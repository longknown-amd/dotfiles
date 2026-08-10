#!/bin/bash
# Status line derived from the PS1 defined in ~/.bashrc:
#   PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
#
# \u -> $(whoami), \h -> $(hostname -s), \w -> $(pwd)
# Trailing "\$" dropped per statusline conventions.

user=$(whoami)
host=$(hostname -s)
cwd=$(pwd)

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' "$user" "$host" "$cwd"
