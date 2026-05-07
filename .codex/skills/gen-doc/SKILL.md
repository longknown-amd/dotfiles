---
name: gen-doc
description: >
  Generate, edit, and publish GPU engineering documentation stored in the
  self-hosted MkDocs repo at ~/docs. Use this skill when the user asks for new
  notes, guides, or reference docs, requests updates to existing pages, or wants
  to push documentation live to http://hjbog-srdc-38:8000/.
---

# Generate Documentation

All GPU engineering docs live in a self-hosted git repo on `hjbog-srdc-38`. The
stack is unchanged from the Claude workflow:

- **Bare repo / push target:** `hjbog-srdc-38:~/docs.git`
- **Working tree:** `~/docs` on the server with an existing MkDocs virtualenv
- **Build output:** `~/docs/site/`
- **Web server:** user systemd unit `docs-http.service` running
  `python3 -m http.server 8000 --directory ~/docs/site` and serving
  **http://hjbog-srdc-38:8000/**

Pushing to `~/docs.git` triggers a post-receive hook that pulls, rebuilds, and
refreshes the static site within ~1–3 seconds.

## 0. Detect the Environment

Run `hostname` first.

- **Server-side:** Hostname starts with `hjbog-srdc-38`. Here, `~/docs` *is* the
  live working tree. You can run `.venv/bin/mkdocs` directly and inspect hook
  logs without SSH.
- **Client-side:** Any other hostname. Ensure `~/docs` exists (`git clone
  thohuang@hjbog-srdc-38:~/docs.git ~/docs` if missing). Local MkDocs may or may
  not be installed; skip the local build step if unavailable.

The git workflow is the same on both sides.

## 1. Determine the Topic and Section

Ask (or infer) the documentation topic, target audience, and desired location in
`~/docs/docs/`. Existing layout:

```
~/docs/docs/
  index.md
  microbench/
  miopen/
  <new-topic>/
```

Run `git -C ~/docs pull --ff-only` before editing to make sure you start from
the latest revision.

## 2. Write the Doc

- Start with an H1 (`# Title`).
- Keep the tone reference-oriented: architecture, workflows, troubleshooting,
  code snippets.
- Use fenced code blocks with language hints where applicable.
- Include tables, callouts, or diagrams (ASCII/Markdown) when they clarify
  hardware behavior or benchmarking steps.

## 3. Save to the Central Docs Path

Write the markdown file under `~/docs/docs/<section>/<filename>.md`. Create a
new subdirectory only when the topic does not fit an existing section.

## 4. Update mkdocs.yml Navigation

Edit `~/docs/mkdocs.yml` to add the new page under the appropriate nav entry. If
this introduces a new section, create a new top-level nav block with the proper
title.

## 5. Update the Landing Page

Modify `~/docs/docs/index.md` so the new doc is discoverable. Follow existing
structure: grouped headings with bullet links and short descriptions.

## 6. Optional Local Build

- **Server-side:** `cd ~/docs && .venv/bin/mkdocs build`
- **Client-side:** `cd ~/docs && mkdocs build` (only if MkDocs is installed)

Skip this step if MkDocs is unavailable locally; the post-receive hook will
surface build errors.

## 7. Stage, Review, and Commit

Stage only the relevant files:

```sh
git -C ~/docs add docs/<section>/<file>.md docs/index.md mkdocs.yml
git -C ~/docs status
```

Show the staged diff and propose an imperative commit subject (≤70 chars). Wait
for approval before committing.

```sh
git -C ~/docs commit -m "<message>"
```

## 8. Push and Verify Publication

Push to the default remote:

```sh
git -C ~/docs push
```

After ~3 seconds, verify the published page with cache busting:

```sh
curl -sS "http://hjbog-srdc-38:8000/<path>?cb=$(date +%s)" | grep "<unique string>"
```

The footer’s “Build Date UTC” should reflect the recent timestamp. If the new
content is missing:

1. Tail the hook log:
   - Server: `tail -30 ~/docs/.git/post-receive.log`
   - Client: `ssh thohuang@hjbog-srdc-38 'tail -30 ~/docs/.git/post-receive.log'`
2. Address MkDocs errors, push again, and re-check.

## 9. Report Back

Summarize:

- Local path(s) touched
- Commit SHA
- Whether the page is live (include the verified URL)
- Any follow-up required if the build failed

## Troubleshooting Quick Reference

| Symptom | First Check |
| --- | --- |
| `git push` rejected | Confirm SSH access and remote permissions |
| Page missing / timestamp stale | Inspect post-receive log |
| Hook reports MkDocs error | Fix the markdown/nav issue and re-push |
| Server not serving updates | `systemctl --user restart docs-http.service` |
| Port 8000 unreachable | `ss -tlnp | grep :8000` on server |

Keep new sections concise. If detailed architecture or API references are
needed, split them into additional markdown files and link from the main doc.
