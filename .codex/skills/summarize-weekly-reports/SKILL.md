---
name: summarize-weekly-reports
description: Summarize pasted daily engineering work reports into a compact, issue-driven weekly progress report organized by project, ASIC, and issue or test case. Use when the user pastes one or more daily status updates, asks for a weekly report or weekly summary, wants work consolidated across days, or wants progress grouped by project, chip, GPU, architecture, ASIC, target, issue, or test case.
---

# Summarize Weekly Reports

Transform daily notes into an outcome-focused weekly report with the hierarchy
`Project → ASIC → Issue/Test Case`. Preserve technical evidence and uncertainty while
removing daily repetition.

## Collect the Reports

- Accept reports pasted in one message or accumulated across the current conversation.
- If the user says more reports are coming, briefly confirm receipt and wait. Do not
  produce the final report until the user says the reports are complete or asks for
  the summary.
- Treat headings, dates, repository names, issue IDs, paths, branches, test names,
  build names, GPU targets, and nearby context as grouping evidence.
- Do not imply that reports are retained outside the current conversation.

## Normalize Each Work Item

For every meaningful update, identify:

1. Date or sequence position
2. Project
3. ASIC
4. Issue, test case, PR, or other work-item key
5. Work performed
6. Result or current status
7. Evidence, such as test output, measurements, commits, review status, or issue IDs
8. Blocker, dependency, or next step

Infer labels only when the surrounding text makes them clear.

- Normalize obvious aliases consistently, such as a repository name and its shortened
  project name, while retaining the user's preferred spelling.
- Keep separate ASICs separate even when the task description is similar.
- Put ASIC-independent work under `Shared / All ASICs`.
- Put unresolved project or ASIC ownership under `Unassigned` and state the ambiguity
  in Notes. Never guess merely to fill the hierarchy.
- Mention a cross-project or cross-ASIC dependency where it matters; do not duplicate
  the same work item in every group.
- Use the most specific stable identifier as the work-item key: test-case name first
  when the report is test-driven, otherwise issue, PR, component, or workstream name.
- Treat analysis, root cause, fix, validation, ticket submission, and follow-up for the
  same issue or test case as progress under one item, not as separate peer items.
- After forming individual work items, compare sibling items within the same project
  and ASIC. If two or more test cases have the same progress, result, evidence, and
  next action, combine them into one shared-progress group.

## Consolidate Across Days

- Merge repeated updates about the same issue or test case into one compact item.
- Order events chronologically to understand transitions such as
  `investigating → root cause found → fix implemented → validated`.
- Report the latest known status, while retaining earlier facts needed to explain the
  progress.
- Distinguish outcomes from activities. Prefer “isolated the assertion to the VCA LDS
  predicate” over “debugged the assertion.”
- Preserve exact technical details that make the result auditable: test or benchmark
  names, pass/fail counts, performance changes, error strings, issue IDs, review links,
  commits, and important file or component names.
- Preserve every PR and issue URL exactly as supplied, including its full path, query
  string, and fragment. Display the complete URL verbatim in the relevant bullet so it
  remains visible and clickable; do not replace it with only a shortened label such as
  `PR #123` or `[issue](URL)`. Deduplicate repeated copies of the same URL.
- If a report contains only a PR or issue identifier without a URL, retain the
  identifier but do not invent a URL.
- Keep each issue or test-case name in its item title; avoid repeating the name in
  every nested progress bullet.
- In a shared-progress group, list every included test case once in a `Tests:` bullet,
  then state the common progress once. Use a descriptive group title such as
  `Known AM failures` or `Common compiler issue`.
- Do not group items merely because they share a broad status such as “known issue.”
  Keep them separate when their root cause, evidence, URL, owner, result, or next
  action differs, or when they belong to different projects or ASICs.
- Combine closely related details when doing so preserves meaning. Prefer one to four
  progress bullets per item instead of reproducing the daily chronology.
- Do not convert a plan into completed work, a local test into full validation, or an
  investigation hypothesis into a confirmed root cause.
- Remove routine repetition, low-value narration, and duplicate meeting notes unless
  they explain a decision, blocker, or dependency.

## Produce the Weekly Report

Use [assets/weekly-report-template.md](assets/weekly-report-template.md) as the default
shape. Adapt it when the user supplies a required format.

- Derive the reporting period from explicit dates. If unavailable, use
  `Reporting period not specified`.
- Do not add an executive summary.
- Create one project section per project and one ASIC subsection per ASIC.
- Within each ASIC, create one bold list item for each issue, test case, PR, other
  work-item key, or eligible shared-progress group. Nest its consolidated progress
  beneath it.
- Include root cause, result, validation, URL, blocker, and next step only when the
  source reports contain them. Express status inline rather than creating separate
  status sections.
- Build the report dynamically from the available content. Omit empty nested details,
  work items, ASIC subsections, project sections, and optional `Notes / Assumptions`;
  never emit placeholders such as `None`, `N/A`, or `No blockers`.
- Use concise, professional engineering language and parallel bullet construction.
- Keep the user's first-person or team voice when explicitly requested; otherwise use
  neutral status-report language.
- Add `Notes / Assumptions` only when grouping, dates, ownership, or status remains
  materially ambiguous.

## Quality Check

Before returning the report, verify that:

- every substantive daily item is represented once;
- every item is grouped under a project and ASIC or explicitly marked unassigned;
- progress for the same issue or test case is consolidated under one item;
- analysis, root cause, validation, and ticket submission are not presented as
  unrelated peer items;
- sibling test cases with genuinely identical progress are combined into one group,
  with every test-case name retained;
- items with distinct root causes, evidence, URLs, results, or next actions remain
  separate;
- the latest status supersedes stale intermediate status;
- claims of completion and validation have evidence in the source reports;
- blockers and next steps are not presented as achievements;
- every supplied PR and issue URL appears in full and is attached to the relevant work
  item;
- the report contains no executive summary;
- no heading or work item is empty or followed only by placeholder text;
- identical progress text is not repeated across sibling items when it can be safely
  shared;
- no technical identifier, number, or result has been invented; and
- the summary can be read independently without the raw daily chronology.

If a missing label would materially change the organization, ask one concise
clarifying question. Otherwise proceed and disclose the assumption in Notes.
