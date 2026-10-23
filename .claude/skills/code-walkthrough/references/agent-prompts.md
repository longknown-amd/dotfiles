# Agent prompt templates

Fill in the `<…>` placeholders. Launch the agents of each stage **in one message**, so they run in parallel.
Models and effort follow the cost policy in `SKILL.md`. Each heading shows the exact Agent parameters.

## Stage 1: readers
`subagent_type: "Explore"`, `model: "sonnet"`, `effort: "medium"`. Use 3 readers by default.

Split the feature into slices that don't overlap. A common split:

1. **Entry, orchestration and surrounding system**, which also covers section 0.
2. **Core decision logic.** Split it in two only if the logic is large.
3. **Data in/out:** evidence and outputs, the API and UI.

Thoroughness: use "medium" when a reference or design doc covers the slice (give its section and line
hints), and "very thorough" only for undocumented slices.

```
Repo: <path> (<language> <project kind>). I'm writing an explainer of how its "<feature>"
feature works, for a developer new to the code. Your slice: <SLICE NAME>. Thoroughness: <medium|very thorough>.

Files to focus on: <files / globs, with approximate line hints if known>.
Reference doc (line numbers may be stale): <path>, sections <…>.

Answer:
1. <specific question>
2. <specific question>
3. Note any claim in the reference doc that no longer matches the code.

Efficiency rules:
- Use grep and read line ranges; never read a whole large file.
- Stop when the questions are answered.

Report format, at most about 1,200 words:
- A numbered flow. Each step gives: function, file:line, a one-sentence purpose, and a key snippet of
  at most 8 lines copied EXACTLY.
- Data structures (fields only), and config toggles with their defaults and file:line.
- Suggested diagram nodes and edges, at most 12.
- Only claim what you verified in the code. Mark anything else UNVERIFIED.
```

**Escalation:** if a report contradicts your spot-checks, or leaves core-logic claims UNVERIFIED,
re-run only that slice with `model: "opus"`, `effort: "high"`, or verify it yourself.

## Stage 2: walkthrough spec writers
`subagent_type: "general-purpose"`, `model: "sonnet"`, `effort: "medium"`. Use one per deep dive.

```
Read ~/.claude/skills/code-walkthrough/references/walkthrough-spec.md first and follow it exactly.
Write slug "<slug>" with back_anchor "<anchor>" to <specs dir>/<slug>.json.
The title must be "<Topic> — code walkthrough".

Repo: <path> at commit <sha> (read-only, never modify it).
Topic: <one-line topic>.

Verified locations (re-check each range with sed before using it; do NOT explore beyond these
except to confirm block boundaries):
- <file>: <function> :<line>, <detail> <a>-<b>
- ...
Follow the data: <A → B → C>. Mention where this differs from <reference doc>, if anywhere.

Include the call map with a `node` on every block and a `nodes` entry for every map ID,
plus 2–3 quiz questions (`block` numbers are 1-based).
Validate with:
  python3 -m json.tool <spec>
  python3 ~/.claude/skills/code-walkthrough/scripts/build_pages.py --repo <path> --commit <sha> --out /tmp/<slug>-trial --parent x <spec>
Fix any ERR lines, then delete /tmp/<slug>-trial.

Final reply, under 150 words: the path, the block count, and any doubts. Don't paste the spec.
```

## Review mode: theme writers
`subagent_type: "general-purpose"`, `model: "sonnet"`, `effort: "medium"`. Use one per theme (two small themes may share a writer).

```
Read ~/.claude/skills/code-walkthrough/references/review-spec.md first and follow it exactly.
Repo: <path> (read-only). Reviewing <sha | A..B | staged | worktree>: "<subject>" (`git log -1 <sha>`).
The skeleton is at <dir>/skeleton.json. Fill in the theme(s) with id <ids>. Do NOT change `hunk`, `range` or the entry order.
Per entry: title, explain (before→after, +L/−L citations), notes (0–3, with evidence), highlight, node.
Per theme: summary, why, checklist, map (ID["name"] nodes, no classDef lines) and nodes {role, def at the
reviewed revision, status new|changed|context}.
See hunks: python3 <skill>/scripts/difflib_git.py --repo <path> <source>, and git show <sha>:<file> | sed -n 'A,Bp'.
Focus on what a reviewer must check: <theme-specific risks, edge cases, contracts>.
Write {"themes": [...]} to <dir>/themes/<name>.json and validate it with json.tool.
Final reply, under 120 words: the path, the note counts by kind, and any doubts.
```

## Map ↔ entry linking (either mode, when specs lack it)
`subagent_type: "general-purpose"`, `model: "haiku"`, `effort: "low"`. Give it an exact list of the themes or specs
to process, and tell it to change nothing but `map` (drop classDef/class lines), `nodes` and each entry's `node`.
Have it validate with the builder and fix its own ERR lines. The builder then auto-attaches functions defined
inside a change and resolves cross-theme links; you check the statuses (new vs changed) against the parent revision.

## Stage 3 (only if needed): fix-ups
Mechanical edits (JSON fields, relabels, map linking): `subagent_type: "general-purpose"`,
`model: "haiku"`, `effort: "low"`, with an exact list of edits.

If the correction needs the original writer's context, for example re-choosing ranges, `SendMessage`
that agent instead. It keeps its context and needs no re-reading.
