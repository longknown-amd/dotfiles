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

# 0. Raise FD limit ----------------------------------------------------------
# Default Ubuntu soft limit (1024) is too low for rustc's parallel codegen on
# large dep graphs — yazi triggers EMFILE in rustix's build script. Bump the
# soft limit for this script's process tree only (hard limit is unchanged).
fd_hard=$(ulimit -Hn)
fd_target=65536
(( fd_hard < fd_target )) && fd_target=$fd_hard
if ulimit -Sn "$fd_target" 2>/dev/null; then
    log "FD soft limit raised to $(ulimit -Sn) (hard: $fd_hard)"
else
    warn "Could not raise FD limit (current: $(ulimit -Sn))"
fi

# 1. Prerequisites -----------------------------------------------------------
log "Checking prerequisites"
need_pkgs=()
command -v git >/dev/null    || need_pkgs+=(git)
command -v zsh >/dev/null    || need_pkgs+=(zsh)
command -v curl >/dev/null   || need_pkgs+=(curl)
command -v tmux >/dev/null   || need_pkgs+=(tmux)
command -v xclip >/dev/null  || need_pkgs+=(xclip)
command -v xsel >/dev/null   || need_pkgs+=(xsel)
command -v axel >/dev/null   || need_pkgs+=(axel)
command -v fzf >/dev/null    || need_pkgs+=(fzf)
command -v lldb-dap >/dev/null || need_pkgs+=(lldb)
# (neovim is handled separately below — apt's version is too old.)
if (( ${#need_pkgs[@]} )); then
    log "Installing: ${need_pkgs[*]}"
    # Intentionally NOT running `apt-get update` here — refreshing the
    # system-wide apt cache could surface unrelated upgrades on the host.
    # If installs fail because the cache is stale, run `sudo apt-get update`
    # manually and re-run this script.
    sudo apt-get install -y "${need_pkgs[@]}"
fi

# 1a. Neovim (from upstream release if missing or too old) ------------------
# Distro-packaged nvim lags badly: Ubuntu 22.04 ships 0.6, 24.04 ships 0.9,
# but our nvim config (treesitter `main` branch, etc.) needs >= 0.11. So we
# pull the official tarball from GitHub releases and install per-user under
# ~/.local — no sudo, no host package state changes.
NVIM_MIN="0.12.0"
NVIM_PREFIX="$HOME/.local/share/neovim"
mkdir -p "$HOME/.local/bin" "$NVIM_PREFIX"
ensure_path_local_bin() { case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac; }
ensure_path_local_bin
nvim_cur=""
if command -v nvim >/dev/null; then
    nvim_cur=$(nvim --version | head -1 | awk '{print $2}' | sed 's/^v//')
fi
# version_ge "a" "b" → 0 if a >= b
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }
if [[ -z "$nvim_cur" ]] || ! version_ge "$nvim_cur" "$NVIM_MIN"; then
    case "$(uname -m)" in
        x86_64)  nv_asset="nvim-linux-x86_64.tar.gz" ;;
        aarch64) nv_asset="nvim-linux-arm64.tar.gz"  ;;
        *)       die "Unsupported arch for nvim binary release: $(uname -m)" ;;
    esac
    log "Installing latest nvim from upstream ($nv_asset; current: ${nvim_cur:-none}, need >= $NVIM_MIN)"
    nv_url="https://github.com/neovim/neovim/releases/latest/download/$nv_asset"
    nv_tmp=$(mktemp -d)
    curl -fsSL "$nv_url" -o "$nv_tmp/nvim.tar.gz"
    tar -xzf "$nv_tmp/nvim.tar.gz" -C "$nv_tmp"
    nv_extracted=$(find "$nv_tmp" -maxdepth 1 -mindepth 1 -type d -name 'nvim-linux-*' | head -1)
    [[ -d "$nv_extracted" ]] || die "Could not find extracted nvim dir under $nv_tmp"
    nv_dest="$NVIM_PREFIX/$(basename "$nv_extracted")"
    rm -rf "$nv_dest"
    mv "$nv_extracted" "$nv_dest"
    ln -sfn "$nv_dest" "$NVIM_PREFIX/current"
    ln -sfn "$NVIM_PREFIX/current/bin/nvim" "$HOME/.local/bin/nvim"
    rm -rf "$nv_tmp"
    log "Installed $("$HOME/.local/bin/nvim" --version | head -1) → ~/.local/bin/nvim"
