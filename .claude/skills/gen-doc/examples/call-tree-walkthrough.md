<!-- Approved example of a code-path walkthrough with call trees (STYLE.md section 3a).
     Source: http://thohuang-pc:8000/troubleshooting/xattention-hipfreeasync-exit-hang.html (docs commit 823b1a9),
     the subsection "A hipFreeAsync marker reaches DTIF in six steps". Copied verbatim; it sits inside a postmortem,
     so its headings are ### / ####. In a standalone explanation page use ## / ###. -->

### A `hipFreeAsync` marker reaches DTIF in six steps, across four threads

The blocked register write is the last step of a path that starts in the test's own `hipFreeAsync` call. Four threads take part:

| Thread | What it does on this path | State in a hung process |
|---|---|---|
| Main (application) | Calls `hipFreeAsync`, which submits the marker. Later runs `exit()` and HIP's teardown | Spinning in `sched_yield` under `__cxa_finalize` |
| DTIF clock thread (`TestMain`) | Runs the FFM model, and serves every command posted through `m_cmdBlock` | Gone: it exited |
| ROCr async-signals thread (`AsyncEventsLoop`) | Polls completion signals and runs their handlers, one at a time | Blocked in `Dtif::WaitForEvent` |
| ROCr async-exceptions thread (`AsyncEventsLoop`) | Watches exception signals only | Idle in `usleep` |

The whole path, in order:

```text
main thread        (1) hipFreeAsync → timing-enabled marker
                   (2) marker → AQL barrier packet + completion signal (value 1) + one-shot handler
                   (3) doorbell → hsaKmtQueueRingDoorbell → SendCmdBlock ──────────────┐
DTIF clock thread      RING_DOORBELL command → model HQD doorbell  ◀───────────────────┘
                   (4) model CP runs the barrier during Stall(128): writes start/end timestamps, value 1 → 0
ROCr async thread  (5) AsyncEventsLoop polls, sees value 0 → HsaAmdSignalHandler
                   (6) timestamps → TranslateTime → hsaKmtGetClockCounters → TCoreWriteRegister
                       → SendCmdBlock → sem_wait forever   (the race above)
```

The sections below take one step each. Each gives the short version first. The full call tree, with `file:line` for every frame, is in the toggle. HIP and ROCr paths are relative to `clr` and `rocr-runtime/runtime/hsa-runtime/core` at `c9ee70b280`. DTIF paths are relative to `src/` at `ecd41d0`.

#### 1. `hipFreeAsync` does not free; it queues a timing-enabled marker

`MemoryPool::FreeMemory` keeps the memory in the pool's free heap and records a marker on the stream. The pool reuses the memory once that marker completes. The marker's event is created with flags `0`, so **timing is enabled**: `hipEventDisableTiming` is not set. That one flag is why a free ends up reading GPU timestamps.

```text
hipFreeAsync → Device::FreeMemory → MemoryPool::FreeMemory → new hip::Event(0) → Event::addMarker(stream)
```

<details markdown="1">
<summary>Full call tree: step 1</summary>

```text
hipFreeAsync(dev_ptr, stream)                                  hipamd/src/hip_mempool.cpp:137
└─ hip::Device::FreeMemory(memory, stream, event)              hipamd/src/hip_device.cpp:99   (called at hip_mempool.cpp:177)
   └─ MemoryPool::FreeMemory(memory, stream, event=nullptr)    hipamd/src/hip_mempool_impl.cpp:245
      ├─ ts.AddSafeStream(stream)
      ├─ Event* e = new hip::Event(0)                          :311   flags 0 = timing enabled
      ├─ e->addMarker(stream, nullptr)                         :312   → step 2
      ├─ ts.SetEvent(e)                                              the pool checks this event before reuse
      ├─ e->ready()                                            :315
      └─ free_heap_.AddMemory(memory, ts)                      :322

Event::addMarker → Event::recordCommand                        hipamd/src/hip_event.cpp:254 → :190
└─ enable_profiling = !(flags & hipEventDisableTiming)                 → true
└─ new hip::EventMarker(*stream, kFlushCache=false, kMarkerTs=true,
                        releaseFlags=kCacheStateInvalid, batch_flush, enable_profiling=true)
   hipamd/src/hip_event.hpp:75   (an amd::Marker with profilingInfo_.enabled_ = marker_ts_ = true)
```

