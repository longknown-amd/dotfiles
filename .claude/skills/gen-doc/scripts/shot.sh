#!/usr/bin/env bash
# Screenshot an HTML page the way a reader first meets it: shot.sh <page.html|url> [out-prefix]
# Writes <prefix>-first.png (first screen, 1400x1300), <prefix>-full.png (1400x6000) and
# <prefix>-dark.png (first screen, dark theme). Look at all three with the Read tool.
set -euo pipefail
src=${1:?usage: shot.sh <page.html|url> [out-prefix]}
prefix=${2:-/tmp/gen-doc-shot}
case "$src" in http*|file:*) url=$src ;; *) url="file://$(realpath "$src")" ;; esac
chrome=$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)
[ -n "$chrome" ] || { echo "no chromium found" >&2; exit 2; }
run() { timeout 90 "$chrome" --headless --no-sandbox --disable-gpu --hide-scrollbars "$@" >/dev/null 2>&1; }
run --window-size=1400,1300 --screenshot="$prefix-first.png" "$url"
run --window-size=1400,6000 --screenshot="$prefix-full.png" "$url"
run --window-size=1400,1300 --force-dark-mode --blink-settings=preferredColorScheme=0 --screenshot="$prefix-dark.png" "$url"
ls -1 "$prefix"-*.png