else
    log "neovim $nvim_cur is recent enough (>= $NVIM_MIN)"
fi

# 1a2. Node.js / npm (for mason to install pyright et al.) -----------------
# Mason installs npm-based LSPs (pyright, bash-language-server) via npm.
# Distro nodejs lags badly (Ubuntu 22.04 ships v12, too old for current
# pyright). Pull the official Linux tarball from nodejs.org per-user.
NODE_MIN="18.0.0"
NODE_PREFIX="$HOME/.local/share/node"
node_cur=""
if command -v node >/dev/null; then
    node_cur=$(node --version | sed 's/^v//')
fi
if [[ -z "$node_cur" ]] || ! version_ge "$node_cur" "$NODE_MIN"; then
    case "$(uname -m)" in
        x86_64)  nd_arch="linux-x64" ;;
        aarch64) nd_arch="linux-arm64" ;;
        *)       die "Unsupported arch for Node.js binary: $(uname -m)" ;;
    esac
    # `xz` is needed to extract Node's .tar.xz; install if missing.
    command -v xz >/dev/null || sudo apt-get install -y xz-utils
    log "Resolving latest Node.js LTS from nodejs.org"
    nd_lts=$(curl -fsSL https://nodejs.org/dist/index.json \
        | python3 -c "import json,sys; print(next(x for x in json.load(sys.stdin) if x['lts'])['version'])")
    log "Installing Node.js $nd_lts ($nd_arch; current: ${node_cur:-none}, need >= $NODE_MIN)"
    nd_tmp=$(mktemp -d)
    curl -fsSL "https://nodejs.org/dist/$nd_lts/node-$nd_lts-$nd_arch.tar.xz" -o "$nd_tmp/node.tar.xz"
    tar -xJf "$nd_tmp/node.tar.xz" -C "$nd_tmp"
    nd_extracted=$(find "$nd_tmp" -maxdepth 1 -mindepth 1 -type d -name "node-*" | head -1)
    [[ -d "$nd_extracted" ]] || die "Could not find extracted node dir under $nd_tmp"
    mkdir -p "$NODE_PREFIX"
    nd_dest="$NODE_PREFIX/$(basename "$nd_extracted")"
    rm -rf "$nd_dest"
    mv "$nd_extracted" "$nd_dest"
    ln -sfn "$nd_dest" "$NODE_PREFIX/current"
    for b in node npm npx corepack; do
        [[ -e "$NODE_PREFIX/current/bin/$b" ]] && \
            ln -sfn "$NODE_PREFIX/current/bin/$b" "$HOME/.local/bin/$b"
    done
    rm -rf "$nd_tmp"
    log "Installed $("$HOME/.local/bin/node" --version) → ~/.local/bin/{node,npm,npx}"
else
    log "node $node_cur is recent enough (>= $NODE_MIN)"
fi

# 1a3. Python CLI tools ------------------------------------------------------
# rich-cli: invoked by yazi's rich-preview plugin (markdown/json/csv/etc).
# debugpy:  imported by nvim DAP-Python (`python -m debugpy.adapter`).
# rich-cli is a CLI app — install via pipx (isolated venv on $PATH).
# debugpy is a library nvim's `python` must `import` — prefer the apt
# package (puts it in system python's site-packages, which the user's
# `python` typically still resolves via stdlib path); fall back to
# `pip install --user` with PEP 668 escape hatch on bare Ubuntu 24.04+.
if ! command -v pipx >/dev/null; then
    log "Installing pipx (for rich-cli)"
    sudo apt-get install -y pipx
    pipx ensurepath >/dev/null 2>&1 || true
