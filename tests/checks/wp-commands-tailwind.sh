#!/usr/bin/env bash
# Every command that emits CSS must route by template, not hardcode wp-css.
set -euo pipefail
for f in commands/wp-page.md commands/wp-header.md commands/wp-footer.md; do
  grep -q 'wp-tailwind' "$f" \
    || { echo "FAIL: $f never mentions wp-tailwind"; exit 1; }
  grep -Eqi 'template.{0,40}tailwind|tailwind.{0,40}template' "$f" \
    || { echo "FAIL: $f does not read the project template"; exit 1; }
  grep -q 'wp-tailwind-system' "$f" \
    || { echo "FAIL: $f does not point the agent at wp-tailwind-system"; exit 1; }
done
echo PASS
