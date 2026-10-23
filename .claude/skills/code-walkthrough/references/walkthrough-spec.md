# Walkthrough page spec (one JSON per deep dive)

`scripts/build_pages.py` turns each spec into an annotated code page. Code is **pulled from
the repo by (file, start, end) at build time**, so spec writers choose ranges and write
explanations. They never paste code.

## Schema

```json
{
  "slug": "owner",
  "title": "Who owns a failed test? — code walkthrough",
  "back_anchor": "owner",
  "summary": "<p>2–4 sentences: what the page covers, the entry function, and the order the blocks follow.</p>",
  "map": "flowchart LR\n  D[\"_draft_single_issue\"] --> C[\"classify_failure_owner\"]\n  C --> H[\"_citation_hits\"]",
  "nodes": {
    "C": {"role": "≤20 words: what this function is for in this feature.", "def": "src/core/x.py:566"}
  },
  "sections": [
    {"heading": "1. Short heading", "intro": "<p>optional</p>",
     "blocks": [
       {"file": "src/core/x.py", "start": 566, "end": 600, "node": "C",
        "title": "Short block title",
        "explain": "<p>One sentence: what the block does.</p><ul><li><strong>L572</strong> how…</li></ul><p><em>Why:</em> …</p>",
        "highlight": [580]}
     ]}
  ],
  "quiz": [
    {"q": "Question (HTML ok)", "options": ["…", "…", "…"], "answer": 1,
     "why": "One or two sentences.", "block": 7}
  ],
  "takeaways": ["one-line lesson"]
}
```

`title` must use the form `"<Topic> — code walkthrough"`. The sidebar shows the part before ` — `.

## Rules for blocks

- **Count and size:** 8–14 blocks in 2–5 sections. Each block is a contiguous range of 6–45 lines; the builder rejects blocks over 60 lines. To cover a long function, split it into several blocks or skip the dull stretches. The page shows "⋮ N lines not shown" between blocks from the same file.
- **Order:** follow the data through the feature (execution order), not file order.
- **`explain`:**
  - Open with one sentence saying what the block does.
  - Then 2–5 bullets on *how*, citing real file line numbers as `<strong>L123</strong>` or `<strong>L120-L130</strong>`. These become hover-highlights, but only when they fall inside the block's range.
  - Add *Why:* or *Gotcha:* only when the point isn't obvious.
  - Explain intent; don't paraphrase lines.
- **`highlight`:** 0–4 key lines, all inside the block's range.
- **Allowed HTML:** p, ul, ol, li, code, strong, em, br, a. Escape `<`, `>` and `&` in prose.
- **Check before writing:** re-read every range with line numbers (`sed -n 'A,Bp' file`) and confirm that start and end land on whole statements.

## Rules for the call map (it must link 1:1 to blocks)

- **Syntax:** Mermaid `flowchart LR`. Write each node as `ID["label"]`, with an alphanumeric ID, square brackets and a double-quoted label. Put the ID on its first use.
- **Labels:** the function name, as `Class.method` for methods.
- **Size:** aim for ≤12 nodes. Go over only when every block really belongs to a different function, and say so.
- **`node` on every block:** the function the block's code belongs to.
  - A constant, table or prompt string belongs to the function that consumes it.
  - A call site belongs to the caller.
  - If a block's function isn't on the map, add a node and an edge for it.
- **`nodes` entry for every map ID:** `role` (≤20 words) and `def` (`file:line` of the `def`, `function` or constant). Check `def` with grep.
- **Context-only nodes:** a node with no block is drawn dashed as "context only". Keep these to 3 or fewer.
- **What the builder checks:**
  - Errors: a block whose node isn't on the map; a `def` file that's missing.
  - Warnings: a node with no role; a `def` line that doesn't mention the name.

## Quiz (2–3 questions per page)

- Ask about behaviour a reader would get wrong without reading the code: a precedence order, a default, a gate's threshold, or what happens in an edge case.
- Make the distractors plausible. Each `why` explains the answer, and `block` points to the block that proves it.

## Build

```bash
python3 scripts/build_pages.py --repo REPO --commit SHA --github https://github.com/ORG/REPO \
  --out DOCS/<topic>/<slug> --parent ../<slug>.html --parent-title "<Feature> overview" \
  --order a,b,c specs/*.json
```

Warnings about `explain cites Lnnn outside range` are acceptable when the reference is
deliberate context. Those references show as plain text instead of hover links.
