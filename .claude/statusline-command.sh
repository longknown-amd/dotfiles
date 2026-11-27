#!/bin/bash
# Status line derived from the PS1 defined in ~/.bashrc:
#   PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
#
# \u -> $(whoami), \h -> $(hostname -s), \w -> $(pwd)
# Trailing "\$" dropped per statusline conventions.

input=$(cat)

user=$(whoami)
host=$(hostname -s)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Fallback: compute from last usage tokens vs context window size
if [ -z "$used" ]; then
  used=$(echo "$input" | jq -r '
    (.context_window.current_usage // null) as $u
    | (.context_window.context_window_size // 1000000) as $s
    | if $u then (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) * 100 / $s else empty end')
fi

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' "$user" "$host" "$cwd"

branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
[ -n "$branch" ] && printf ' \033[01;33m(%s)\033[00m' "$branch"
[ -n "$model" ] && printf ' \033[01;36m[%s]\033[00m' "$model"
[ -n "$used" ] && printf ' \033[01;35mctx:%.0f%%\033[00m' "$used"
