#!/usr/bin/env bash
# /wp-init must make the demo conversion part of the flow, and /wp-finalize must
# validate the tailwind convention before delivery.
set -euo pipefail

# Command files wrap at ~90 columns, and any ordinary edit re-flows the paragraph
# around it. Every prose match below therefore runs against a newline-flattened
# copy; a line-anchored `grep -F` would false-fail on the next re-wrap.
flatten() { tr '\n' ' ' | sed 's/  */ /g'; }

init=$(flatten < commands/wp-init.md)
fin=$(flatten < commands/wp-finalize.md)

# The old wording must be gone. A positive alone is not enough: both sentences can
# coexist, leaving the operator told to suggest AND to run.
if printf '%s' "$init" | grep -Fq 'Also suggest running `/wp-tailwindify`'; then
  echo "FAIL: wp-init still tells the operator to merely suggest /wp-tailwindify"; exit 1
fi
printf '%s' "$init" | grep -Fq 'run `/wp-tailwindify`' \
  || { echo "FAIL: wp-init does not tell the operator to RUN /wp-tailwindify"; exit 1; }

printf '%s' "$fin" | grep -Fq 'bin/tailwind-native-check.sh' \
  || { echo "FAIL: wp-finalize does not run the tailwind-native check"; exit 1; }

# The gate must be scoped to the tailwind template — an unconditional run would fail
# every basic project on a missing main.css.
printf '%s' "$fin" | grep -Fq 'Skip when `Template:` is `basic`' \
  || { echo "FAIL: wp-finalize's tailwind check is not gated on the template"; exit 1; }

# Step 4b: Layer 3 must compare the converted demo against the pristine original,
# because on the tailwind path the demo URL now serves the converted page and a
# conversion error appears on BOTH sides of the old comparison.
# Anchor on the ASCII substring, not on the heading's em-dash — a bare `.` does not
# match a multibyte char under LC_ALL=C.
l3=$(awk '/Layer 3 \(measured visual parity/{f=1;next} f&&/^## Step 4:/{exit} f' commands/wp-finalize.md | flatten)
[ -n "$l3" ] || { echo "FAIL: no Layer 3 section in wp-finalize.md"; exit 1; }
grep -q '^## Step 4:' commands/wp-finalize.md \
  || { echo "FAIL: the Layer 3 region is not terminated by a '## Step 4:' heading — its assertions would silently run to EOF"; exit 1; }
printf '%s' "$l3" | grep -Fq 'demo/.original/' \
  || { echo "FAIL: Layer 3 never reads demo/.original/ — on the tailwind path it compares the converted demo against a build made from that same converted demo, so a conversion defect cancels out"; exit 1; }
printf '%s' "$l3" | grep -Fq 'conversion defect' \
  || { echo "FAIL: Layer 3 does not distinguish a conversion defect from a build defect"; exit 1; }

echo PASS
