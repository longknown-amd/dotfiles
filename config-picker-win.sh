#!/usr/bin/env bash
# Bootstrap Claude + Codex dotfiles on Windows (Git Bash / Claude Code bash).
#
# Usage (Git Bash or Claude Code terminal on a fresh Windows machine):
#   bash config-picker-win.sh
#
# What it does:
#   • Clones (or updates) the dotfiles bare repo into %USERPROFILE%\.dotfiles
#   • Checks out only Windows-relevant paths from HEAD:
#       .claude/  .codex/  config-picker.sh  config-picker-win.sh
#     Linux-only configs (zsh, tmux, nvim, yazi, .agents, etc.) are skipped.
#   • Merges any Windows-specific settings.json rules (deny lists, announcements)
#     on top of the dotfiles base settings
#
# SSH access to the repo is assumed to be already configured in ~/.ssh/config
# (host alias + key path). The script does not touch SSH state.
#
# The UserPromptSubmit hook is a Python script (dotfiles-dirty-check.py) that
# uses os.path.expanduser('~') for cross-platform home resolution.

set -euo pipefail

REPO_URL="git@github.com:longknown-amd/dotfiles.git"
REPO_URL_HTTPS="https://github.com/longknown-amd/dotfiles.git"

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

dot() { git --git-dir="$DOT_DIR" --work-tree="$WINHOME" "$@"; }

# ---------------------------------------------------------------------------
# 1. Clone or update the bare repo
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
# 2. Configure the bare repo
# ---------------------------------------------------------------------------
log "Configuring bare repo"
dot config --local status.showUntrackedFiles no
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# ---------------------------------------------------------------------------
# 3. Backup existing Claude settings before overwriting
# ---------------------------------------------------------------------------
CLAUDE_SETTINGS="$WINHOME/.claude/settings.json"
SETTINGS_BACKUP=""
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    SETTINGS_BACKUP="$WINHOME/.claude/settings.json.pre-dotfiles-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing settings.json → $SETTINGS_BACKUP"
    cp "$CLAUDE_SETTINGS" "$SETTINGS_BACKUP"
fi

# ---------------------------------------------------------------------------
# 4. Selectively check out Windows-relevant paths only
# ---------------------------------------------------------------------------
CHECKOUT_PATHS=(.claude/ .codex/ config-picker.sh config-picker-win.sh)
log "Checking out from HEAD: ${CHECKOUT_PATHS[*]}"
dot checkout HEAD -- "${CHECKOUT_PATHS[@]}" 2>/dev/null \
    || dot checkout HEAD -f -- "${CHECKOUT_PATHS[@]}"

# ---------------------------------------------------------------------------
# 5. Merge Windows-specific settings on top of the dotfiles base
#    The hook command (python3 dotfiles-dirty-check.py) already works
#    cross-platform via os.path.expanduser — no patching needed.
# ---------------------------------------------------------------------------
log "Merging Windows-specific settings into settings.json"
python3 - "$CLAUDE_SETTINGS" "${SETTINGS_BACKUP:-}" <<'PY'
import json, sys

settings_path = sys.argv[1]
backup_path   = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""

with open(settings_path, encoding='utf-8') as f:
    merged = json.load(f)

if backup_path:
    try:
        with open(backup_path, encoding='utf-8') as f:
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
        merged["permissions"] = {k: v for k, v in bp.items() if v}

        if "companyAnnouncements" in win and "companyAnnouncements" not in merged:
            merged["companyAnnouncements"] = win["companyAnnouncements"]

    except Exception as e:
        print(f"Warning: could not merge backup settings: {e}", file=sys.stderr)

with open(settings_path, 'w', encoding='utf-8', newline='\n') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
print("settings.json merged.")
PY

# ---------------------------------------------------------------------------
# 6. Done
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