Timing-enabled records are also not eligible for marker coalescing. Only `hipEventDisableTiming` records get a coalesce id (`hip_event.cpp:218-225`).

</details>

#### 2. The marker becomes an AQL barrier packet with a completion signal and a one-shot handler

HIP submits directly from the calling thread; there is no worker thread. The marker becomes a barrier-AND packet. On gfx1250 it is a plain barrier packet, because the barrier-value packet is enabled only for gfx90a and gfx94x (`rocclr/device/rocm/rocsettings.cpp:151-155`). Before writing the packet, HIP takes a completion signal and registers a handler for it:

- The signal starts at **1**. The handler is registered with ROCr for condition "value < 1", i.e. "run `HsaAmdSignalHandler` once the packet completes". It runs once.
- The handler's argument is the command's `Timestamp`, which now owns this signal for timing.
- **On DTIF the signal has no interrupt.** `HSA_ENABLE_DTIF=1` sets `g_use_interrupt_wait = false` (`runtime/amd_topology.cpp:315-317`), so ROCr creates a plain memory signal (`runtime/hsa_ext_amd.cpp:1025`). Nobody will be woken when it changes; someone has to poll it (step 5).

```text
Command::enqueue → VirtualGPU::submitMarker → dispatchBarrierPacket
  ├─ ActiveSignal(1, timestamp_) → signal = 1; hsa_amd_signal_async_handler(sig, LT, 1, HsaAmdSignalHandler, ts)
  └─ ringQueueDoorbell(index)  → step 3
```

<details markdown="1">
<summary>Full call tree: step 2</summary>

```text
Event::enqueueRecordCommand(stream, command)                   hipamd/src/hip_event.cpp:234
└─ amd::Command::enqueue()                                     rocclr/platform/command.cpp:382
   │  AMD_DIRECT_DISPATCH: submitted on the caller's thread
   ├─ queue_->FormSubmissionBatch(this)                        :415
   ├─ CL_COMMAND_MARKER → EnableProfiling()                    :421
   ├─ SetBatchHead(queue_->GetSubmissionBatch())               :424   this marker now tracks the batch
   └─ submit(*queue_->vdev())                                  :426
      └─ Marker::submit → device.submitMarker(*this)           rocclr/platform/command.hpp:1720
         └─ VirtualGPU::submitMarker(vcmd)                     rocclr/device/rocm/rocvirtual.cpp:5399
            ├─ profilingBegin(vcmd)                            :2887  timestamp_ = new Timestamp(this, cmd);
            │                                                         cmd.data().emplace_back(timestamp_)
            └─ dispatchBarrierPacket(kBarrierPacketHeader, false)   :2256
               ├─ ReserveAqlSlots(1) … CompleteAqlSubmission
               ├─ completion_signal = Barriers().ActiveSignal(kInitSignalValueOne, timestamp_)   :2290
               │  └─ HwQueueTracker::ActiveSignal                     :754
               │     ├─ enqueHandler = (Callback() || GetBatchHead()) && !CpuWaitRequested()   :813-817 → true
               │     ├─ CreateSignal(sig, use_irq=true)               :833 → :709
               │     │  └─ hsa_amd_signal_create → DefaultSignal on DTIF   rocr: runtime/hsa_ext_amd.cpp:1025
               │     ├─ signal_silent_store_relaxed(sig, 1)           :846
               │     ├─ ts->AddProfilingSignal(prof_signal)           :859
               │     └─ Hsa::signal_async_handler(sig, LT, 1, &HsaAmdSignalHandler, ts)   :878
               │        └─ hsa_amd_signal_async_handler               rocr: runtime/hsa_ext_amd.cpp:1195
               │           └─ Runtime::SetAsyncSignalHandler          rocr: runtime/runtime.cpp:970
               │              ├─ new_events.PushBack(signal, cond, value, handler, arg)
               │              └─ control.wake->StoreReleaseAndNotify(1)   wake AsyncEventsLoop
               ├─ writePacketToRingBuffer(aql_loc, &barrier_packet_, …)
               └─ ringQueueDoorbell(index)                           :2308 → step 3
```

