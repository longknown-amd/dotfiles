# User-Level CLAUDE.md

## Centralized Documentation

All GPU engineering notes live in a self-hosted git repo on **`thohuang-pc`**, a Windows PC (SSH alias `thohuang-pc` → `longk@10.67.184.188`, key `~/.ssh/id_ed25519_thohuang_pc`, default shell `cmd`; use `powershell -NoProfile -Command "…"` for anything non-trivial). The site is served at **http://thohuang-pc:8000/**; the network URL is http://10.67.184.188:8000/, but the IP can change with DHCP.

- Bare repo (push target): `D:\doc_center\repository.git`. Its `post-receive` hook (bash, run by Git for Windows) does `git pull --ff-only` in the working tree, then `.venv\Scripts\python.exe -m mkdocs build`. It writes no log file.
- Working tree: `D:\doc_center` (`docs\`, `mkdocs.yml`, `.venv\`). Build output: `D:\doc_center\site`.
- Web server: `D:\doc_center\hosting\serve.py` (pythonw, port 8000, serves `site\`, directory listing off). It starts when `longk` signs into Windows (Startup shortcut) and stops on sign-out. Manual start: `hosting\start.ps1`. Manual build: `hosting\build.ps1`. HTTP log: `hosting\http.log`. Setup notes: `D:\doc_center\MIGRATION-WINDOWS.txt`.
- **Git over SSH needs the `ext::` transport.** The plain `thohuang-pc:D:/…` URL fails because `cmd` keeps git's single quotes around the path. Remote URL: `ext::ssh thohuang-pc git %s D:/doc_center/repository.git`, with `git config protocol.ext.allow always` set in the clone.
- The local clone is `~/docs`. The old Linux copy (`hjbog-srdc-38:~/docs.git`, http://hjbog-srdc-38:8000/) is **legacy**: it was copied over at commit `9e8cbc1` and is now independent and stale. Don't push or link to it.

When creating new docs, add to `~/docs/docs/<topic>/`, update `~/docs/mkdocs.yml` nav, then commit + push to `origin`. The `gen-doc` skill encapsulates the full workflow including staged-then-ask-before-push and post-push verification.
