---
name: gen-doc
description: Use this skill when the user asks to generate, output, create, or write documentation, study notes, a guide, or a reference doc. Trigger automatically unless the user explicitly says to write elsewhere (e.g., "save it here", "put it in this repo", "output to stdout").
---

# Generate Documentation

All GPU engineering docs live in a self-hosted git repo on `hjbog-srdc-38`. The architecture is:

- **Bare repo (push target):** `hjbog-srdc-38:~/docs.git`
- **Working tree (built from):** `~/docs` on the server, with mkdocs and a `.venv/`
- **Build output:** `~/docs/site/` — pre-rendered static HTML, populated by the post-receive hook
- **Web server:** user-systemd unit `docs-http.service` running `python3 -m http.server 8000 --directory ~/docs/site`, served at **http://hjbog-srdc-38:8000/**

Push to `~/docs.git` → server hook does `git pull --ff-only` in `~/docs`, then `mkdocs build` → `python3 -m http.server` serves the freshly-rebuilt static site immediately. End-to-end propagation is ~1–3 seconds.

## 0. Detect environment first

Run `hostname` to decide which workflow applies:

- **Server-side** (`hostname` starts with `hjbog-srdc-38`): `~/docs` IS the working tree the hook reads from, and `~/docs/.venv/bin/mkdocs` is available locally. You can verify the build directly and tail the hook log without SSH.
- **Client-side** (any other host): the local clone is `~/docs` (clone with `git clone thohuang@hjbog-srdc-38:~/docs.git ~/docs` if missing), but `mkdocs` may or may not be installed locally. Verify by curling the published URL after push.

The git workflow is identical in both cases: edit → commit → push to `origin` (`thohuang@hjbog-srdc-38:~/docs.git`). The hook fires regardless of who pushed.

## 1. Determine the topic and section

Ask the user (or infer from context) what the doc covers. Map it to an existing section in `~/docs/docs/` or create a new subfolder if the topic doesn't fit existing ones.

Layout convention:
```
~/docs/docs/
  index.md              # Landing page with links to all sections
  microbench/           # Radeon Microbench + hipMicroBench
  miopen/               # MIOpen library internals
  <new-topic>/          # Add new folders as needed
```

Before writing, run `git -C ~/docs pull --ff-only` so you start from the latest revision.

## 2. Write the doc

- Use clear markdown with proper headings, tables, and code blocks.
- Start with a level-1 heading (`# Title`).
- Keep it reference-oriented — facts, architecture, code patterns, not tutorials.
- Include code snippets where they clarify behavior.
- No emojis unless the user asks for them.

## 3. Save to the central docs path

Write the file to `~/docs/docs/<section>/<filename>.md`.

## 4. Update mkdocs.yml nav

Read `~/docs/mkdocs.yml`, then edit it to add the new page under the appropriate nav section. If the section doesn't exist, create a new top-level nav entry.

## 5. Update the landing page

Read `~/docs/docs/index.md` and add a link to the new doc under the appropriate section. If it's a new section, add a new heading and description.

## 6. Local build check (optional)

Only when `mkdocs` is available locally — usually only on the server, where `~/docs/.venv/bin/mkdocs` exists:

```sh
cd ~/docs && .venv/bin/mkdocs build   # server
# or, if a system-wide mkdocs exists on a client:
cd ~/docs && mkdocs build
```

If `mkdocs` isn't installed locally, skip this — the server hook will catch syntax/nav errors and surface them in the post-receive log (see Troubleshooting).

## 7. Stage, then ask before pushing

Stage the new/changed files but **do not commit or push automatically**:
```sh
git -C ~/docs add docs/<section>/<filename>.md docs/index.md mkdocs.yml
git -C ~/docs status
```

Show the user the staged diff and a proposed commit message, then ask whether to commit and push. Only after explicit approval:
```sh
git -C ~/docs commit -m "<message>"
git -C ~/docs push
```

## 8. Verify propagation

Wait ~3 seconds, then cache-bust to confirm the new content is live:

```sh
curl -sS "http://hjbog-srdc-38:8000/<path>?cb=$(date +%s)" | grep "<unique string from new doc>"
```

A `Build Date UTC : <recent timestamp>` line in the page footer confirms the rebuild fired. If the timestamp didn't advance or your unique string is missing, jump to Troubleshooting.

## 9. Report

Tell the user:
- The local file path.
- That changes are pushed and live at the appropriate URL under **http://hjbog-srdc-38:8000/**.
- (If verification failed) the diagnostic from Troubleshooting.

## Troubleshooting

If the published page doesn't reflect a push:

| Symptom | First check |
|---|---|
| `git push` rejected | SSH access to `hjbog-srdc-38`; identity in `~/.ssh/authorized_keys` on server |
| Push succeeds but timestamp didn't move | Server-side: tail `~/docs/.git/post-receive.log`. Client-side: `ssh thohuang@hjbog-srdc-38 'tail -30 ~/docs/.git/post-receive.log'` |
| `mkdocs build` errored in the log | Fix the markdown / nav and push again |
| Hook log shows successful build but page is stale | `systemctl --user is-active docs-http.service` on the server; restart with `systemctl --user restart docs-http.service` if not active |
| Page completely unreachable | `ss -tlnp | grep :8000` on the server to confirm the listener is bound |

The serving stack on the server is intentionally simple — the hook log is authoritative.