fi
if ! pipx list 2>/dev/null | grep -qE '^[[:space:]]*package rich-cli '; then
    log "Installing rich-cli via pipx"
    pipx install rich-cli
else
    log "rich-cli already installed (pipx)"
fi
if ! python3 -c 'import debugpy' 2>/dev/null; then
    log "Installing debugpy (python3-debugpy via apt, pip --user fallback)"
    sudo apt-get install -y python3-debugpy 2>/dev/null \
        || python3 -m pip install --user --break-system-packages debugpy \
        || python3 -m pip install --user debugpy
else
    log "debugpy already importable in system python3"
fi

# 1b. Rust toolchain (cargo) — declared, installed lazily ------------------
# We only install rustup when a later step actually needs cargo (yazi or
# tree-sitter). On a re-run where both binaries already exist, cargo never
# gets touched and the cleanup step won't wipe a pre-existing user install.
# Source the env shim if present so an existing cargo lands on PATH.
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
RUSTUP_INSTALLED_HERE=false
install_rustup() {
    log "Installing Rust toolchain via rustup"
    sudo apt-get install -y build-essential pkg-config libssl-dev
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --no-modify-path
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
    RUSTUP_INSTALLED_HERE=true
}
ensure_cargo() {
    if command -v cargo >/dev/null && cargo --version >/dev/null 2>&1; then
        return 0
    fi
    if command -v cargo >/dev/null; then
        # Proxy present but no usable toolchain (e.g., prior cleanup wiped
        # ~/.rustup but left the proxies). Try recovery first.
        warn "cargo proxy present but no toolchain configured — attempting recovery"
        if command -v rustup >/dev/null && rustup default stable; then
            log "Recovered: $(cargo --version)"
            return 0
        fi
    fi
    install_rustup
}

# 1c. Yazi file manager ------------------------------------------------------
# Installed via cargo so we get a recent build matching the tracked
# ~/.config/yazi/ plugins.
if ! command -v yazi >/dev/null; then
    ensure_cargo
    log "Installing yazi (via yazi-build meta-crate) via cargo"
    # ffmpeg/7zip/jq/poppler/fd/ripgrep/zoxide/imagemagick are yazi's
    # recommended runtime deps for previews and integrations. (fzf is in the
    # top-level prereq block since .zshrc also depends on it.)
    sudo apt-get install -y \
        ffmpeg p7zip-full jq poppler-utils fd-find ripgrep zoxide imagemagick
    # As of yazi v25+, `yazi-fm`/`yazi-cli` panic in their build scripts and
    # demand the `yazi-build` meta-crate (resolves both with consistent
    # features). Don't pass --locked: yazi-build's Cargo.lock pins a yanked
    # core2 0.4.0, so let cargo resolve a current version.
    cargo install --force yazi-build
else
    log "yazi already installed: $(yazi --version | head -1)"
fi

# 1c2. tree-sitter CLI -------------------------------------------------------
# Required by nvim-treesitter `main` branch (>= 0.26.1) — the rewrite
# delegates parser compilation to this binary. Without it, parser installs
# fail silently / with ENOENT 'tree-sitter'.
if ! command -v tree-sitter >/dev/null; then
    ensure_cargo
    log "Installing tree-sitter-cli via cargo"
    # tree-sitter-cli depends on rquickjs-sys → bindgen, which needs
    # libclang.so at build time to generate Rust FFI bindings.
    sudo apt-get install -y libclang-dev
    cargo install --locked tree-sitter-cli
else
    log "tree-sitter already installed: $(tree-sitter --version)"
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