</details>

#### 3. The doorbell is itself a DTIF command, served by the clock thread

There is no hardware doorbell on the simulator. ROCr's queue doorbell, on DTIF, calls `hsaKmtQueueRingDoorbell`. That posts a `RING_DOORBELL` command through the same `m_cmdBlock` handshake that the register write uses later. The clock thread picks it up and writes the doorbell of the model's hardware queue (HQD). The process runs with `DtifAqlMode=0` (`AQL_DOORBELL`) and `DtifModel=ffm_mono`, so the model's command processor reads the AQL ring itself; DTIF's AQL-to-PM4 translator is not used.

```text
ringQueueDoorbell → AqlQueue::StoreRelease → hsaKmtQueueRingDoorbell → SendCmdBlock
   clock thread: TCoreProcessCommand → AqlUserQueue::RingDoorbell → Handle → HalGpu::DoorbellWrite
```

<details markdown="1">
<summary>Full call tree: step 3</summary>

```text
VirtualGPU::ringQueueDoorbell(index)                           rocclr/device/rocm/rocvirtual.cpp:1474
└─ Hsa::signal_store_screlease(gpu_queue_->doorbell_signal, index)   :1478   (DEBUG_CLR_DIRECT_DOORBELL is off by default)
   └─ AqlQueue::StoreRelease → StoreRelaxed                    rocr: runtime/amd_aql_queue.cpp:512 → :499
      └─ IsDTIF() → hsaKmtQueueRingDoorbell(queue_id_, value)  :502
         └─ DTIF hsaKmtQueueRingDoorbell                       hsakmt/queues.cpp:274
            ├─ m_cmdBlockMutex.lock(); m_cmdBlock = {HSA_QUEUE_NOTIFY, RING_DOORBELL, queue}
            └─ SendCmdBlock()                                  dtifCModel.cpp:1272   check :1277, post :1296, wait :1302

TestMain clock loop (clock thread)                             dtifCModel.cpp:2260-2300
├─ TimedWaitForEvent(m_clockSignalEvent, 0)                    :2263   non-blocking poll
├─ TCoreProcessCommand(pDtif, &m_cmdBlock)                     :2271
│  └─ RING_DOORBELL → HsaUserQueue::RingDoorbell()             dtifCModel.cpp:1157
│     └─ AqlUserQueue::RingDoorbell()                          hsakmt/aqluserqueue.cpp:250
│        └─ CheckAqlPacket(); Handle()                         :339
│           └─ FFM_MONO: HalGpu::DoorbellWrite(hqd->Doorbell(), write_index_)
├─ SignalEvent(m_clockAcknowledgeEvent)                        :2272
├─ exit flag set? → break                                      :2290-2295
└─ pHost->Stall(128)                                           :2298   advance the model 128 clocks
```

</details>

#### 4. The FFM model completes the packet; the #908 exit release cannot cause this hang

**Normally the model's command processor sets the signal.** It runs inside `pHost->Stall(128)` on the clock thread. It fetches the barrier packet from the ring, writes the `start_ts`/`end_ts` fields of the signal, and decrements its value from 1 to 0. On this path DTIF itself never writes the signal value: in the AQL_DOORBELL code, the only write to it is the exit release below. The model source is not in this investigation (package `model_sha 2dd01db1`), so the model side is described, not cited.

