#!/usr/bin/env bash
# UserPromptSubmit hook: if the dotfiles bare repo at ~/.dotfiles has uncommitted
# tracked changes, emit a JSON additionalContext block reminding Codex to offer
# the dotfiles-sync skill. No-op when clean.
set -uo pipefail

GIT_DIR="$HOME/.dotfiles"
WORK_TREE="$HOME"

# Bail silently if the bare repo is missing (e.g., on a fresh machine).
[ -d "$GIT_DIR" ] || exit 0

status=$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" \
    -c status.showUntrackedFiles=no status --porcelain 2>/dev/null) || exit 0

[ -z "$status" ] && exit 0

python3 - "$status" <<'PY'
import json, sys
status = sys.argv[1]
msg = (
    "Dotfiles repo (~/.dotfiles, bare repo, work-tree=$HOME) has uncommitted "
    "tracked changes:\n\n"
    f"{status}\n\n"
    "If these changes resulted from work in this conversation and look ready to "
    "persist, invoke the dotfiles-sync skill to stage, diff, and (with the "
    "user's approval) push them. If the dirt is unrelated drift, mention it "
    "briefly and let the user decide."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": msg,
    }
}))
PY
