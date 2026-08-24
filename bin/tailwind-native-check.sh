#!/usr/bin/env bash
# Validates a Tailwind theme against the tailwind-native CSS convention.
# Usage: bin/tailwind-native-check.sh <theme-dir>
# Safe to run against the starter (uncompiled) or a built theme; the
# markup rule only applies once assets/css/dist/main.css exists.
set -euo pipefail

theme="${1:?usage: tailwind-native-check.sh <theme-dir>}"
src="$theme/assets/css/src/tailwindcss"
main="$src/main.css"
fail=0

err() { echo "FAIL: $1"; fail=1; }

[ -f "$main" ] || { echo "FAIL: $main not found"; exit 1; }

# Every rule below uses `if`, never `[ … ] && err …` — under `set -e` a false
# test as the last command of a line aborts the script instead of continuing.

# 1. No plain-CSS output file from the basic path.
if [ -f "$theme/assets/css/styles.css" ]; then
  err "assets/css/styles.css exists — that is the template=basic output surface"
fi

# 2. Only the four sanctioned directories.
for d in "$src"/*/; do
  case "$(basename "$d")" in
    base|components|layouts|utilities) ;;
    *) err "unexpected directory $(basename "$d") under $src" ;;
  esac
done

# 3. Every .css file has at least one rule, and 4. is imported by main.css.
# Process substitution, not a pipe — a pipe would run the loop in a subshell
# and every `fail=1` would be lost.
while IFS= read -r f; do
  rel="${f#"$src"/}"
  # Drop single-line comments and blank lines; anything left is a rule.
  body=$(sed -e 's|/\*.*\*/||g' -e '/^[[:space:]]*$/d' "$f" | tr -d '[:space:]')
  if [ -z "$body" ]; then
    err "$rel is empty or comment-only"
  fi
  grep -Fq "$rel" "$main" || err "$rel has no @import in main.css"
done < <(find "$src" -mindepth 2 -name '*.css')

# 5. No inline <style> blocks in templates.
if grep -rlq '<style' "$theme" --include='*.php' 2>/dev/null; then
  err "inline <style> block(s) in: $(grep -rl '<style' "$theme" --include='*.php' | tr '\n' ' ')"
fi

# 6. A compiled theme must actually use utilities in its markup.
if [ -f "$theme/assets/css/dist/main.css" ]; then
  hits=$(grep -rlE 'class="[^"]*(flex|grid|px-|py-|text-|bg-|gap-)' "$theme" --include='*.php' 2>/dev/null | wc -l)
  if [ "$hits" -lt 3 ]; then
    err "only $hits template(s) carry Tailwind utility classes — build produced no utilities"
  fi
fi

[ "$fail" -eq 0 ] || exit 1
echo PASS
