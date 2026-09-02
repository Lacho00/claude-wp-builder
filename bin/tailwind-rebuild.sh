#!/usr/bin/env bash
# Recompile a Tailwind theme's assets/css/dist/main.css after an agent has written new
# utility classes into its templates. functions.php enqueues ONLY the compiled file, so
# without this the live site keeps serving the CSS built at /wp-init time — before any
# section existed — and /wp-yolo's parity gate diffs the demo against an unstyled page.
# Usage: bin/tailwind-rebuild.sh <theme-dir>
# Exit 0 and print nothing on a non-Tailwind theme (no package.json / no tailwindcss src).
# Skip the build when `npm run preview` / `tailwindwatch` is already running FOR THIS
# THEME: the watcher owns dist/ then and a second compiler racing it only produces a torn
# file. A watcher in another theme is irrelevant, so match on the process's cwd, not on
# the command line alone — the watch command carries relative paths.
set -euo pipefail

theme="${1:?usage: tailwind-rebuild.sh <theme-dir>}"

[ -f "$theme/package.json" ] && [ -d "$theme/assets/css/src/tailwindcss" ] || exit 0

theme_abs=$(cd "$theme" && pwd -P)

watcher_cwd() {
  # Linux first; lsof for macOS. Empty when neither can tell.
  readlink -f "/proc/$1/cwd" 2>/dev/null \
    || lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' \
    || true
}

for pid in $(pgrep -f 'tailwindcss.*--watch' 2>/dev/null || true); do
  if [ "$(watcher_cwd "$pid")" = "$theme_abs" ]; then
    echo "tailwind: watcher running for this theme (npm run preview) — dist/main.css is live, skipping build"
    exit 0
  fi
done
# ponytail: a watcher whose cwd we cannot read is treated as absent and we build anyway —
# a possible torn write the watcher immediately redoes beats silently never compiling.

if [ ! -d "$theme/node_modules" ]; then
  echo "tailwind: node_modules missing — running npm install once"
  (cd "$theme" && npm install --silent)
fi

# ponytail: tailwindbuild only, never the starter's `build` — that also runs wp-scripts
# and takes 10x longer; JS is untouched by the section/header/footer/page builders.
(cd "$theme" && npm run --silent tailwindbuild)
echo "tailwind: rebuilt assets/css/dist/main.css"
