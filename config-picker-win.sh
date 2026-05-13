#!/usr/bin/env bash
# Bootstrap Claude + Codex dotfiles on Windows (Git Bash / Claude Code bash).
#
# Usage (Git Bash or Claude Code terminal on a fresh Windows machine):
#   bash config-picker-win.sh
#
# What it does:
#   • Clones (or updates) the dotfiles bare repo into %USERPROFILE%\.dotfiles
#   • Checks out .claude/ and .codex/ configs into %USERPROFILE%
#   • Patches the UserPromptSubmit hook so it resolves %USERPROFILE% not $HOME
#     (on Windows, Git Bash sets $HOME to a network/mapped drive, not C:\Users\…)
#   • Merges any Windows-specific settings.json rules (deny lists, announcements)
#     on top of the dotfiles base settings
#
# Linux-only configs (zsh, tmux, nvim, yazi) are intentionally skipped.

set -euo pipefail

REPO_URL="git@github.com:longknown-amd/dotfiles.git"
REPO_URL_HTTPS="https://github.com/longknown-amd/dotfiles.git"
SSH_KEY_NAME="id_ed25519_longknown"   # key that has push access to the repo

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Resolve the Windows user home as a Unix-style path
#    On Git Bash / Claude Code's bash, $HOME is a mapped network drive (e.g.
#    /u/), NOT the real Windows user profile. We derive the correct path from
#    $USERPROFILE via cygpath.
# ---------------------------------------------------------------------------
if command -v cygpath >/dev/null 2>&1 && [[ -n "${USERPROFILE:-}" ]]; then
    WINHOME=$(cygpath -u "$USERPROFILE")
    log "Windows home resolved: $WINHOME  (from USERPROFILE=$USERPROFILE)"
else
    WINHOME="$HOME"
    warn "cygpath not found or USERPROFILE unset — using \$HOME=$HOME"
fi

DOT_DIR="$WINHOME/.dotfiles"
SSH_KEY="$WINHOME/.ssh/$SSH_KEY_NAME"

dot() { git --git-dir="$DOT_DIR" --work-tree="$WINHOME" "$@"; }

# ---------------------------------------------------------------------------
# 1. Verify SSH key exists
# ---------------------------------------------------------------------------
log "Checking SSH key: $SSH_KEY"
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY\nAdd it to GitHub first: ssh-keygen -t ed25519 -f $SSH_KEY"

export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no"

# ---------------------------------------------------------------------------
# 2. Clone or update the bare repo
# ---------------------------------------------------------------------------
if [[ -d "$DOT_DIR" ]]; then
    log "Bare repo already exists at $DOT_DIR — fetching latest"
    if dot fetch origin main:refs/remotes/origin/main 2>/dev/null; then
        dot update-ref refs/heads/main refs/remotes/origin/main 2>/dev/null \
            || warn "Could not fast-forward local main to origin/main"
    else
        warn "Fetch failed; proceeding with local HEAD"
    fi
else
    log "Cloning dotfiles bare repo into $DOT_DIR"
    if ! git clone --bare "$REPO_URL" "$DOT_DIR" 2>/dev/null; then
        warn "SSH clone failed — falling back to HTTPS (read-only)"
        git clone --bare "$REPO_URL_HTTPS" "$DOT_DIR"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Configure the bare repo
# ---------------------------------------------------------------------------
log "Configuring bare repo"
dot config --local status.showUntrackedFiles no
dot config --local core.sshCommand "ssh -i $SSH_KEY"
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# ---------------------------------------------------------------------------
# 4. Backup existing Claude settings before overwriting
# ---------------------------------------------------------------------------
CLAUDE_SETTINGS="$WINHOME/.claude/settings.json"
SETTINGS_BACKUP=""
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    SETTINGS_BACKUP="$WINHOME/.claude/settings.json.pre-dotfiles-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing settings.json → $SETTINGS_BACKUP"
    cp "$CLAUDE_SETTINGS" "$SETTINGS_BACKUP"
fi

# ---------------------------------------------------------------------------
# 5. Selectively check out .claude/ and .codex/ only
#    (Linux-only paths like .zshrc, .tmux.conf, .config/nvim are skipped)
# ---------------------------------------------------------------------------
log "Checking out .claude/ and .codex/ from HEAD"
dot checkout HEAD -- .claude/ .codex/ .agents/ 2>/dev/null \
    || dot checkout HEAD -f -- .claude/ .codex/ .agents/

