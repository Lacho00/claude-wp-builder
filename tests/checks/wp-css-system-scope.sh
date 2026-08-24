#!/usr/bin/env bash
# wp-css-system must declare itself basic-only. Its unconditional "no
# frameworks" rule previously banned Tailwind even on the tailwind path.
set -euo pipefail
f=skills/wp-css-system/SKILL.md

grep -Eq 'template=basic|`basic`' "$f" \
  || { echo "FAIL: wp-css-system does not scope itself to template=basic"; exit 1; }
grep -q 'wp-tailwind-system' "$f" \
  || { echo "FAIL: wp-css-system does not redirect tailwind projects to wp-tailwind-system"; exit 1; }

# The framework prohibition must be scoped, not absolute.
line=$(grep -n 'No frameworks' "$f" | head -1 | cut -d: -f1)
[ -n "$line" ] || { echo "FAIL: 'No frameworks' rule not found"; exit 1; }
sed -n "${line}p" "$f" | grep -Eq 'basic|this template' \
  || { echo "FAIL: the 'No frameworks' rule is still unconditional"; exit 1; }

echo PASS
