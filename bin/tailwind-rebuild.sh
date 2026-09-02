#!/usr/bin/env bash
# Recompile a Tailwind theme's assets/css/dist/main.css after an agent has written new
# utility classes into its templates. functions.php enqueues ONLY the compiled file, so
# without this the live site keeps serving the CSS built at /wp-init time — before any
# section existed — and /wp-yolo's parity gate diffs the demo against an unstyled page.
# Usage: bin/tailwind-rebuild.sh <theme-dir>
# Exit 0 and print nothing on a non-Tailwind theme (no package.json / no tailwindcss src).
#
# Two writers must never touch dist/main.css at once, or it is served torn:
#  - another builder for the SAME theme    → serialized by flock below
#  - the user's `npm run preview` watcher  → detected, and we skip rather than fight it
set -euo pipefail

theme="${1:?usage: tailwind-rebuild.sh <theme-dir>}"

[ -f "$theme/package.json" ] && [ -d "$theme/assets/css/src/tailwindcss" ] || exit 0

theme_abs=$(cd "$theme" && pwd -P)
out_abs="$theme_abs/assets/css/dist/main.css"

proc_cwd() {
  # Linux first; lsof for macOS. Empty when neither can tell.
  readlink -f "/proc/$1/cwd" 2>/dev/null \
    || lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' \
    || true
}

# The watcher's own -o argument is the ground truth for which theme it compiles: cwd alone
# misses `npm --prefix wp-content/themes/acme run preview`, whose cwd is the parent. Read
# the command line, resolve its -o relative to that cwd, and compare output files.
# One argument per line. /proc is exact; `ps` is the macOS fallback and splits on
# spaces, so a theme path containing one is not matched there — it falls through to
# the cwd comparison below, which is where macOS stood before.
proc_argv() {
  tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null && return 0
  ps -ww -o command= -p "$1" 2>/dev/null | tr ' ' '\n'
}

watcher_output() {
  local pid=$1 cwd out
  cwd=$(proc_cwd "$pid") || return 1
  [ -n "$cwd" ] || return 1
  out=$(proc_argv "$pid" \
        | awk '$0 == "-o" || $0 == "--output" { getline; print; exit }') || return 1
  [ -n "$out" ] || return 1
  case "$out" in
    /*) printf '%s\n' "$out" ;;
    *)  printf '%s\n' "$cwd/$out" ;;
  esac
}

for pid in $(pgrep -f 'tailwindcss.*--watch' 2>/dev/null || true); do
  # Either signal is enough: an output path that resolves to ours, or a cwd that is ours
  # (the fallback when /proc is unreadable, e.g. macOS, where cmdline is not available).
  w_out=$(watcher_output "$pid" || true)
  if [ -n "$w_out" ] && [ "$(readlink -f "$w_out" 2>/dev/null || echo "$w_out")" = "$out_abs" ]; then
    echo "tailwind: watcher running for this theme (npm run preview) — dist/main.css is live, skipping build"
    exit 0
  fi
  if [ -z "$w_out" ] && [ "$(proc_cwd "$pid")" = "$theme_abs" ]; then
    echo "tailwind: watcher running for this theme (npm run preview) — dist/main.css is live, skipping build"
    exit 0
  fi
done
# ponytail: a watcher we cannot identify at all is treated as absent and we build anyway —
# a possible torn write the watcher immediately redoes beats silently never compiling.

build() {
  if [ ! -d "$theme/node_modules" ]; then
    echo "tailwind: node_modules missing — running npm install once"
    (cd "$theme" && npm install --silent)
  fi
  # ponytail: tailwindbuild only, never the starter's `build` — that also runs wp-scripts
  # and takes 10x longer; JS is untouched by the section/header/footer/page builders.
  (cd "$theme" && npm run --silent tailwindbuild)
  echo "tailwind: rebuilt assets/css/dist/main.css"
}

# /wp-yolo dispatches section builders in parallel, so two can land here at once for the
# same theme: concurrent `npm install` corrupts node_modules and concurrent compiles tear
# dist/main.css. One lock per theme, in the theme, so separate projects never block.
# The lock file is never deleted. Unlinking it after the flock is released hands a
# late arrival a fresh inode while an earlier waiter still holds the old one, and the
# two then build at once — the exact collision the lock exists to stop. It lives in
# the temp dir, keyed by the theme's absolute path, so nothing is left inside the
# theme for the user to commit.
lock="${TMPDIR:-/tmp}/tailwind-rebuild-$(printf '%s' "$theme_abs" | cksum | tr -d ' ').lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock"
  flock 9
  build
  exec 9>&-
else
  # ponytail: no flock (macOS ships none) — build unlocked rather than not at all.
  build
fi
