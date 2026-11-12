# Style rules for gen-doc

Readers scan: 79% skim and 16% read word by word (NN/g). A doc works when the answer, the key numbers and the headings are visible on the first screen and detail sits one click away. These rules apply to every doc, Markdown or HTML.

## 1. Structure

Pick one doc type and keep to it; mixing types makes each part worse (Diátaxis).

- Reports, evaluations, design docs and postmortems open with an answer block (BLUF): verdict, 3-5 findings with numbers, the decision or action needed.
- How-tos open with the goal in one line, then prerequisites, then steps.
- References open with a one-line scope. Their structure mirrors the thing described (same fields, same order for every entry).
- Explanations open with the question they answer, then the why, the background and the trade-offs.
- Draft the answer block first to fix the message, then rewrite it last so it matches the finished body; it always sits first. Aim for 5-15% of a long doc; in a one-page doc keep it to about 6 lines.
- Put a meta line under the title: audience, status and date, scope. Readers use it to decide whether to continue.
- Order content as an inverted pyramid: conclusion, support, niche detail.
- Support the governing claim with 2-4 non-overlapping arguments, each backed by data.
- Open every paragraph with its point. Readers take in the first two words of each line (F-pattern).
- Keep paragraphs to 10 lines at most and sections short.
- Use two disclosure layers at most: main text, then "Full ..." toggles or appendices. Collapse logs and raw data, never the conclusion.
- Design docs list goals and non-goals. A non-goal is something that could reasonably be a goal but is excluded.
- Postmortems are blameless and end in action items that each have an owner, a due date and a priority.
- Say when a doc is partial. Readers trust a stated gap more than a silent one.

## 2. Headings

Readers fixate on headings (layer-cake pattern), so a heading should work as a one-line summary.

- State a claim, not a topic: "codex_sol_med gives the best results for the money", not "Results".
- Front-load the keyword, because scanners read only the first words.
- Make each heading cover its whole section and nothing else.
- Use sentence case and no trailing punctuation.
- Add a heading only for a real section; one heading per paragraph is noise.
- Keep the title a claim too: it states the answer, the meta line gives the scope.
- Give toggles and links specific labels ("Full scoreboard", not "More" or "Learn more").

## 3. Writing

- Use active voice and address the reader as "you". Name the actor.
- Prefer strong verbs to nominalizations: "analyze", not "conduct an analysis".
- Use short, plain words and sentences.
- Write prose by default. Use bullets only for parallel items and nest at most 2 levels.
- Use numbered lists for sequences.
- Put conditions before instructions ("If the build fails, run X") and warnings before the steps they cover.
- Define each acronym on first use and keep one term per concept.
- Include one concrete example wherever a rule or term is abstract.
- State the reason behind each choice and the cases where it does not apply.
- Commit to claims. Cut minimizers (just, simply, obviously) and stacked hedges.
- Explain code only where the why is non-obvious; do not narrate lines.
- Use descriptive link text that names the target.
- Write for one specific reader and read the draft aloud. Cut about 30% of the first draft.

## 4. Data: tables and charts

- Use a table to look up exact values and a chart to show shape or trend (Few).
- Keep tables to 7 columns or fewer. Split wider ones.
- Left-align text and right-align numbers, with the same decimals in a column and tabular figures.
- Use light horizontal rules and no vertical rules.
- Mark only the winner or the exception in each column, and use more than color (underline plus ▲).
- Define every term and mark in a note under the table.
- Give each chart an action title that states the takeaway, plus a sub-line on how to read it.
- Draw inline SVGs at their rendered width (viewBox about 860 wide in the reader column) so 12-13 px labels stay that size; label values on the marks and keep labels from overlapping (check the screenshot).
- Maximize data per ink: no 3D, no heavy borders. Use small multiples with shared axes for comparisons.
- Meet contrast of 4.5:1 for text and 3:1 for chart marks in both themes. Never convey meaning by color alone.
- Keep every number identical across the answer block, body, tables and appendices. Re-check after each edit.
- Renumber "section N" and "Appendix X" references after any reorder.

## 5. HTML specifics

Build pages with `scripts/build_html.py`, which inlines `assets/reader.css` into `assets/skeleton.html`. Write only the `<main>` body. Type is 17px/1.55 with a 68ch prose measure; do not override it.

- `<h1>` claim title, then `<p class="meta"><span>audience</span><span>status, date</span><span>scope</span></p>`.
- `<div class="answer" id="answer">` holds `<p class="rec">` (one-sentence verdict), an `<ol>` of 3-5 numbered findings, and `<p class="ask">Decision needed: ...</p>`.
- Every `<h2>` needs an `id`; the sticky side TOC is built from them.
- `table.key` is the key-figures table: `td.num` for numbers, `td.win` for the best value in a column. Wrap tables in `<div class="tablewrap">`.
- `<p class="tnote">` sits under the table and defines the marks and terms.
- `<details class="more" id="...">` with `<summary><span class="lbl">Full X</span> <span class="hint">what is inside</span></summary><div class="more-body">...</div>` is the one disclosure layer. The page script opens a toggle when a hash link targets it.
- `<section class="appx"><h2 id="appendix">Appendices</h2>` contains `details.more` blocks labeled "A. ...", "B. ...".
- `<figure>` wraps a chart: `<p class="chart-title">` takeaway, `<p class="chart-sub">` reading guide, inline SVG with `role="img"` and a `<title>`. Use `.f-s1` to `.f-s4` fills and `.gridline`/`.baseline` strokes.
- `.legend` with `<span style="--c:var(--series-1)">name</span>` labels series; `.dot.s1` to `.dot.s4` mark rows in tables only when those rows are the same series as the legend and charts; otherwise leave dots out, because a color must mean one thing per page.
- Use `.callout` (with `.warn` or `.good`) at most 3 times per page.
- Check the page with `scripts/shot.sh` in light and dark mode before staging.

