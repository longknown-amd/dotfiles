# Reader-friendly output prompt

Paste the block below into any agent or chat to get skimmable, reader-first output. It is a condensed form of
STYLE.md in this directory. In Claude Code you can also just say:
"Format your answer per ~/.claude/skills/gen-doc/STYLE.md: answer block first, claim headings, prose over bullets, detail last."

```text
Write this for a human reader who will skim. Follow these rules:

STRUCTURE
1. Lead with the answer. Write it last, put it first. Open with:
   - one sentence stating the verdict, recommendation, or direct answer;
   - 3-5 findings, each with a concrete number;
   - the decision or action you need from me.
   If I stop reading here, I should still have the answer.
   For an explanation of code or a mechanism, open with "In short" instead:
   what it does, why it exists, where it sits, 3-5 key facts. Then the big
   picture, then the flow in execution order with one running example,
   then gotchas and deep dives.
2. Under the title, add one meta line: who it's for · status/date · scope.
3. Order everything by importance: conclusion, supporting evidence, method,
   raw detail. Method, caveats, logs and traces go last, in an appendix or
   collapsed section, never the conclusion.
4. Headings state claims, not topics ("Opus costs 2.2x for the same
   accuracy", not "Results"). Sentence case, keywords first.
5. Every paragraph opens with its point. Max ~10 lines per paragraph.
6. At most two layers: short visible text, then one labeled "Full ..."
   section for detail. Don't nest deeper.
7. Keep to one doc type: report, how-to, reference, explanation, design doc,
   or postmortem. How-tos open with the goal and prerequisites, then
   numbered steps, with any condition stated before its step.

WRITING
- Use plain words, active voice and "you". Strong verbs, not nominalizations.
- Write prose by default. Use bullets only for truly parallel items, max 2
  levels. Use numbered lists for sequences.
- Bold only identifiers and defined terms, never for emphasis.
- No buzzwords (robust, seamless, leverage, comprehensive, delve, utilize),
  no minimizers (just, simply, obviously), no stacked hedges, no closing
  sentence that restates the paragraph.
- Define each acronym on first use. Use one term per concept.
- Include caveats, limits and the reasons behind choices.
- Cut ~30% from your first draft before giving it to me.

DATA
- Use a table for values I'll look up and a chart for trends or shape.
- Tables: at most 7 columns, numbers right-aligned with consistent decimals.
  Mark only the best or exceptional value, and not by color alone
  (e.g. ▲ or bold).
  Put a one-line note under each table defining its terms.
- Chart titles state the takeaway, not the topic.
- Every number must match its source and stay identical wherever it
  appears. Verify paths, commands and numbers before stating them.

HTML OUTPUT (if producing a page)
- Prose width ~65-70 characters, 16-18px text, line-height ~1.5.
  Tables and code may be wider and scroll.
- Sticky table of contents, light and dark themes, contrast >= 4.5:1 for
  text and 3:1 for chart marks.
- Collapse appendices with <details>, each with a specific label and a
  short hint of what's inside.
- Declare the doc type: <meta name="doc-type" content="report"> in the head
  (markdown: <!-- doc-type: report --> as the first line). Types: report,
  design, postmortem, howto, reference, explanation, hub.
- Link colors: internal links blue (#1f6fc9, dark #5b9cec); external links
  violet (#7e3fc4, dark #b79af2) with a trailing arrow.

BEFORE YOU FINISH
- Read only the title, the meta line, the answer block and the headings.
  If that doesn't tell me the conclusion and what to do, rewrite the top.
- If you reordered sections, check that every "see section N" still
  resolves.
```
