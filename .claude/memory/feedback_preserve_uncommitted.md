---
name: preserve-uncommitted-before-destructive-git
description: Always preserve uncommitted tracked files (stash, dedicated branch, or explicit commit) before running git reset --hard / checkout that overwrites tracked files / rebase / cherry-pick / any branch switch that could collide
metadata:
  type: feedback
---

Before ANY git operation that could discard uncommitted tracked changes, save them first — `git stash push -u -m "auto: <reason>"` is the default, or create a throwaway WIP commit, or push the changes to a dedicated branch. Verify with `git status` that the working tree is clean before proceeding.

Operations that require this preservation step:
- `git reset --hard <anything>`
- `git checkout <ref> -- <paths>` when the paths have local edits
- `git checkout <branch>` if the branch's version of M-files differs
- `git rebase`, `git cherry-pick`, `git merge` (can leave half-applied state on conflict)
- Switching branches when working tree has `M` lines, even if git doesn't complain

**Why:** On 2026-05-28 (hipMicroBench project) I ran `git reset --hard 30212b3` on `thohuang/dockerfile` to drop two commits after cherry-picking them to a new branch. The user had uncommitted modifications to `src/coexec/coexec_alu_alu.hpp` (+157 lines) and `src/coexec/coexec_wcnn_alu.hpp` (+2 lines) sitting in the working tree. The reset discarded them. They were only recoverable because the user had separately stashed earlier work; without that pre-existing `stash@{0}`, ~160 lines of in-progress engineering would have been gone. The user called this "a very serious accident" and asked me to remember at the user level so all projects inherit it.

**How to apply:** Run `git status --short` immediately before any of the operations above. If there are `M` / `A` lines and they're not intentionally part of the operation, halt and either:
1. `git stash push -u -m "auto-preserve before <operation>"` and tell the user a stash was created (so they know how to recover)
2. Make a dated WIP commit on a safety branch
3. Ask the user explicitly

Never assume the user "doesn't care" about M-files just because they've been there a while — long-living working-tree edits often mean weeks of WIP. Treat every uncommitted line as load-bearing.