## 6. Markdown specifics

The site runs MkDocs 1.6 with the readthedocs theme. Extensions: tables, fenced_code, codehilite, `toc: permalink`, admonition and `md_in_html`. `pymdownx` is not installed, so `???` collapsibles do not work.

- Start with `# Claim title`, then the meta line in italics: `*Audience · Status, date · Scope*`.
- Write the answer block as `!!! abstract "Answer"` with the body indented 4 spaces.
- Collapse detail with `<details markdown="1"><summary>Full ...</summary>` ... `</details>`. Leave a blank line after `<summary>` and before `</details>` so Markdown renders inside.
- Use `##` for sections and `###` for sub-parts; `toc` adds the permalinks.
- Fence code with a language tag. Keep one command per block when readers will copy it.
- Align numeric table columns with `---:`. Mark winners with bold plus ▲ since Markdown cells have no class.
- Add the page to `mkdocs.yml` nav, with the file under `docs/<topic>/`.

## 7. AI anti-patterns

| Anti-pattern | Fix |
|---|---|
| Bold scattered through sentences | Bold only identifiers and defined terms |
| Runs of 5+ verbless fragment bullets, or bullets with a bold self-repeating label | Full-sentence claims or one prose paragraph |
| A heading on every paragraph, or bullets nested 4 deep | Flat structure; headings only for real sections |
| A closing sentence that restates the paragraph | Delete it |
| Buzzwords: robust, seamless, leverage, comprehensive, cutting-edge, delve, utilize | State the specific fact |
| Minimizers (just, simply, obviously) and stacked hedges | Commit to the claim, or say what is unknown |
| Narrating code line by line | Explain only the non-obvious why |
| Plausible but unverified numbers, paths, commands | Check each against its source before publishing |
| No caveats, edge cases or rationale | Add the gotchas, the limits and the reason behind each choice |
| Topic headings: Overview, Results, Details | Rewrite as claims |

## 8. Pre-publish checklist

- [ ] Doc type chosen; the structure matches it
- [ ] Title is a claim; meta line present
- [ ] Answer block (or goal and scope line) appears in the first screen
- [ ] Answer block has 3-5 findings with numbers and a stated decision or action
- [ ] Every heading is a claim, in sentence case
- [ ] Each paragraph opens with its point; none exceeds 10 lines
- [ ] Tables have 7 columns or fewer, aligned numbers and a note defining marks
- [ ] Every number, path and command verified against its source and identical everywhere
- [ ] Cross-references ("section N", "Appendix X") resolve; acronyms defined
- [ ] Cut pass done; `scripts/check_doc.py` run; HTML screenshot checked

## 9. Sources

- NN/g reading: https://www.nngroup.com/articles/how-users-read-on-the-web/
- NN/g F-pattern: https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content-discovered/
- NN/g layer-cake: https://www.nngroup.com/articles/layer-cake-pattern-scanning/
- NN/g inverted pyramid: https://www.nngroup.com/articles/inverted-pyramid/
- NN/g progressive disclosure: https://www.nngroup.com/articles/progressive-disclosure/
- NN/g information scent: https://www.nngroup.com/articles/information-scent/
- BLUF: https://en.wikipedia.org/wiki/BLUF_(communication)
- Minto pyramid: https://modelthinkers.com/mental-model/minto-pyramid-scqa
- Google design docs: https://www.industrialempathy.com/posts/design-docs-at-google/
- Google SRE postmortem: https://sre.google/sre-book/example-postmortem/
- Diátaxis: https://diataxis.fr/start-here/
- Google style: https://developers.google.com/style/highlights
- Microsoft style: https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice
- digital.gov plain language: https://digital.gov/guides/plain-language/writing
- Write the Docs principles: https://www.writethedocs.org/guide/writing/docs-principles/
- Butterick line length: https://practicaltypography.com/line-length.html
- WCAG contrast: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- Few, tables vs charts: https://www.perceptualedge.com/articles/Whitepapers/Communicating_Numbers.pdf
- A List Apart tables: https://alistapart.com/article/web-typography-tables/
- Action titles: https://www.storytellingwithdata.com/blog/2017/3/22/so-what
- Slatton: https://x.com/GrantSlatton/status/1829941438848909778
- Doshi: https://x.com/shreyas/status/1449911454291791875
- Graham: https://paulgraham.com/writing44.html
- AI docs pitfalls: https://passo.uno/whats-wrong-ai-generated-docs/
