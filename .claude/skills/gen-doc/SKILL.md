---
name: gen-doc
description: Use this skill when the user asks to generate, output, create, or write documentation, study notes, a guide, or a reference doc. Trigger automatically unless the user explicitly says to write elsewhere (e.g., "save it here", "put it in this repo", "output to stdout").
---

# Generate Documentation

When generating documentation, follow these steps:

## 1. Determine the topic and section

Ask the user (or infer from context) what the doc covers. Map it to an existing section in `~/Documents/gpu-docs/docs/` or create a new subfolder if the topic doesn't fit existing ones.

Current layout convention:
```
~/Documents/gpu-docs/docs/
  index.md              # Landing page with links to all sections
  microbench/           # Radeon Microbench + hipMicroBench
  miopen/               # MIOpen library internals
  <new-topic>/          # Add new folders as needed
```

## 2. Write the doc

- Use clear markdown with proper headings, tables, and code blocks.
- Start with a level-1 heading (`# Title`).
- Keep it reference-oriented — facts, architecture, code patterns, not tutorials.
- Include code snippets where they clarify behavior.
- No emojis unless the user asks for them.

## 3. Save to the central docs path

Write the file to `~/Documents/gpu-docs/docs/<section>/<filename>.md`.

## 4. Update mkdocs.yml nav

Read `~/Documents/gpu-docs/mkdocs.yml`, then edit it to add the new page under the appropriate nav section. If the section doesn't exist, create a new top-level nav entry.

## 5. Update the landing page

Read `~/Documents/gpu-docs/docs/index.md` and add a link to the new doc under the appropriate section. If it's a new section, add a new heading and description.

## 6. Verify

Run `cd ~/Documents/gpu-docs && mkdocs build` to confirm the build succeeds.

## 7. Report

Tell the user the file path and that they can view it with `mkdocs0` from `~/Documents/gpu-docs/`.
