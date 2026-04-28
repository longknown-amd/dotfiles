#!/usr/bin/env bash
# Pick up dotfiles configs on a fresh Ubuntu machine.
#
# Usage (one-liner on a new box):
#   curl -fsSL https://raw.githubusercontent.com/longknown-amd/dotfiles/main/config-picker.sh | bash
# or:
#   bash config-picker.sh

set -euo pipefail

REPO_URL="git@github.com:longknown-amd/dotfiles.git"
REPO_URL_HTTPS="https://github.com/longknown-amd/dotfiles.git"
DOT_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

dot() { git --git-dir="$DOT_DIR" --work-tree="$HOME" "$@"; }

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }

# 1. Prerequisites -----------------------------------------------------------
log "Checking prerequisites"
need_pkgs=()
command -v git >/dev/null    || need_pkgs+=(git)
command -v zsh >/dev/null    || need_pkgs+=(zsh)
command -v curl >/dev/null   || need_pkgs+=(curl)
command -v tmux >/dev/null   || need_pkgs+=(tmux)
command -v nvim >/dev/null   || need_pkgs+=(neovim)
command -v xclip >/dev/null  || need_pkgs+=(xclip)
command -v axel >/dev/null   || need_pkgs+=(axel)
if (( ${#need_pkgs[@]} )); then
    log "Installing: ${need_pkgs[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${need_pkgs[@]}"
fi

# 1b. Rust toolchain (cargo) -------------------------------------------------
# Some configs depend on cargo-installed binaries. Use rustup rather than apt
# so we get an up-to-date toolchain.
if ! command -v cargo >/dev/null; then
    log "Installing Rust toolchain via rustup"
    sudo apt-get install -y build-essential pkg-config libssl-dev
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --no-modify-path
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
else
    log "cargo already installed: $(cargo --version)"
fi

# 1c. Yazi file manager ------------------------------------------------------
# Installed via cargo so we get a recent build matching the tracked
# ~/.config/yazi/ plugins.
if ! command -v yazi >/dev/null; then
    log "Installing yazi (yazi-fm + yazi-cli) via cargo"
    # ffmpeg/7zip/jq/poppler/fd/ripgrep/fzf/zoxide/imagemagick are yazi's
    # recommended runtime deps for previews and integrations.
    sudo apt-get install -y \
        ffmpeg p7zip-full jq poppler-utils fd-find ripgrep fzf zoxide imagemagick
    cargo install --locked yazi-fm yazi-cli
else
    log "yazi already installed: $(yazi --version | head -1)"
fi

# 1d. oh-my-zsh + custom plugins ---------------------------------------------
# .zshrc sources $ZSH/oh-my-zsh.sh and references three non-bundled plugins.
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
if [[ ! -d "$ZSH" ]]; then
    log "Installing oh-my-zsh (unattended)"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    log "oh-my-zsh already installed"
fi
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
declare -A omz_plugins=(
    [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions.git"
    [zsh-completions]="https://github.com/zsh-users/zsh-completions.git"
)
for name in "${!omz_plugins[@]}"; do
    dest="$ZSH_CUSTOM/plugins/$name"
    if [[ ! -d "$dest" ]]; then
        log "Cloning OMZ plugin: $name"
        git clone --depth 1 "${omz_plugins[$name]}" "$dest"
    fi
done

# 2. Clone the bare repo -----------------------------------------------------
if [[ -d "$DOT_DIR" ]]; then
    log "$DOT_DIR already exists, skipping clone"
else
    log "Cloning dotfiles into $DOT_DIR"
    if ! git clone --bare "$REPO_URL" "$DOT_DIR" 2>/dev/null; then
        warn "SSH clone failed, falling back to HTTPS (read-only)"
        git clone --bare "$REPO_URL_HTTPS" "$DOT_DIR"
    fi
fi

# 3. Local repo config -------------------------------------------------------
log "Configuring repo (hide untracked, set ignore file)"
dot config --local status.showUntrackedFiles no
dot config --local core.excludesFile "$HOME/.config/git/dot-ignore"

# 4. Checkout, backing up any conflicting files ------------------------------
log "Checking out files into \$HOME"
if ! dot checkout 2>/dev/null; then
    warn "Conflicts detected — backing up to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    # Each conflicting path is listed after the warning header.
    dot checkout 2>&1 \
        | grep -E "^\s+\." \
        | awk '{print $1}' \
        | while read -r f; do
              src="$HOME/$f"
              [[ -e "$src" ]] || continue
              dest="$BACKUP_DIR/$f"
              mkdir -p "$(dirname "$dest")"
              mv "$src" "$dest"
          done
    dot checkout
    log "Backed-up originals are in $BACKUP_DIR"
fi

# 4b. tmux plugins (TPM) -----------------------------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
    log "Installing TPM (tmux plugin manager)"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    log "TPM already present, updating"
    git -C "$TPM_DIR" pull --ff-only --quiet || true
fi
log "Installing tmux plugins headlessly"
"$TPM_DIR/bin/install_plugins" >/dev/null

# 4c. Yazi plugins -----------------------------------------------------------
# Tracked package.toml lists code/mime-ext/rich-preview; fetch them now.
if command -v ya >/dev/null && [[ -f "$HOME/.config/yazi/package.toml" ]]; then
    log "Installing yazi plugins via ya pack -i"
    ya pack -i || warn "ya pack -i had issues — check ~/.config/yazi/package.toml"
fi

# 4d. Neovim plugins (lazy.nvim) ---------------------------------------------
# lazy.lua self-bootstraps on first launch; do it headlessly so LSPs,
# treesitter parsers, and DAP adapters are ready before the first interactive run.
if command -v nvim >/dev/null && [[ -f "$HOME/.config/nvim/init.lua" ]]; then
    log "Syncing nvim plugins headlessly (this can take a minute)"
    nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5 || \
        warn "Lazy sync exited non-zero — open nvim to inspect"
fi

# 5. Done --------------------------------------------------------------------
log "Done. Next steps:"
cat <<'EOF'

  • Open a new shell (or `exec zsh`) to pick up the new ~/.zshrc.
  • Use `dot` instead of `git` for dotfile changes:
        dot status -u           # list untracked too
        dot add ~/.zshrc
        dot commit -m "tweak"
        dot push
  • If your default shell isn't zsh:  chsh -s "$(command -v zsh)"
  • Inside tmux, prefix + I re-fetches plugins; prefix + U updates them.

EOF
