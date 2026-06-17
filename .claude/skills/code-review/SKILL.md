---
name: code-review
description: Review the current diff for bugs. Default mode is fast inline review (no agents). Pass --full for the deep multi-agent review with 7 finder angles, parallel verify, and ranked findings.
---

# Code Review

Parse args to determine mode:
- `--full` or `--deep` → **Full review** (multi-agent, see below)
- `--comment` → post findings as PR comments (combine with either mode)
- `--fix` → apply fixes after review (combine with either mode)
- anything else (or no args) → **Quick review**

---

## Quick review (default)

Run `git diff @{upstream}...HEAD` to get the diff. If empty or no upstream, run `git diff HEAD`. Also include uncommitted changes (`git diff HEAD`).

Read the diff directly — no agents. For each hunk, read the surrounding function context if needed. Report only high-confidence correctness bugs: wrong logic, off-by-one, inverted condition, mismatched types, bad packing/masking, dropped error, wrong variable in copy-paste. Skip style, nitpicks, and anything a linter or compiler would catch.

Output: a short bulleted list of findings (file:line + one sentence each). If nothing stands out, say so in one line. Cap at 5 findings max.

---

## Full review (--full or --deep)

Run `git diff @{upstream}...HEAD` (fallback: `git diff HEAD`) to get the diff.

### Phase 1 — Find candidates

Run **7 independent finder angles** via the Agent tool in parallel. Each returns up to 6 candidates with `file`, `line`, `summary`, `failure_scenario`.

- **Angle A — line-by-line scan**: Read every hunk and the enclosing function. What input/state makes this line wrong? Look for inverted conditions, off-by-one, null deref, wrong-variable copy-paste, swallowed errors, bad bit-masks.
- **Angle B — removed-behavior**: For every deleted line, name the invariant it enforced. Check if the new code re-establishes it.
- **Angle C — cross-file tracer**: Find callers of changed functions. Check if the change breaks any call site or introduces a new precondition.
- **Angle D — reuse**: Does the new code re-implement something that already exists? Name the existing helper.
- **Angle E — simplification**: Redundant state, copy-paste variants, unnecessary complexity. Name the simpler form.
- **Angle F — efficiency**: Wasted work in hot paths. Flag only if egregious.
- **Angle G — altitude**: Is the fix a bandaid on shared infrastructure instead of a proper fix?

### Phase 2 — Verify (1-vote, recall-biased)

Dedup near-duplicates. For each remaining candidate, spawn one verifier agent: returns CONFIRMED / PLAUSIBLE / REFUTED. Keep CONFIRMED and PLAUSIBLE; drop REFUTED. PLAUSIBLE by default — refute only when provably impossible (quote the actual line/constant/type that rules it out).

### Output

JSON array ranked by severity, max 10 findings:
```json
[{"file": "...", "line": 123, "summary": "...", "failure_scenario": "..."}]
```
Then render the findings as a brief bulleted report.

If `--comment` is present, post findings as inline PR comments via `gh`.
If `--fix` is present, apply findings to the working tree after the report.
