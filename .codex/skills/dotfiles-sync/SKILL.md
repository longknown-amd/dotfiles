---
name: dotfiles-sync
description: >
  Synchronize the user's bare ~/.dotfiles repository (work-tree=$HOME) with
  explicit staging, review, fetch, and push guardrails. Trigger when Codex
  should offer or run the dotfiles sync workflow after a hook reminder or a
  direct request such as "sync dotfiles", "push my config", or "commit my
  dotfiles". Skip if the dirty files are unrelated to the current work or the
  user declines.
---

# Sync Dotfiles

The user maintains their `$HOME` configuration in a **bare git repo** at
`~/.dotfiles`, with `$HOME` itself as the work tree. The remote is
`git@github.com-longknown:longknown-amd/dotfiles.git` (`origin/main`).
Tracked paths include `~/.claude/`, `~/.config/nvim/`, shell rc files, etc.

A Codex hook plugin at `~/plugins/personal-hooks` runs
`scripts/dotfiles-dirty-check.sh` on every `UserPromptSubmit` event. When the
repo has tracked changes, the hook injects an additional-context reminder so
this skill can offer the sync workflow. The hook only inspects local state; it
does not contact the remote.

Always use the full git invocation:

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME -c status.showUntrackedFiles=no <subcommand>
```

The `-c status.showUntrackedFiles=no` flag prevents the status command from
enumerating every untracked file in `$HOME`.

## When to Invoke

- **Auto-trigger:** The hook reminder appears in additional context. Offer the
  workflow if the dirty files relate to the current task.
- **Explicit trigger:** The user says "sync dotfiles", "push my config",
  "commit my dotfiles", or similar.
- **On-demand:** When you notice edits under `$HOME` that should be captured in
  the dotfiles repo before finishing the session.

Skip the skill when the user explicitly declines or the dirty paths are clearly
unrelated to the current work.

## Workflow

### 1. Show Current Local State

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME -c status.showUntrackedFiles=no status -s
git --git-dir=$HOME/.dotfiles --work-tree=$HOME log --oneline -5
```

Summarize the dirty paths. If nothing is staged or dirty, exit early.

### 2. Stage the Relevant Files

Stage by explicit absolute path so the command works regardless of the current
working directory. **Never** use `git add -A` or `git add .`.

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add $HOME/<path1> $HOME/<path2> ...
```

If multiple unrelated topics changed (for example a Claude config edit and an
nvim lockfile update), prefer separate commits unless the user asks to combine
them.

### 3. Review the Staged Diff and Draft a Commit Message

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME --no-pager diff --staged
```

Show the diff and propose a concise imperative subject (≤70 characters). Ask
the user before committing if the scope is non-trivial.

### 4. Commit Once the Message Is Approved

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -m "<message>"
```

If any hook fails, surface the failure and work with the user to fix it. Do not
amend or bypass verification.

### 5. Sync with Remote Before Pushing

The remote may advance from other machines, so always fetch before pushing.

```sh
git --git-dir=$HOME/.dotfiles fetch origin main:refs/remotes/origin/main

ahead=$(git --git-dir=$HOME/.dotfiles rev-list --count origin/main..HEAD)
behind=$(git --git-dir=$HOME/.dotfiles rev-list --count HEAD..origin/main)
echo "local is ahead by $ahead, behind by $behind"
```

Decide based on `(ahead, behind)`:

| `ahead` | `behind` | Action |
| --- | --- | --- |
| 0 | 0 | Already in sync; nothing to push. |
| ≥1 | 0 | Local commits only; safe to push. |
| 0 | ≥1 | Remote ahead; run `git pull --ff-only` and re-evaluate. |
| ≥1 | ≥1 | Diverged; rebase on `origin/main` and show the incoming commits first. |

Stop and consult the user if a rebase encounters conflicts.

### 6. Push with Confirmation

Unless the user explicitly requested the sync, ask before pushing. Show
`git log origin/main..HEAD --stat` (or `git log -1 --stat` for a single commit)
and confirm.

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME push
```

If the push is rejected because the remote advanced again, repeat the fetch and
divergence check once.

### 7. Report Back

Summarize the commit SHA(s), files changed, whether a rebase occurred, and the
push outcome. Note any remote commits that were integrated.

## Common Pitfalls

| Pitfall | Avoidance |
| --- | --- |
| Running git commands inside `~/.dotfiles` | Always use the `--git-dir=... --work-tree=...` form. |
| Forgetting `-c status.showUntrackedFiles=no` | Prevents `git status` from listing every untracked file in `$HOME`. |
| Using the `dot` alias | Non-interactive shells do not load aliases; rely on the explicit git form. |
| Staging with `git add -A` or `git add .` | May stage everything in `$HOME`; always list explicit paths. |
| Skipping the pre-push fetch | Leads to rejected pushes; always fetch before pushing. |
| Auto-resolving rebase conflicts | Stop and ask the user; intent matters. |
| Forgetting to verify unrelated dirt | If the dirty paths are unrelated to this session, mention them but skip the workflow unless the user insists. |
