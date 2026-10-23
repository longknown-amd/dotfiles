---
name: code-walkthrough
description: Explain code as an interactive, verifiable HTML walkthrough published to the docs site. FEATURE mode explains how a feature works (Python or C/C++). It places the feature in the system, gives a guided step-through with code at file:line, animates replays of real cases run through today's code, and adds deep-dive code pages with call maps linked 1:1 to annotated blocks, plus quizzes. REVIEW mode explains a commit, a range, or staged/unstaged diffs. It groups hunks by intent, renders diffs from git, links a change map 1:1 to hunk cards, and adds per-hunk notes, verified findings and an optional parent-vs-change replay. Use it when the user asks to "explain / walk me through / help me understand how <feature> works", to onboard onto unfamiliar code, for a code tour or feature explainer, or to "help me review / understand this commit / diff / PR / my staged changes".
---

# Code walkthrough

Turn code into a two-layer explainer: an **overview page** that builds the mental model, and **code pages**
that show the real code (or diff) block by block, each block explained. Every quoted line is pulled from git
or the repo by the builders, and every claim cites code or is marked unverified.

## Pick the mode

| The user asks… | Mode | Overview (`<slug>.html`) | Code pages (`<slug>/<page>.html`) |
|---|---|---|---|
| "How does `<feature>` work?", onboarding, code tour | **feature** | where it sits → 60-second version → guided scenarios → real-case replays → deep dives → switches, gotchas, where to start reading, quiz, glossary | one per deep dive: call map ↔ verbatim code blocks, quiz |
| "Help me review / understand commit `<sha>`, `A..B`, my staged or unstaged changes" | **review** | the commit → where it lands → change in 60 s, with a before/after table → theme cards → verified findings → tests → files | one per theme: change map ↔ git-diff hunk cards with notes and a checklist |

**Options:**
- **Review mode:** the real before/after replay and the test runs are **off unless asked** ("with replay", "run the tests").
- **Feature mode:** replays are on, using real inputs; ask the user when a run needs their environment (rule 3).

The method follows the C4 zoom levels (system → component → code), code-reading.org's "map first, trace one
real path, confirm with real data", CodeTour-style `file:line` stops, and mermaidiff-style evidence per claim.

## Hard rules

1. **Never hand-copy code or diffs into a page.** Code enters only as `(file, start, end)` at a pinned commit, and
   diffs only as hunk ids from `difflib_git.py`. The builders read both from git or the repo.
2. **Verify before you write.** Spot-check every agent's key `file:line` claims and its top findings with grep or
   sed. Anything unverified goes in a "Not verified" list, not in the prose.
3. **Replays use real input and real code output only** (`references/replays.md`).
   - **If a replay needs a real job run, hardware, a simulator, credentials, remote hosts, prod data, or repro steps
     you don't have, STOP and ask the user**, with specific questions and a fallback.
   - Label what-if inputs as what-if, and report any difference from production on the page.
4. **Keep the big picture light:** one diagram of ≤10 nodes plus three bullets.
5. **Never write to production systems** while gathering evidence. Don't touch the user's uncommitted work
   without asking; prefer temporary `git worktree`s.

## Cost policy (quality first, then cost)

Set `model` and `effort` on every Agent call exactly as below; this skill is the explicit instruction to do so.

| Role | Agent type | `model` | `effort` |
|---|---|---|---|
| Feature readers | Explore | `sonnet` | `medium` |
| Feature spec writers, review theme writers | general-purpose | `sonnet` | `medium` |
| Mechanical work: JSON edits, map↔entry linking, relabels | general-purpose | `haiku` | `low` |
| Scope, hunk grouping, synthesis, spot-checks, findings verification, evals, overview prose, replays | main thread | inherited | inherited |

- **Escalate only a failing slice:** if a report contradicts your spot-checks, or leaves core logic UNVERIFIED,
  re-run that slice with `opus`/`high`, or verify it yourself.
