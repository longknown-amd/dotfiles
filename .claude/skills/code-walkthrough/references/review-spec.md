# Review mode: theme spec

`scripts/build_review.py` renders theme pages from a review spec and the **real `git diff`**. Diff text
is never typed. Each entry references a hunk id from `scripts/difflib_git.py`, optionally sliced by a
new-side line `range`.

The main thread writes the **skeleton**: themes plus hunk/range assignments. The builder proves full
coverage, every changed line exactly once, before any writer starts. Writers fill in `title`,
`explain`, `notes`, `highlight`, and the theme's `summary`/`why`/`map`/`checklist`. They must
**not** change `hunk` or `range`.

## Entry fields

```json
{"hunk": "src/core/x.py@1000", "range": [1012, 1325],
 "title": "Short: what this change does",
 "explain": "<p><b>Before:</b> … <b>After:</b> …</p><ul><li><strong>+L1120</strong> …</li></ul><p><em>Why:</em> …</p>",
 "notes": [{"kind": "risk", "text": "… (cite +L/−L)"}],
 "highlight": [1120, 1121]}
```

- **`title`:** ≤ 70 chars, the intent rather than the mechanics ("Tail line numbers become file-absolute").
- **`explain`:** ≤ 120 words.
  - Start with **Before → After** behaviour.
  - Then 1–4 bullets on *how*, citing **new-side lines as `+L123`** and removed lines as `−L98` (old-side numbers).
  - Then the *Why*, taken from the commit message or code comments. Mark it as inference if it's neither.
- **`notes`:** 0–3 per entry, each one sentence, with evidence. Kinds:
  - `risk`: a plausible bug, regression or edge case. Give the scenario.
  - `question`: something a reviewer should ask the author, or verify.
  - `test`: which test covers this, or a missing test, by name.
  - `nit`: naming or readability; use sparingly.
  - `good`: a notably careful choice worth confirming; at most one per theme.

  **Don't pad.** An entry with no notes is fine.
- **`highlight`:** 0–4 new-side line numbers of the key lines.

## Theme fields

- **`summary`:** what changes, 2–3 sentences.
- **`why`:** the motivation, quoting the commit message where it applies.
- **`map`** (required for every theme except `tests`): a Mermaid `flowchart LR` of the functions this theme
  touches, plus up to 3 unchanged context functions. Use `ID["name"]` nodes with alphanumeric IDs, and use
  `Class.method` for methods. Aim for ≤ 12 nodes. **Don't write `classDef`/`class` lines**: the builder
  styles boxes from `nodes[*].status`.
- **`nodes`** (required with a map): one entry per map ID,
  `"C": {"role": "≤20 words: what it does in this change", "def": "path:line", "status": "new|changed|context"}`.
  - `def` is the definition line **at the reviewed revision**: `git show <sha>:path | grep -n "def name"`.
    The builder checks it there, not in the working tree.
  - `new` = added by this change, `changed` = modified, `context` = unchanged (drawn dashed).
- **Every entry gets `"node": "<map ID>"`**, the function its changed lines belong to:
  - a module-level constant or import goes to the function that uses it
  - a slice of a big hunk goes to the function the slice is in
  - if that function isn't on the map, add it
  - an entry that really spans several functions may use a list: `"node": ["A", "B"]`. The first one is the card's chip.

  **The builder resolves the rest:**
  - **Auto-attach:** a new or changed node whose *body* contains an entry's changed lines is attached to that
    entry. The body is found at the reviewed revision; for Python it runs from the def to the next statement at
    the same indent. So helpers defined inside one big slice don't each need hand-linking.
  - **Cross-theme:** a node changed on *another* theme page gets `see <theme> #k` in its box, with a link from
    its card.
  - **Warning:** a new or changed node that is touched by no change on any page. Attach it, or mark it `context`.

  The page then links the map 1:1 with the hunk cards:
  - each box shows its change numbers (`#3 #5`) and opens an info card with a "read these changes" focus mode
  - each card carries a `● function · part i/n` chip
  - a sticky mini-map marks the function on screen
- **`checklist`:** 3–6 concrete things a reviewer should verify for this theme.

## How to read the change

- See it in context:
  - `git show <sha>:<file> | sed -n 'A,Bp'` for the new side
  - `git show <sha>^:<file> | sed -n 'A,Bp'` for the old side
  - `python3 <skill>/scripts/difflib_git.py --repo R <sha>` to list hunks
- Review the change **as of the commit**. If a later commit touched the same code, mention it once in a
  `question` note, at most.
- Check callers or callees outside the diff only when a note depends on them.
  Prefer `grep -n` and line ranges over reading whole files.

## Build

```bash
python3 scripts/build_review.py --repo R --source <sha|A..B|staged|worktree> --github URL \
  --out DOCS/<topic>/<slug> --parent ../<slug>.html --parent-title "<title>" review.json
```

The build fails on any of these:
- an unknown hunk id
- a slice that selects no changed lines
- a changed line covered twice
- **any changed line not reviewed** (escape hatch: `--allow-uncovered`)

It also writes `review_summary.json`: per-file stats, notes by theme and coverage, which the overview uses.
