# Overview page spec

`scripts/build_overview.py` builds the feature overview from one JSON spec, using the engine in
`scripts/overview_template.html` (step player, replay player, quiz, Mermaid, highlight.js).
If a local `examples/` folder exists, its feature examples' `overview.json` files are complete references. Copy their structure.

## Top-level fields

| Field | Purpose |
|---|---|
| `title`, `h1`, `subtitle`, `footer` | page text. The subtitle states the commit and that code is quoted verbatim. |
| `back` | `{"href": "/<topic>/", "text": "← <topic> docs"}` |
| `scripts` | extra `<script src>` files, normally `["<slug>/replays.js"]` |
| `diagrams` | `{key: "mermaid text"}`. Every `data-diagram="key"` in the HTML needs an entry. |
| `walk_diagram` | the diagram key the guided walkthrough highlights (usually `main`) |
| `scenarios` | `{"A": {"label": "A · …", "steps": [{"node", "title", "plain", "file", "start", "end"}]}}`. The code is pulled from the repo, and every `node` must exist in `walk_diagram`. |
| `sections` | ordered list (see below) |
| `quiz` | `[{"q", "options", "answer", "why", "link", "linkText"}]` |
| `replay_tabs` | `[{"id": "r123", "label": "A · Job 123: …"}]` for the tabbed replay section |

## Sections, in this order (ids and nav labels are yours)

| # | Section | `kind` | Content |
|---|---|---|---|
| 0 | **Where it sits** | html | One `mermaid-host` diagram (≤10 nodes) of the surrounding system with the feature highlighted (`classDef focus`), external calls dashed. Then three bullets: the system's main job, where the feature hooks in (before or after what), and what it reads, writes and calls outside. Give a source line naming where the facts came from. Keep it high level, with no internals. |
| 1 | **60-second version** | html | `card tldr`: one bold sentence, the 2–3 paths, and the design principle. Then a `stats` row of 4–5 numbers. |
| 2 | **Guided walkthrough** | walkthrough | One intro sentence. `legend` holds the colour pills. Use 2–3 scenarios, each 4–9 steps along a real path. |
| 2b | **Replay real jobs** | replays | Intro sentence. The tabs come from `replay_tabs`. See `replays.md`. Omit the section if there is no real data. |
| 3 | **Deep dives** | html + `subs` | 3–6 subs. Each sub starts with a walkthrough link button, then 1–2 visuals (a table, a `mermaid-host`, a `logbar` chart or a `code-ref`) and short prose. |
| 4 | **Switches** | html | Table of env vars and config: name, default, effect. |
| 5 | **Surprises & gotchas** | html | `callout`s for behaviour that contradicts intuition or docs, plus a `<details>` "Not verified" list. |
| 6 | **Where to start reading** | html | A table of 5–8 `file:line` entry points in reading order. |
| 7 | **Check yourself** | quiz | One sentence. The questions come from `quiz` (3–5). |
| 8 | **Glossary** | html | A table of terms. |

## HTML components available in fragments

```html
<span class="pill test">test-level</span> <span class="pill job">…</span> <span class="pill llm">…</span>
<div class="card tldr">…</div>          <div class="callout">…</div>
<div class="stats"><div class="stat"><div class="n">2</div><div class="l">paths</div></div></div>
<div class="side-by-side"><div>…</div><div>…</div></div>
<div class="mermaid-host" data-diagram="KEY"></div>
<div class="code-ref" data-file="src/x.py" data-start="10" data-end="20" data-caption="optional"></div>
<div class="replay-host" data-replay="r1" data-diagram="0"></div>   <!-- 1 = show walk diagram -->
<a class="walk" href="<slug>/owner.html">Code walkthrough → <small>files…</small></a>
<div class="logbar"><div class="head">…</div><div class="mid">…</div><div class="tail">…</div></div>
<pre><code class="language-plaintext">literal output (escaped)</code></pre>
```

- Tables use `width: auto`; don't stretch them.
- Never paste source code into a fragment. Use `code-ref`, which the builder fills verbatim and links to GitHub.
- Literal *program output*, such as a real digest, may be inlined in `<pre>` when it really is output. Say where it came from.

## Tip: generate the spec

Write a small `gen_overview.py` that builds `overview.json`, and have scenario steps cite
**walkthrough-spec blocks by (page, block#)** instead of typing ranges. Those ranges are already
verified by the spec writers. A local example's `gen_overview.py`, if present, shows the pattern.

## Build

```bash
python3 scripts/build_overview.py --repo REPO --commit SHA --github URL --out DOCS/<topic>/<slug>.html overview.json
```

The builder fails on any of these:
- a code range missing or outside its file
- a range over 60 lines
- a step `node` that isn't in the walk diagram
- a `data-diagram` with no entry in `diagrams`
