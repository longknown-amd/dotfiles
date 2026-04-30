---
name: dotfiles-sync
description: Stage, review, commit, and push changes to the user's dotfiles bare repo at ~/.dotfiles (work-tree=$HOME, remote on GitHub). Trigger automatically when the dotfiles repo has uncommitted changes (a UserPromptSubmit hook surfaces a reminder), OR when the user says "sync dotfiles", "push my dotfiles", "commit my config", or similar. Skip if the user explicitly says not to sync, or if the only dirty paths look unrelated to the current conversation.
---

# Sync Dotfiles

The user maintains their `$HOME` configuration in a **bare git repo** at `~/.dotfiles`, with `$HOME` itself as the work tree. The remote is `git@github.com-longknown:longknown-amd/dotfiles.git` (`origin/main`). Tracked paths include `~/.claude/`, `~/.config/nvim/`, shell rc files, etc.

There is a shell alias `dot` defined in `~/.zshrc` (`alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'`). **Do NOT rely on this alias from within tool calls** — Claude's Bash tool runs non-interactively and won't load `~/.zshrc`. Always use the full form:

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME -c status.showUntrackedFiles=no <subcommand>
```

The `-c status.showUntrackedFiles=no` flag is critical: `$HOME` contains thousands of untracked files; without it, `git status` will list every file in your home directory.

## When to invoke

- **Auto-trigger:** The `UserPromptSubmit` hook (`~/.claude/hooks/dotfiles-dirty-check.sh`) injects a reminder at the start of any turn where the dotfiles repo has uncommitted changes. When you see that reminder, propose syncing — but only if the dirt looks related to what you've been working on this conversation. If it looks like unrelated drift the user introduced manually, just mention it briefly and let them decide.
- **Explicit trigger:** The user says "sync dotfiles", "push my config", "commit my dotfiles", or invokes `/dotfiles-sync` directly.

## Workflow

### 1. Show the current state

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME -c status.showUntrackedFiles=no status -s
git --git-dir=$HOME/.dotfiles --work-tree=$HOME log --oneline -5
```

### 2. Stage the relevant files

Stage by explicit path. **Never** use `git add -A` or `git add .` — `$HOME` would pull in untracked junk if `status.showUntrackedFiles=no` ever gets bypassed downstream:

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add <path1> <path2> ...
```

If multiple unrelated topics are dirty (e.g., a Claude config edit AND an nvim lazy-lock change), prefer **separate commits** unless the user explicitly says to bundle them.

### 3. Show the staged diff and propose a commit message

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME --no-pager diff --staged
```

Draft a concise commit message (subject line ≤ 70 chars, imperative mood). Surface it to the user along with the diff.

### 4. Commit (only after the message is settled)

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -m "<message>"
```

If a pre-commit hook fails, fix the underlying issue and create a NEW commit — do not `--amend` and do not `--no-verify`.

### 5. Push — confirmation policy

Default behavior: **stage, diff, commit, then ask before push.** Show the user the new commit with `git log -1 --stat` and ask "OK to push to origin/main?"

**Exception** — skip the ask only if the user explicitly invoked the sync (e.g., they typed "sync dotfiles", "push my config", or `/dotfiles-sync`). In that case the request itself is the approval; push directly:

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME push
```

When the skill was invoked via the auto-detection hook reminder (not user request), always ask.

### 6. Report

Tell the user the commit SHA, files changed, and whether it was pushed. If pushed, mention the remote (`origin/main`).

## Common pitfalls

| Pitfall | Avoidance |
|---|---|
| Running `git status` inside `~/.dotfiles` | That's the bare repo dir — it errors. Always use `--git-dir=...` form from anywhere. |
| Forgetting `-c status.showUntrackedFiles=no` | You'll get a status output with every untracked file in `$HOME`. Always include the flag. |
| Using the `dot` alias in a Bash tool call | Aliases aren't loaded in non-interactive shells. Use the full `git --git-dir=...` invocation. |
| `git add -A` / `git add .` | Stages everything in `$HOME` if the flag protection slips. Stage explicit paths only. |
| Editing files inside `~/.dotfiles` directly | That's the bare-repo internal directory. The actual files live at their `$HOME` paths (e.g., `~/.claude/CLAUDE.md`, not `~/.dotfiles/...`). |
