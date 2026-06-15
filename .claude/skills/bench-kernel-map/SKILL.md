---
name: bench-kernel-map
description: Use this skill to convert between a hipMicroBench bench test-case name (the strings -bench_filter / -list_bench use, e.g. Atomic_Add_fp32_All_Global) and the GPU kernel name in any form — demangled kentry<...> (rocprof view), mangled device symbol, or KernelImpl type. Trigger when the user asks "which kernel is this bench / this rocprof symbol", "what's the -bench_filter for kernel X", "map bench name to kernel name", or wants to correlate profiler/ISA/ELF kernel symbols back to bench cases, in either direction.
---

# hipMicroBench bench-name ⇄ kernel-name converter

A bundled Python tool (`bench_kernel_map.py`, stdlib only) builds a cached mapping and does
fast bidirectional lookups. The repo is `~/project/hipMicroBench` (the three binaries are
`alu`, `atomic`, `coexec`; plus `latency`, `memCache`, `bandwidth`).

## What "kernel name" means (3 forms, all supported)

| form | example |
|---|---|
| **demangled** | `void hip_bench::kentry<2, hip_bench::AtomicKernel<hip_bench::AtomicAdd, float, hip_bench::ContentionAll, hip_bench::MemGlobal, 16u>, …>(…)` — what rocprof shows |
| **mangled** | `_ZN9hip_bench6kentryILi2ENS_12AtomicKernelI…EEEEvDpT1_` — the device symbol |
| **impl** | `AtomicKernel<hip_bench::AtomicAdd, float, hip_bench::ContentionAll, hip_bench::MemGlobal, 16u>` |

A bench name (`Atomic_Add_fp32_All_Global`) is the `GetTestName()` string; the kernel is the
`kentry<MinBlockPerCu, KernelImpl, KernelArgs>` instantiation wrapping it.

## How it works (so you can reason about edge cases)

- **Kernel side — always offline, exact.** `llvm-nm <binary>` lists every
  `__device_stub__kentry<…>` symbol; demangle with `llvm-cxxfilt`; the real *device* symbol is
  that symbol with `__device_stub__kentry` → `kentry` (verified: `_ZN9hip_bench21__device_stub__kentry…`
  → `_ZN9hip_bench6kentry…`, otherwise byte-identical).
- **Bench-name side — joined on the (normalized) KernelImpl type, from one of:**
  1. **Authoritative (recommended):** a run with `-enable_json_output=true` emits
     `kernel_name` + `kernel_entry.kernel_impl_type` (`include/metadata.hpp`). Exact for every
     category, no re-implementation. Needs the Docker/GPU env once.
  2. **Offline reconstruct (no GPU, best-effort):** re-derives the bench name from the demangled
     KernelImpl type, mirroring each `GetTestName()`. Reliable for plain-typed kernels.

Robustness note: the host `llvm-cxxfilt` is *lossy* for AMD vendor float types — it fails
outright on `__bf16` (`DF16b`, i.e. `bf16_t`) and drops `_BitInt` (`DB8_`/`DU8_` = `fp8_t`/`bf8_t`).
Trusting demangled text would silently DROP those kernels and confuse fp16/bf16. So the tool
parses *type identity from the mangled symbol* (unambiguous) and uses the demangler only for the
human display string (synthesizing it when the demangler fails). Offline reconstruction is
validated exhaustively against the authoritative atomic `-list_bench` (all 380 gfx1310 names
reproduced). Still **prefer the authoritative `--from-json` path for `latency`/`memCache`/
`bandwidth`** (bespoke name formats not reconstructed offline) and to be certain on a new arch.

## Workflow

1. **Pick the build dir / arch.** Binaries live in `build-<arch>/bin/`. The map is arch-specific
   (kernels are arch-gated), so build one map per arch you care about.

2. **Build the map** (merges all binaries into one arch-wide map; run from the repo root):
   ```
   PY=~/.claude/skills/bench-kernel-map/bench_kernel_map.py
   # offline, no GPU — fast, best-effort bench names:
   python3 $PY build-map --binary build-gfx950/bin/atomic build-gfx950/bin/alu build-gfx950/bin/coexec
   ```
   Map is written next to the binary: `build-<arch>/bin/bench_kernel_map.<arch>.json`.

   **Authoritative (exact, all categories)** — feed result JSON(s) from a metadata run. A cheap
   metadata-only run (minimal workload) inside Docker/GPU is enough:
   ```
   ./build-gfx950/bin/atomic -v=0 -dim0=1 -loop_count=1 -warmup=0 -repeat=1 \
       -enable_json_output=true -json_file=atomic_meta.json
   # (repeat for alu/coexec/latency/memCache/bandwidth), then:
   python3 $PY build-map --binary build-gfx950/bin/atomic build-gfx950/bin/alu build-gfx950/bin/coexec \
       --from-json atomic_meta.json alu_meta.json coexec_meta.json
   ```
   Records resolved from JSON show `resolved_by: json`; the rest fall back to reconstruct.

   **Cross-check reconstruction** against the full name set with `--names`:
   ```
   ./build-gfx950/bin/atomic -list_bench -enable_json_output=true -json_file=atomic_list.json   # in Docker
   python3 $PY build-map --binary build-gfx950/bin/atomic --names atomic_list.json
   ```
   (A `-list_bench` JSON is the *full* set; a filtered result JSON is partial, so
   "not-in-reference" against a partial list just means "not exercised", not an error.)