# ---------------------------------------------------------------------------
# 6. Patch the dirty-check hook for Windows
#    The hook uses $HOME which resolves to the network drive on Windows.
#    Replace the GIT_DIR/WORK_TREE assignments with a cross-platform block.
# ---------------------------------------------------------------------------
HOOK="$WINHOME/.claude/hooks/dotfiles-dirty-check.sh"
if [[ -f "$HOOK" ]] && ! grep -q "USERPROFILE" "$HOOK"; then
    log "Patching $HOOK for Windows HOME vs USERPROFILE"
    python3 - "$HOOK" <<'PY'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

old = 'GIT_DIR="$HOME/.dotfiles"\nWORK_TREE="$HOME"'
new = (
    '# Cross-platform home (Windows Git Bash: $HOME != %USERPROFILE%)\n'
    'if command -v cygpath >/dev/null 2>&1 && [[ -n "${USERPROFILE:-}" ]]; then\n'
    '    _EFF_HOME=$(cygpath -u "$USERPROFILE")\n'
    'else\n'
    '    _EFF_HOME="$HOME"\n'
    'fi\n'
    'GIT_DIR="$_EFF_HOME/.dotfiles"\n'
    'WORK_TREE="$_EFF_HOME"'
)

if old not in content:
    print("Pattern not found — hook may already be patched or has changed. Skipping.")
    sys.exit(0)

content = content.replace(old, new)
with open(path, 'w') as f:
    f.write(content)
print("Patched successfully.")
PY
else
    log "Hook already patched or not present — skipping"
fi
chmod +x "$HOOK" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 7. Patch settings.json
#    • Fix the hook command to invoke the script via bash with USERPROFILE path
#      (so Claude Code's hook runner finds it on the right drive)
#    • Merge any Windows-specific deny/ask rules from the backup on top of the
#      dotfiles base
# ---------------------------------------------------------------------------
log "Patching settings.json for Windows"
python3 - "$CLAUDE_SETTINGS" "${SETTINGS_BACKUP:-}" <<'PY'
import json, sys, re

settings_path = sys.argv[1]
backup_path   = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""

with open(settings_path) as f:
    merged = json.load(f)

# -- 7a. Fix hook command: replace $HOME with bash + USERPROFILE invocation --
def fix_hook_command(cmd):
    # Replace bare $HOME script invocation with an explicit bash call using
    # $USERPROFILE so it resolves correctly on Windows.
    return re.sub(
        r'\$HOME(/.+\.sh\b)',
        r'bash "$USERPROFILE\1"',
        cmd
    )

for event_list in merged.get("hooks", {}).values():
    for hook_group in event_list:
        for hook in hook_group.get("hooks", []):
            if hook.get("type") == "command":
                hook["command"] = fix_hook_command(hook["command"])

# -- 7b. Merge deny/allow/ask from backed-up Windows settings ----------------
if backup_path:
    try:
        with open(backup_path) as f:
            win = json.load(f)
        def merge_list(base, extra):
            seen = list(base)
            for item in extra:
                if item not in seen:
                    seen.append(item)
            return seen
        bp = merged.setdefault("permissions", {})
        wp = win.get("permissions", {})
        for key in ("allow", "deny", "ask"):
            bp[key] = merge_list(bp.get(key, []), wp.get(key, []))
        # Remove empty lists
        merged["permissions"] = {k: v for k, v in bp.items() if v}
        # Keep Windows companyAnnouncements if dotfiles base has none
        if "companyAnnouncements" in win and "companyAnnouncements" not in merged:
            merged["companyAnnouncements"] = win["companyAnnouncements"]
    except Exception as e:
        print(f"Warning: could not merge backup settings: {e}", file=sys.stderr)

with open(settings_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
print("settings.json patched.")
PY

# ---------------------------------------------------------------------------
# 8. Done
# ---------------------------------------------------------------------------
log "Done. Claude and Codex configs synced from dotfiles."
cat <<EOF

  Bare repo : $DOT_DIR
  Work-tree : $WINHOME
  Remote    : $(dot remote get-url origin)

  To use the dot alias in Git Bash, add to ~/.bashrc:
    alias dot='git --git-dir=$WINHOME/.dotfiles --work-tree=$WINHOME'

  To pull latest dotfiles later, just re-run this script:
    bash $WINHOME/config-picker-win.sh

EOF
