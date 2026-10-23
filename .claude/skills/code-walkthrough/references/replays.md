# Real-case replays

A replay animates **real input → today's code → real output**: the active diagram box lights
up, the log lines the code reads are highlighted, and a "Result so far" panel fills in. It is
the strongest evidence on the page, so it must never be invented.

## Where real inputs come from (cheapest first)

1. **Artifacts already in the repo:**
   - test fixtures, e.g. `tests/**/fixtures/*`
   - captured prompts and samples, e.g. `docs/prompt_samples/*`
   - example logs and reports under `logs/` (local, read-only use)
2. **Pure functions you can run locally on those inputs.** Import the module and call the real function with `PYTHONPATH` set; for C/C++, use a small driver or a unit-test binary. Record its actual return values.
3. **Read-only queries the user has already sanctioned**, such as a dashboard API they named. Respect read-only rules: never write to production systems.
4. **Running a real job or workload** (hardware, simulators, containers, remote hosts, credentials). **Don't do this yourself.** See *Blockers*.

## Blockers: stop and ask the user

If a replay needs something you can't do safely or don't have, **stop and ask**. Don't fake it
and don't silently drop it. Ask specific questions and offer a fallback. Typical blockers:

- the environment: which host, container image, venv or module path, GPU or simulator, and whether you may run it
- repro steps: the command line, the config or suite file, the job id to copy
- access: logs or DBs you can't reach, credentials, VPN-only services
- data: no fixture or capture exists for the path you want to show
- cost or risk: the run takes a long time, uses shared hardware, or writes anywhere

Example question:
> To replay the job-level path on a real failure I need a full job log. Can you point me to
> one (path or job id plus how to fetch it), or should I replay on the 107 lines captured in
> `docs/prompt_samples/…` instead?

Until the user answers, ship the page without that replay, or with a replay on the partial
data you do have, labelled as such.

## When internal values are too expensive to capture

Debug builds under a debugger can be orders of magnitude slower than release. In one C++ simulator
case, the debug build under gdb made no visible progress in 10 minutes, while a whole release run took 9.
Before committing to a trace:
- Measure the debug run's speed, e.g. from its perf-counter dump rate.
- If it's impractical, switch to an **A/B pair of release runs that differ in exactly one parameter**
  (or one flag or commit), and replay their own logs and counters at real line numbers.
- A single toggled switch that flips PASS↔FAIL, with counters explaining why, is strong evidence.
- Say on the page what wasn't captured, and why.

## Honesty rules

- Every value shown as a *result* must come from running real code on real input.
- Hypothetical inputs, such as an LLM reply that wasn't captured, are allowed only when the caption says **what-if**, and the result shown is still real code output for that input.
- Put a `note` on every replay saying where the input came from, what was run, and any difference from production. Report a difference, never smooth it over (e.g. "today's code finds 5 cascades, but the capture says 0").
- Commit the data-prep script beside the specs (`examples/<feature>/prep_replays.py`) so the replay can be regenerated when the code changes.

## Data format (`window.REPLAYS = [...]` in `<slug>/replays.js`)

```json
{
  "id": "r1", "job": 1234,
  "title": "Job 1234: the build broke, zero tests ran",
  "subtitle": "<target> · <config> · suite.json",
  "log_title": "job log: the lines the code read (real)",
  "log": [[206, "line text"], [207, "…"]],
  "frames": [
    {"node": "B", "caption": "HTML, one or two sentences",
     "hl": [498], "focus": 498, "tags": {"498": "BUILD_FAILED"},
     "set": {"blocker": "BUILD_FAILED @ L498"},
     "code": "<slug>/blocker.html#b7",
     "swap": {"title": "digest", "log": [[1, "…"]]}}
  ],
  "note": "provenance + differences from production"
}
```

How the frame fields behave:
- `log` holds `[line_no, text]` pairs. Gaps in the numbering render as "⋮ N lines not shown", so keep the original line numbers.
- `set` and `tags` accumulate from frame to frame. `hl` and `focus` apply to the current frame only.
- `swap` replaces the log from that frame on (e.g. raw dump → digest).
- `node` refers to the overview's `walk_diagram`. Use `null`, and `data-diagram="0"`, for replays that don't follow the pipeline.
- `code` deep-links to the walkthrough block that does this step.

Aim for 6–11 frames per replay. Write captions in plain English and quote the real values.
Use one or two replays in the tabbed section (one per main path), and optionally one inline replay
in a deep dive (e.g. a transformation such as raw output → digest).
