# User-Level CLAUDE.md

## Centralized Documentation

All GPU engineering notes live in a self-hosted git repo at `hjbog-srdc-38:~/docs.git`. The local working clone is `~/docs`. A server-side post-receive hook runs `mkdocs build` after every push, and a `python3 -m http.server` user-systemd unit (`docs-http.service`) serves the rebuilt static site at **http://hjbog-srdc-38:8000/**.

When creating new docs, add to `~/docs/docs/<topic>/`, update `~/docs/mkdocs.yml` nav, then commit + push to `origin`. The `gen-doc` skill encapsulates the full workflow including environment detection (server vs client), staged-then-ask-before-push, and post-push verification.
