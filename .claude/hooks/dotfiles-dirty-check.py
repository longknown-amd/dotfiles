#!/usr/bin/env python3
"""
UserPromptSubmit hook: notify Claude when the dotfiles bare repo has uncommitted
tracked changes.  Cross-platform: works on Linux and Windows (Git Bash / native).

Python's os.path.expanduser('~') resolves the real OS home directory on both
platforms, so no USERPROFILE vs $HOME juggling is needed here.

On Windows the hook also filters out "D"-status deletions for Linux-only paths
(nvim, yazi, tmux, zsh, etc.) so they don't generate constant noise.
"""
import json, os, subprocess, sys

# ----------------------------------------------------------------------------
# Linux-only path prefixes that are intentionally absent on Windows.
# Deletions under these paths are suppressed from the Windows dirty report.
# ----------------------------------------------------------------------------
LINUX_ONLY_PREFIXES = (
    '.config/nvim/',
    '.config/yazi/',
    '.config/git/',
    '.local/bin/',
    '.tmux.conf',
    '.zshrc',
    '.zshenv',
    'config-picker.sh',
)

home     = os.path.expanduser('~')
git_dir  = os.path.join(home, '.dotfiles')
work_tree = home

if not os.path.isdir(git_dir):
    sys.exit(0)

try:
    result = subprocess.run(
        ['git', '--git-dir', git_dir, '--work-tree', work_tree,
         '-c', 'status.showUntrackedFiles=no', 'status', '--porcelain'],
        capture_output=True, text=True, timeout=10,
    )
    lines = result.stdout.splitlines()
except Exception:
    sys.exit(0)

# On Windows, suppress expected deletions of Linux-only tracked files.
is_windows = os.name == 'nt' or bool(os.environ.get('USERPROFILE'))
if is_windows:
    lines = [
        l for l in lines
        if not (l.startswith('D ') and any(l[3:].startswith(p) for p in LINUX_ONLY_PREFIXES))
    ]

status = '\n'.join(lines).strip()
if not status:
    sys.exit(0)

msg = (
    'Dotfiles repo (~/.dotfiles, bare repo, work-tree=$HOME) has uncommitted '
    'tracked changes:\n\n'
    f'{status}\n\n'
    'If these changes resulted from work in this conversation and look ready to '
    'persist, invoke the dotfiles-sync skill to stage, diff, and (with the '
    "user's approval) push them. If the dirt is unrelated drift, mention it "
    'briefly and let the user decide.'
)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': msg,
    }
}))
