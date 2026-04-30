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

- **Auto-trigger:** The `UserPromptSubmit` hook (`~/.claude/hooks/dotfiles-dirty-check.sh`) injects a reminder at the start of any turn where the dotfiles repo has uncommitted tracked changes. The hook only checks local state (it does NOT contact the remote — that would add network latency to every prompt). Remote-sync checking happens here, at push time. When you see the reminder, propose syncing — but only if the dirt looks related to what you've been working on this conversation.
- **Explicit trigger:** The user says "sync dotfiles", "push my config", "commit my dotfiles", or invokes `/dotfiles-sync` directly.

## Workflow

### 1. Show the current local state

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME -c status.showUntrackedFiles=no status -s
git --git-dir=$HOME/.dotfiles --work-tree=$HOME log --oneline -5
```

### 2. Stage the relevant files

Stage by explicit path (use absolute `$HOME/...` paths so resolution is independent of the current directory). **Never** use `git add -A` or `git add .`:

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add $HOME/<path1> $HOME/<path2> ...
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

### 5. Sync with remote BEFORE push

This is mandatory and applies on every push, regardless of how the skill was invoked. The remote may have advanced from another machine since your last sync.

```sh
# Refresh the cached remote-tracking ref.
git --git-dir=$HOME/.dotfiles fetch origin main

# Compute divergence.
ahead=$(git --git-dir=$HOME/.dotfiles rev-list --count origin/main..HEAD)
behind=$(git --git-dir=$HOME/.dotfiles rev-list --count HEAD..origin/main)
echo "local is ahead by $ahead, behind by $behind"
```

Decide based on `(ahead, behind)`:

| `ahead` | `behind` | Action |
|---|---|---|
| 0 | 0 | Already in sync. Nothing to push. Skip step 6. |
| ≥1 | 0 | Local is purely ahead. Safe fast-forward. Continue to step 6. |
| 0 | ≥1 | Remote is purely ahead. Run `git pull --ff-only` (or `git merge --ff-only origin/main`). Re-check; usually nothing to push. |
| ≥1 | ≥1 | True divergence. **Rebase** local commits on top of remote: `git --git-dir=$HOME/.dotfiles --work-tree=$HOME rebase origin/main`. Show the user what's coming from the remote (`git log HEAD..origin/main --stat`) before rebasing, especially if any remote-only file overlaps a file you just committed (conflict risk). |

If a rebase produces conflicts, stop and show the user — do NOT auto-resolve. They can decide between resolving manually or `git rebase --abort` to back out.

### 6. Push — confirmation policy

Default behavior: **ask before push.** Show the user the new commit(s) with `git log -1 --stat` (or `git log origin/main..HEAD --stat` if multiple) and ask "OK to push to origin/main?"

**Exception** — skip the ask only if the user explicitly invoked the sync (e.g., they typed "sync dotfiles", "push my config", or `/dotfiles-sync`). In that case the request itself is the approval; push directly.

```sh
git --git-dir=$HOME/.dotfiles --work-tree=$HOME push
```

When the skill was invoked via the auto-detection hook reminder (not user request), always ask.

If the push is rejected anyway (race condition: remote advanced again between your fetch in step 5 and your push), repeat step 5 once.

### 7. Report

Tell the user the commit SHA(s), files changed, and whether it was pushed. If the push integrated remote work via rebase, mention the rebased commits' new SHAs (the original local SHAs no longer exist after rebase — that's expected and harmless since they were never pushed).

## Common pitfalls

| Pitfall | Avoidance |
|---|---|
| Running `git status` inside `~/.dotfiles` | That's the bare repo dir — it errors. Always use `--git-dir=...` form from anywhere. |
| Forgetting `-c status.showUntrackedFiles=no` | You'll get a status output with every untracked file in `$HOME`. Always include the flag. |
| Using the `dot` alias in a Bash tool call | Aliases aren't loaded in non-interactive shells. Use the full `git --git-dir=...` invocation. |
| `git add -A` / `git add .` | Stages everything in `$HOME` if the flag protection slips. Stage explicit paths only. |
| Editing files inside `~/.dotfiles` directly | That's the bare-repo internal directory. The actual files live at their `$HOME` paths (e.g., `~/.claude/CLAUDE.md`, not `~/.dotfiles/...`). |
| Skipping step 5 (the pre-push fetch) | This is exactly how you get a "rejected — fetch first" error and have to recover manually. Always fetch before pushing, even if you `git pull`-ed at the start of the session — the remote can advance during the work. |
| Auto-resolving rebase conflicts | Stop and show the user. Conflict resolution requires intent the skill can't infer. |
| First push of a brand-new branch | `git push --set-upstream origin main` is needed once to establish tracking. After that, plain `git push` works. |