- **Sizing:**
  - 3 readers by default, 4–5 only when there are more than 4 subsystems and no design doc.
  - Use thoroughness "medium" when a reference doc exists.
  - Cap reader reports at about 1,200 words and writer replies under 150 words.
  - Writers get verified line lists and must not re-explore.
- **Main-thread hygiene:**
  - Use `grep`/`sed -n` ranges, never whole large files.
  - Prefer text checks (`check_render.py`, `run_evals.py`, builder warnings) over screenshots; take 1–2 cropped
    screenshots per page *type*.
  - Run long builds with `run_in_background`, never `sleep`-poll.
  - Don't restate agents' reports.

Templates for every agent role are in `references/agent-prompts.md`.

## Feature mode workflow

0. **Scope:**
   - Pin the repo, the commit (`git rev-parse --short HEAD`), the topic folder and a `<slug>`.
   - Scratch dir: `/tmp/<slug>-build/` with `specs/`, `gen_overview.py`, `prep_replays.py` and `evals.json`.
1. **Read:** launch 3 readers in one message, with non-overlapping slices, one of them covering the
   **surrounding system**. Meanwhile, look for real replay inputs (fixtures, captured samples, local logs).
2. **Synthesize and verify:**
   - Spot-check the lines you'll rely on.
   - Choose the one-sentence summary, 2–3 scenarios, 3–6 deep dives and the gotchas.
   - **Write `evals.json` now**, with 12–20 regex facts, before any page exists.
3. **Spec writers**, one per deep dive, following `references/walkthrough-spec.md`:
   - 8–14 blocks in execution order
   - a call map with a `node` on every block, plus `nodes` roles and defs
   - 2–3 quiz questions
4. **Replays:** `prep_replays.py` runs the real functions on the real inputs and writes `<slug>/replays.js`.
   - When internals are too slow to trace (e.g. a debug build under gdb), use **A/B runs that differ in one
     parameter**, and replay their own logs and counters.