**At exit, #908 can release the signal instead.** `SetExit()` → `AqlUserQueue::SignalAllPending` (`hsakmt/aqluserqueue.cpp:59`) → `SignalPendingPacketsOnExit` (`:274`) stores 0 into the signal of every doorbelled packet the model never read (`:323`). It writes no timestamps.

That release cannot produce the hang. `SetExit()` sets `m_exitFlag` **before** it calls `SignalAllPending`. A handler started by the release therefore finds the flag set at `SendCmdBlock`'s check (`:1277`) and returns early. The hang needs a marker the **model** completed, whose handler passed that check before exit began.

#### 5. `AsyncEventsLoop` finds the completed signal by polling, then runs the handler on its own thread

ROCr's async-signals thread holds the list of registered signals. On DTIF none has a kernel event, so it cannot sleep in the kernel driver. It scans the values, and when a condition holds it calls the handler. The handler returns `false` ("don't call me again"), so the loop drops the signal. Between scans it naps: 20 µs at first, doubling up to 2 ms (`util/poll_backoff.h:26-32`). That is the `usleep` in the second `AsyncEventsLoop` thread of every hung process.

Handlers run **one at a time on this one thread**. Once a handler blocks, no other completion handler in the process runs. That includes the `~AqlQueue` handshake behind the patch B hangs.

```text
AsyncEventsLoop: load value → CheckSignalCondition(0 < 1) → processEvent → handler(value, ts) = HsaAmdSignalHandler
```

<details markdown="1">
<summary>Full call tree: step 5</summary>

```text
Runtime::AsyncEventsLoop(asyncSignals_)                        rocr: runtime/runtime.cpp:2061
while (!control.exit):
├─ flag().wait_any() is false (HSA_WAIT_ANY_DEBUG unset)        util/flag.h:320
│    → index = 1, wait_any = false: skip WaitMultiple, scan from slot 1 (slot 0 is the wake signal)
├─ for each registered signal i:
│    value = atomic::Load(&sig->signal_.value)
│    CheckSignalCondition(value, LT, 1)?
│    ├─ yes → processEvent(i, value, …)                         :2209 → :2073
│    │        └─ keep = handler_[i](value, arg_[i])             :2077   → HsaAmdSignalHandler(value, ts)
│    │           └─ keep == false → Release signal, CopyIndex/PopBack
│    └─ no  → PrepareInterrupt(i)                               :2221
│             └─ no EopEvent (plain signal on DTIF) → polling = true
├─ polling && !finish → os::uSleep(poll_nap_us)                 :2298   20 µs … 2000 µs
└─ move new_events (step 2 registrations) into the scan list
```

</details>

#### 6. The handler converts the marker's timestamps, and that conversion is a register write to DTIF

`HsaAmdSignalHandler` updates the state of every command in the marker's batch. To give each command a start and end time, it asks ROCr to translate the signal's GPU timestamps into host time. ROCr does that by sampling the GPU and host clocks together. When a timestamp is beyond the range it can extrapolate, it resamples them (`SyncClocks`). On DTIF, sampling the GPU clock is `hsaKmtGetClockCounters`. Its hardcoded-clock workaround applies only when the model is `TB_CSIM` (`hsakmt/time.cpp:48-60`), so on FFM it falls through to real register access:

```cpp
// hsakmt/time.cpp @ecd41d0
182          } else {
183              TCoreWriteRegister(mmRLC_CAPTURE_GPU_CLOCK_COUNT, 1);       // goes to the clock thread
185              const uint32_t clockCountLow  = TCoreReadRegister(mmRLC_GPU_CLOCK_COUNT_LSB);
186              const uint32_t clockCountHigh = TCoreReadRegister(mmRLC_GPU_CLOCK_COUNT_MSB);
```

`TCoreWriteRegister` takes `m_cmdBlockMutex` and calls `SendCmdBlock()`. If exit started between that call's flag check and its post, this is the stranded command from the race table above. The mutex stays held, the handler never returns, and the marker is never marked complete.

