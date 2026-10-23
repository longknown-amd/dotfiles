---
name: gen-doc
description: Use this skill when the user asks to generate, output, create, or write documentation, study notes, a guide, or a reference doc. It publishes to the user's self-hosted MkDocs docs site (host, repo and URL are defined in ~/.claude/CLAUDE.md). Trigger automatically unless the user explicitly says to write elsewhere (e.g., "save it here", "put it in this repo", "output to stdout", "put it in OneNote").
---

# Generate Documentation → self-hosted docs site

All GPU engineering docs live in a self-hosted git repo on the docs host.

**Configuration:** the docs host, the SSH user and the site URL are defined in `~/.claude/CLAUDE.md`
("Centralized Documentation"). Below, `<docs-host>` and `<user>` stand for those values; read them from
there, never hard-code them in synced files.

The architecture is:

- **Bare repo (push target):** `<docs-host>:~/docs.git`
- **Working tree (built from):** `~/docs` on the server, with mkdocs and a `.venv/`
- **Build output:** `~/docs/site/`, pre-rendered static HTML populated by the post-receive hook
- **Web server:** user-systemd unit `docs-http.service` running `python3 -m http.server 8000 --directory ~/docs/site`,
  served at **http://<docs-host>:8000/**

A push to `~/docs.git` triggers the server hook: `git pull --ff-only` in `~/docs`, then `mkdocs build`. The http
server then serves the rebuilt site. End-to-end propagation takes about 1–3 seconds.

**Other targets:**
- **Interactive code explainers** (feature walkthroughs, commit reviews): use the `code-walkthrough` skill, which
  builds raw HTML pages and publishes them through this same repo.
- **OneNote:** only when the user explicitly asks for it. The OneNote MCP tools (`mcp__onenote__*`) are still available.

## 0. Detect environment first

Run `hostname` to decide which workflow applies:

- **Server-side** (`hostname` starts with `<docs-host>`): `~/docs` IS the working tree the hook reads from, and
  `~/docs/.venv/bin/mkdocs` is available locally. You can check the build directly and tail the hook log without SSH.
- **Client-side** (any other host, e.g. your workstation): the local clone is `~/docs`. If it's missing, clone it
  with `git clone <user>@<docs-host>:~/docs.git ~/docs`. `mkdocs` is usually not installed locally, so verify
  by curling the published URL after the push.

The git workflow is the same either way: edit → commit → push to `origin` (`<user>@<docs-host>:~/docs.git`).
The hook fires whoever pushed.

## 1. Determine the topic and section

Ask the user, or infer from context, what the doc covers. List the existing sections with `ls ~/docs/docs/`
and the nav in `~/docs/mkdocs.yml`. Map the doc to an existing folder, or create a new one if nothing fits.
`index.md` is the landing page that links every section.

Before writing, run `git -C ~/docs pull --ff-only` so you start from the latest revision.

## 2. Write the doc

- Use clear markdown with proper headings, tables and code blocks. Start with a level-1 heading (`# Title`).
- Keep it reference-oriented (facts, architecture, code patterns), not a tutorial.
- Include code snippets where they clarify behaviour. Cite `file:line` and the revision for anything taken from
  a repo, because line numbers drift.
- No emojis unless the user asks for them.

## 3. Save to the central docs path

Write the file to `~/docs/docs/<section>/<filename>.md` (lowercase, hyphenated filename).

**Raw HTML pages** (self-contained or interactive) also go under `~/docs/docs/<section>/`. MkDocs copies them
unchanged. Their nav entries must use an **absolute path** (see step 4).

## 4. Update mkdocs.yml nav

Read `~/docs/mkdocs.yml`, then add the new page under the matching nav section. Create a new top-level nav entry if
the section doesn't exist.

```yaml
  - Some Section:
    - "Some Page": some-section/some-page.md                    # markdown: relative path
    - "Some Explainer (interactive)": /some-section/explainer.html   # raw HTML: absolute path
```

## 5. Update the landing page

Read `~/docs/docs/index.md` and add a link to the new doc under the matching section. For a new section, add a
heading and a one-line description.

If `index.md` is missing sections that exist in the nav, mention that to the user and offer to fill the gap;
don't do it silently.

## 6. Local build check (optional)

Only when `mkdocs` is available locally, which is usually only on the server:

```sh
cd ~/docs && .venv/bin/mkdocs build   # server
cd ~/docs && mkdocs build             # a client with a system-wide mkdocs
```

If `mkdocs` isn't installed locally, skip this step; the server hook reports syntax and nav errors in the
post-receive log (see Troubleshooting).

## 7. Stage, then ask before pushing

Stage the new or changed files but **don't commit or push automatically**:

```sh
git -C ~/docs add docs/<section>/<filename>.md docs/index.md mkdocs.yml
git -C ~/docs status --short
```

Show the user the staged diff summary and a proposed commit message (`docs(<section>): <what>`), then ask whether
to commit and push.

**Exception:** if the user's request already said to publish or push (e.g. "publish it to the docs server"), that
is the approval. Commit and push without asking again.

Pushing:

```sh
git -C ~/docs commit -m "<message>"
git -C ~/docs push origin main
git -C ~/docs status -sb | head -1     # must NOT say "ahead"
```

The server prints a Conductor SUT-authentication banner on every SSH connection; it's noise, not an error. A
push can occasionally fail the authorization check transiently. If `status -sb` still says `ahead`, retry the push
(up to 3 times, a few seconds apart) before reporting a failure.

## 8. Verify propagation

Wait about 3 seconds, then confirm the new content is live, using a cache-buster:

```sh
curl -sS -o /dev/null -w "%{http_code}\n" "http://<docs-host>:8000/<path>"            # expect 200
curl -sS "http://<docs-host>:8000/<path>?cb=$(date +%s)" | grep -c "<unique string from new doc>"
curl -sS "http://<docs-host>:8000/?cb=$(date +%s)" | grep -o "Build Date UTC : [^<]*"
```

The markdown page URL is `/<section>/<filename>/` (directory style); a raw HTML page stays at
`/<section>/<filename>.html`. A recent `Build Date UTC` confirms the rebuild ran. If the page returns 404, the
string is missing, or the timestamp didn't advance, go to Troubleshooting.

## 9. Report

Tell the user:
- the local file path
- that the changes are pushed and live at the full URL under **http://<docs-host>:8000/** (or that they're
  staged and awaiting approval)
- the diagnostic from Troubleshooting, if verification failed

## Troubleshooting

If the published page doesn't reflect a push:

| Symptom | First check |
|---|---|
| `git push` rejected, or `status -sb` still says `ahead` | Retry (transient auth). Then check SSH access to `<docs-host>` and your key in the server's `~/.ssh/authorized_keys` |
| Push succeeds but the build timestamp didn't move | Server-side: tail `~/docs/.git/post-receive.log`. Client-side: `ssh <user>@<docs-host> 'tail -30 ~/docs/.git/post-receive.log'` |
| `mkdocs build` errored in the log | Fix the markdown or nav and push again |
| Hook log shows a successful build but the page is stale | `systemctl --user is-active docs-http.service` on the server; restart it with `systemctl --user restart docs-http.service` if needed |
| Page completely unreachable | Run `ss -tlnp \| grep :8000` on the server to confirm the listener is bound |
| A raw HTML page 404s but its markdown siblings work | Check the nav entry uses an absolute path (`/section/page.html`) and the file is under `docs/` |

The serving stack on the server is deliberately simple; the hook log is authoritative.