5. **Overview:** generate `overview.json` with `gen_overview.py`, following `references/overview-spec.md`.
   - Scenario steps cite verified spec blocks by (page, block#).
   - Deep dives use `code-ref`, `mermaid-host`, `replay-host` and a `walk` button.
6. **Build, check, look** (commands below). Fix every ERR, then check the pages yourself:
   - code is legible, diagrams aren't squeezed
   - replays advance and scroll
   - map boxes open their cards
7. **Publish** (below).

## Review mode workflow

1. **List hunks:** `difflib_git.py --repo R <sha|A..B|staged|worktree>`. Read the commit message.
2. **Main thread: group hunks into 4–8 themes by intent**, usually matching the commit-message bullets, with tests
   as their own theme.
   - Slice big hunks by new-side line `range` at function boundaries.
   - Write `skeleton.json` and run `build_review.py` until **every changed line is covered exactly once**,
     before any writer starts.
3. **(Only if asked) real before/after:**
   - Check out the parent and the change as temporary worktrees.
   - Run the changed functions on the **same real input** in both.
   - Run the tests on both sides and separate pre-existing failures. For staged or unstaged diffs, "after" is the working tree.
4. **Theme writers** (`references/review-spec.md`) fill in titles, before→after explanations, notes
   (risk / question / test / nit / good) and checklists, plus the **change map with `nodes` and a `node` per entry**.
   They never touch `hunk`/`range`.
5. **Main thread:**
   - Merge, and assert that hunk/range/order are unchanged.
   - Build: the builder auto-attaches functions whose bodies contain an entry's changes, links cross-theme
     functions (`see <theme> #k`), and warns on unlinked new or changed functions and stray `+L`/`−L` citations.
   - **Verify the top 4–8 risk and question notes against the code**, and fix mis-tagged notes.
6. **Overview** (`gen_review_overview.py` pattern, fed by `review_summary.json`). The findings table links each
   verified finding to its hunk card.
7. **Build, check, publish**, then remove the worktrees.

## Build and check

```bash
S=~/.claude/skills/code-walkthrough/scripts
# feature mode
python3 $S/build_pages.py    --repo R --commit C --github G --out OUT/<slug> --parent ../<slug>.html \
        --parent-title "<Feature> overview" --order a,b,c specs/*.json
# review mode
python3 $S/build_review.py   --repo R --source <sha|A..B|staged|worktree> --github G \
        --out OUT/<slug> --parent ../<slug>.html --parent-title "Review overview" review.json
# both
python3 $S/build_overview.py --repo R --commit C --github G --out OUT/<slug>.html overview.json
python3 $S/check_render.py OUT/<slug>.html OUT/<slug>/*.html     # diagrams render, no JS errors
python3 $S/run_evals.py evals.json OUT/<slug>.html OUT/<slug>/*.html   # feature mode
```

**Headless tips:**
- Use a tall window (1500×9000) and crop with PIL; scrolling to an anchor renders blank.
- To test clicks, inject `setTimeout(...)` clicks into a temp copy of the page.

## Publish

Follow the user's docs setup: the `gen-doc` skill's workflow; the docs host, repo and URL are defined in `~/.claude/CLAUDE.md`:
- Write `docs/<topic>/<slug>.html` plus `<slug>/`.
- Add a nav entry with an absolute path: `"<Title> (interactive)": /<topic>/<slug>.html`.
- Commit with `docs(<topic>): …`. **Push only if the user asked you to publish; otherwise ask first.**
- Retry the push if it reports "ahead", then check that every page returns 200 with `curl`.
- Report: the URL, what's on the page, any unverified points or differences, and anything you need from the user.

## Quality checklist (before reporting done)

**Both modes:**
- [ ] Every code block, scenario step and diff hunk comes from the builders at a pinned revision.
- [ ] Each map box shows its block/change numbers or `see <page> #k`; each card shows its function chip; no
      unexplained "context only" boxes.
- [ ] `check_render.py` passes on every page, and no builder ERR lines remain.

**Feature mode:**
- [ ] Section 0 places the feature in the system (≤10 nodes, feature highlighted).
- [ ] Replays are real or labelled what-if, differences are noted, and blockers were asked about.
- [ ] Quiz: 3–5 questions on the overview, 2–3 per code page, each linking to its evidence.
- [ ] `run_evals.py` passes all facts, and the gotchas list stale docs with paths.

**Review mode:**
- [ ] All changed lines are covered exactly once.
- [ ] Every risk/question in the findings table was verified by the main thread; mis-tagged notes are fixed.
- [ ] Notes cite `+L`/`−L` lines that are visible in their hunk, or the warning was accepted on purpose.
- [ ] The replay and test runs appear only if requested.

## Files

| Path | What |
|---|---|
| `scripts/build_pages.py`, `walkthrough_template.html` | feature code pages (call map, blocks, focus, mini-map, quiz) |
| `scripts/difflib_git.py`, `build_review.py`, `review_template.html` | review mode: hunk parser, theme pages, coverage, citation and linking checks |
| `scripts/build_overview.py`, `overview_template.html` | overview for both modes (step player, replay player, quiz, `code-ref`) |
| `scripts/check_render.py`, `run_evals.py` | headless render check, fact evals |
| `references/walkthrough-spec.md`, `review-spec.md`, `overview-spec.md`, `replays.md`, `agent-prompts.md` | spec contracts and agent templates |
| `examples/` *(local only; never synced, see below)* | worked examples: a Python feature, a C++ feature with A/B real-run replays, a commit review with an opted-in replay |

**`examples/` stays out of the dotfiles repo**: it quotes project-internal code, names and findings. It's excluded
via `~/.dotfiles/info/exclude`. Never force-add it, and keep project-specific names out of the files that are synced.