```text
HsaAmdSignalHandler → updateCommandsState → Timestamp::getTime → checkGpuTime → ExtractSignalTiming
  → CacheTimingData → hsa_amd_profiling_get_dispatch_time → GpuAgent::TranslateTime → SyncClocks
  → hsaKmtGetClockCounters → TCoreWriteRegister(0xec26, 1) → SendCmdBlock → WaitForEvent (sem_wait)
```

<details markdown="1">
<summary>Full call tree: step 6, matched to a live backtrace</summary>

```text
HsaAmdSignalHandler(value, ts)                                 rocclr/device/rocm/rocvirtual.cpp:544
├─ gpu->updateCommandsState(ts->command().GetBatchHead())      :559
│  └─ VirtualGPU::updateCommandsState(list)                    :3020
│     ├─ ts->getTime(&start, &end)                             :3045
│     │  └─ Timestamp::getTime                                 rocvirtual.hpp:146
│     │     └─ Timestamp::checkGpuTime(nullptr)                rocvirtual.cpp:389
│     │        └─ ExtractSignalTiming(sig, …)                  :416 → :483
│     │           └─ sig->CacheTimingData(gpu_device)          :488 → :356
│     │              └─ Hsa::profiling_get_dispatch_time(agent, signal_, &time)   :378
│     │                 └─ hsa_amd_profiling_get_dispatch_time        rocr: runtime/hsa_ext_amd.cpp:912
│     │                    └─ GpuAgent::TranslateTime(signal, time)   rocr: runtime/amd_gpu_agent.cpp:3523
│     │                       ├─ raw start/end = 0 or before t0 → return 0, no clock read
│     │                       └─ TranslateTime(end)                   :3567
│     │                          └─ beyond extrapolation → SyncClocks()      :3584 / :3608 → :3653
│     │                             └─ KfdDriver::GetClockCounters           rocr: driver/kfd/amd_kfd_driver.cpp:1003
│     │                                └─ hsaKmtGetClockCounters             DTIF hsakmt/time.cpp:133
│     │                                   └─ TCoreWriteRegister(0xec26, 1)   :183 → dtifCModel.cpp:2488
│     │                                      ├─ m_cmdBlockMutex.lock()       :2504   held while blocked
│     │                                      └─ SendCmdBlock()               :2511 → :1272
│     │                                         ├─ exit flag false → pass    :1277
│     │                                         ├─ sem_post("command posted")  :1296
│     │                                         └─ sem_wait("command done")    :1302 → WaitForEvent :239   ◀ blocked
│     └─ (not reached) marker: CL_SUBMITTED → CL_RUNNING → CL_COMPLETE      :3081-3083
└─ (not reached) ReleaseHwQueue; QueuedAsyncHandlers()--; AsyncHandlersInFlight()--
```

The same chain in a natural hang (PID 28940, stock `ecd41d0`, X-Attention full suite):

```text
#2  Dtif::WaitForEvent              dtifCModel.cpp:239
#3  Dtif::TCoreWriteRegister        offset=60454 (0xec26), value=1   dtifCModel.cpp:2511
#4  hsaKmtGetClockCounters          time.cpp:183
#5  rocr::AMD::KfdDriver::GetClockCounters
#6  rocr::AMD::GpuAgent::TranslateTime(unsigned long)            (SyncClocks inlined)
#7  rocr::AMD::GpuAgent::TranslateTime(Signal*, dispatch_time&)
#8  rocr::AMD::hsa_amd_profiling_get_dispatch_time
#9-#15  libamdhip64.so.7 ?? (7 frames, stripped)                  HsaAmdSignalHandler … CacheTimingData
#16 rocr::core::Runtime::AsyncEventsLoop
```

Frames #9-#15 are stripped. Assigning them to the `clr` functions above follows the code, not symbols.

</details>

So every `hipFreeAsync` marker that completes near exit sends DTIF register commands from the ROCr thread, at the moment the model is shutting down. A plain `hipFree` creates no marker and no timing callback.