# 4. Restore tracked files into $HOME ---------------------------------------
# Use `checkout HEAD -- :/` (unambiguous pathspec from work-tree root) to
# actually populate / restore tracked files. Plain `dot checkout` with no
# pathspec only prints status — it does NOT restore deleted files.
# Force-overwrites local modifications to tracked files; back them up first
# so the user doesn't silently lose anything.
log "Checking for locally modified tracked files"
modified=$(dot diff --name-only HEAD 2>/dev/null || true)
if [[ -n "$modified" ]]; then
    warn "Local modifications detected — backing up to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    while IFS= read -r f; do
        [[ -e "$HOME/$f" ]] || continue
        dest="$BACKUP_DIR/$f"
        mkdir -p "$(dirname "$dest")"
        cp -a "$HOME/$f" "$dest"
    done <<< "$modified"
    log "Backed-up originals are in $BACKUP_DIR"
fi
log "Restoring tracked files from HEAD into \$HOME"
dot checkout HEAD -- :/

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
# yazi v25+ renamed `ya pack` to `ya pkg`; install-all is now `ya pkg install`.
if command -v ya >/dev/null && [[ -f "$HOME/.config/yazi/package.toml" ]]; then
    log "Installing yazi plugins via ya pkg install"
    ya pkg install || warn "ya pkg install had issues — check ~/.config/yazi/package.toml"
fi

# 4d. Neovim plugins (lazy.nvim) ---------------------------------------------
# Pre-clone lazy.nvim from the shell rather than relying on lua/config/lazy.lua's
# self-bootstrap: that bootstrap calls getchar() on failure, which hangs in
# `--headless` mode if the clone fails. With lazy.nvim already on disk, the
# headless sync just installs the plugin specs and exits cleanly.
if command -v nvim >/dev/null && [[ -f "$HOME/.config/nvim/init.lua" ]]; then
    LAZY_DIR="$HOME/.local/share/nvim/lazy/lazy.nvim"
    if [[ ! -d "$LAZY_DIR" ]]; then
        log "Bootstrapping lazy.nvim"
        mkdir -p "$(dirname "$LAZY_DIR")"
        git clone --filter=blob:none --branch=stable \
            https://github.com/folke/lazy.nvim.git "$LAZY_DIR"
    else
        log "lazy.nvim already present"
    fi
    log "Syncing nvim plugins headlessly (this can take a minute)"
    nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5 || \
        warn "Lazy sync exited non-zero — open nvim to inspect"
fi

# 4e. Cleanup build intermediates --------------------------------------------
# The Rust toolchain was only needed to compile yazi-build / tree-sitter-cli.
# Once those binaries are in ~/.cargo/bin, ~/.rustup (~1.5 GB) and the cargo
# download caches are dead weight.
# Only clean up if WE installed rustup this run — never wipe a pre-existing
# user install. Set KEEP_RUST=1 to force-skip even when we did install it.
if $RUSTUP_INSTALLED_HERE && [[ "${KEEP_RUST:-0}" != "1" ]]; then
    log "Cleaning up build intermediates (set KEEP_RUST=1 to skip)"
    before=$(du -sh "$HOME/.rustup" "$HOME/.cargo" 2>/dev/null | awk '{s+=$1} END {print s}' || echo "?")
    rm -rf "$HOME/.rustup" \
           "$HOME/.cargo/registry" \
           "$HOME/.cargo/git" \
           /tmp/cargo-install* /tmp/rustup-init* 2>/dev/null || true
    # Drop rustup proxy binaries (cargo, rustc, ...) — they can't resolve a
    # toolchain anymore. Keep yazi/ya/tree-sitter (cargo-installed standalone
    # binaries) and the env shim sourced by .zshenv.
    for b in cargo cargo-clippy cargo-fmt cargo-miri clippy-driver rls \
             rust-analyzer rust-gdb rust-gdbgui rust-lldb rustc rustdoc \
             rustfmt rustup; do
        rm -f "$HOME/.cargo/bin/$b"
    done
    log "Cleanup done"
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
