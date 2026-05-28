---
name: gen-doc
description: Use this skill when the user asks to generate, output, create, or write documentation, study notes, a guide, or a reference doc. Trigger automatically unless the user explicitly says to write elsewhere (e.g., "save it here", "put it in this repo", "output to stdout").
---

# Generate Documentation → OneNote

All documentation is published to **OneNote** in the **AMD-Work** notebook, section **GPU-Eng-Notes**. Pages are organized with category header pages (level 0) and content pages indented as subpages (level 1).

## 1. Determine the topic and category

Ask the user (or infer from context) what the doc covers. Map it to an existing category header in GPU-Eng-Notes:

| Category | Topics |
|---|---|
| Microbench | Radeon microbench, hipMicroBench, perf measurement |
| MIOpen | MIOpen library, convolution, kernels, CBA fusion |
| Work with AI | AI coworking, onboarding guides, prompt patterns |
| Troubleshooting | Bug investigations, ISA issues, build errors |
| Cheatsheets | Quick-reference docs (Docker, git, CLI tools, etc.) |

If no existing category fits, you will create a new level-0 header page for the category before creating the content page.

## 2. Write the doc as inline-styled HTML

Write the document body as **HTML with inline styles**. Do NOT write markdown — write HTML directly. The inline styles simulate a clean rendered-Markdown appearance that OneNote preserves faithfully.

Use these styling patterns:

### Headings
```html
<h2 style="border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; margin-top: 1.5em;">Section Title</h2>
<h3 style="margin-top: 1.2em;">Subsection Title</h3>
```

### Paragraphs
```html
<p style="line-height: 1.6; margin: 0.8em 0;">Body text here.</p>
```

### Code blocks
```html
<pre style="background-color: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 16px; font-family: 'Consolas', 'Courier New', monospace; font-size: 13px; line-height: 1.45; overflow-x: auto; white-space: pre;"><code>code goes here</code></pre>
```

### Inline code
```html
<code style="background-color: #eff1f3; padding: 0.2em 0.4em; border-radius: 3px; font-family: 'Consolas', 'Courier New', monospace; font-size: 85%;">command</code>
```

### Tables
**ALWAYS use `width: auto`** — never `width: 100%` or any fixed width. Tables must size to their content, not stretch across the page. This is a hard rule (user has corrected it multiple times).

```html
<table style="border-collapse: collapse; width: auto; margin: 1em 0;">
  <thead>
    <tr style="background-color: #f6f8fa;">
      <th style="border: 1px solid #d0d7de; padding: 8px 12px; text-align: left;">Header</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="border: 1px solid #d0d7de; padding: 8px 12px;">Data</td>
    </tr>
  </tbody>
</table>
```

### Lists
```html
<ul>
  <li style="margin: 0.3em 0;">Item one</li>
  <li style="margin: 0.3em 0;">Item two</li>
</ul>
```

### Blockquotes / callouts
```html
<blockquote style="border-left: 4px solid #d0d7de; padding: 0.5em 1em; margin: 1em 0; color: #57606a;">
  <p>Note or callout text.</p>
</blockquote>
```

### Bold and emphasis
Use standard `<strong>` and `<em>` tags — no special styling needed.

### Important rules
- Always use inline styles (not `<style>` blocks or class attributes) — OneNote strips those.
- Do NOT wrap content in `<!DOCTYPE html>` or `<html>` tags — just write the body content. The MCP `createPage` tool wraps it in a full document.
- Do NOT include an `<h1>` — the `createPage` tool adds one from the `title` parameter.
- Keep the doc reference-oriented: facts, architecture, code patterns. Not tutorials.
- No emojis unless the user asks.

## 3. Create the page in OneNote

Call the `createPage` MCP tool with:
- **`title`**: the document title
- **`content`**: the styled HTML body from Step 2
- **`notebook`**: `"AMD-Work"`
- **`section`**: `"GPU-Eng-Notes"`

If you needed to create a new category header page (because no existing category fits), create it first:
- Call `createPage` with `title` = category name, `content` = `<p><em>Category: [name]</em></p>`, `notebook` = `"AMD-Work"`, `section` = `"GPU-Eng-Notes"`.
- Do NOT call `setPageLevel` on the header — it stays at level 0.

## 4. Set the page as a subpage

After the content page is created, call `setPageLevel` with:
- **`pageId`**: the page ID returned by `createPage`
- **`level`**: `1`

This indents the page under its category header in the OneNote page list.

## 5. Report

Tell the user:
- The page title and that it is live in **AMD-Work → GPU-Eng-Notes → [Category]**.
- Suggest they open OneNote to verify formatting, especially for code blocks and tables.