3. **Convert** (the map path is auto-derived from `--binary`, or pass `--map`):
   ```
   python3 $PY to-kernel "Atomic_Add_fp32_All_Global" --binary build-gfx950/bin/atomic
   python3 $PY to-kernel "Atomic_Add_fp32_All_Global" --form mangled --map <map.json>
   python3 $PY to-bench "_ZN9hip_bench6kentry…"        --map <map.json>   # mangled (device or stub)
   python3 $PY to-bench "hip_bench::kentry<2, hip_bench::AtomicKernel<…>>" --map <map.json>
   python3 $PY to-bench "AtomicKernel<hip_bench::AtomicAdd, float, …>"     --map <map.json>
   python3 $PY search "Atomic_CAS_.*_LDS" --map <map.json>
   python3 $PY dump --map <map.json>
   ```
   `to-bench` accepts any of the three kernel forms; mangled input is auto-demangled. `to-kernel`
   accepts a regex for the bench name too.

## Environment notes

- Tools: needs `llvm-nm` + `llvm-cxxfilt` (prefers `/opt/rocm/llvm/bin`, falls back to PATH /
  GNU `nm`/`c++filt`). `llvm-cxxfilt` demangles the newer types GNU `c++filt` chokes on.
- Binaries built in the project's Docker (ROCm 7.x) often can't *execute* on the host (glibc),
  but `llvm-nm` reads them statically — so **map building works on the host**; only the
  authoritative `--from-json` / `--names` runs need the Docker/GPU env.

## Bench-name format reference (what reconstruction mirrors)

Prefix + `_`-joined tags. Types via `DataTypeTraits<T>::name` (`float`→`fp32`, `double`→`fp64`,
`int`→`i32`, `unsigned int`→`u32`, fp16/bf16/fp8/bf8, mx_* and scale e8m0/e5m3/e4m3, i4/fp4);
vectors get an `xN` suffix; coexec appends a schedule (`Interwave`/`Intrawave`/`Wavegroup`).

| KernelImpl | bench format |
|---|---|
| `AtomicKernel<Op,T,Cont,Mem,U>` | `Atomic_{op}_{T}_{cont}_{mem}` |
| `TransKernel<Op,T,V,U>` | `Trans_{op}_{T[xV]}` |
| `AluKernel<Op,T,V,U>` (valu) | `Valu_{op}_C_{T[xV]}_A_{T[xV]}` |
| `MMaKernel<M,N,K,C,A,B,U>` | `Mma_{M}x{N}x{K}_C_{C}_A_{A}_B_{B}` |
| `MxMmaKernel<M,N,K,S16,A,B,SA,SB,C,U>` | `MxMma_{M}x{N}x{K}[_S16]_A_{A}_{SA}_B_{B}_{SB}` |
| `WcnnKernel<H,W,D,Wt,Acc,F,It,Dil,U>` | `Wcnn_{H}x{W}_F{F}_{I{It}|Dil{Dil}}_C_{Acc}_D_{D}_W_{Wt}` |
| `WcnnTileKernel<H,W,D,Acc,Cfg,U>` | `WcnnTile_{tileop}_{H}x{W}_C_{Acc}_D_{D}` |
| `CoexecAluAluKernel<O0,O1,P0,P1,V0,V1,Sch,U>` | `CoAluAlu_{O0}_{P0[xV0]}_{O1}_{P1[xV1]}_{sch}` |
| `CoexecMmaAluKernel<M,N,K,C,A,B,AluOp,AT,AV,Sch,U>` | `CoMmaAlu_{M}x{N}x{K}_C_{C}_A_{A}_B_{B}_{aluop}_{AT[xAV]}_{sch}` |
| `CoexecMxMmaAluKernel<…,AluOp,AT,AV,Sch,U>` | `CoMxMmaAlu_{M}x{N}x{K}[_S16]_A_{A}_{SA}_B_{B}_{SB}_{aluop}_{AT[xAV]}_{sch}` |
| `CoexecWcnnAluKernel<…,AluOp,AT,AV,Sch,Dil,U>` | `CoWcnnAlu_{shape}_C_{Acc}_D_{D}_W_{Wt}_{aluop}_{AT[xAV]}_{sch}` |
| `CoexecWcnnWcnnTileKernel<…,Cfg,Sch,Dil,U>` | `CoWcnnWcnnTile_{shape}_C_{Acc}_D_{D}_W_{Wt}_{tileop}{sch}` |

`latency` / `memCache` / `bandwidth` use bespoke `GetTestName(...)` signatures — covered by the
authoritative `--from-json` path; offline reconstruction leaves them `<unresolved>` (rebuild
with `--from-json` to fill them). If `to-bench` matches a kernel whose name is `<unresolved>`,
that's the signal to do an authoritative run.
