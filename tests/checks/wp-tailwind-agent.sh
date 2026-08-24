#!/usr/bin/env bash
# wp-tailwind must do double duty: demo conversion AND section authoring
# (the wp-css replacement on the tailwind path).
set -euo pipefail
f=agents/wp-tailwind.md

grep -q 'Section Authoring Mode' "$f" \
  || { echo "FAIL: wp-tailwind has no Section Authoring Mode"; exit 1; }

# It must defer to the convention skill rather than restating a rival ladder.
grep -q 'wp-tailwind-system' "$f" \
  || { echo "FAIL: wp-tailwind does not reference the wp-tailwind-system skill"; exit 1; }

# Cross-page promotion: a group seen on a second page moves to utilities/site.css.
grep -q 'utilities/site.css' "$f" \
  || { echo "FAIL: wp-tailwind never mentions utilities/site.css"; exit 1; }
grep -Eqi 'grep|search' "$f" \
  || { echo "FAIL: wp-tailwind has no cross-page detection step"; exit 1; }

# Hard prohibitions.
grep -q 'assets/css/styles.css' "$f" \
  || { echo "FAIL: wp-tailwind missing the styles.css prohibition"; exit 1; }
grep -Eqi 'never create.*(empty|file it does not fill)|at least one rule' "$f" \
  || { echo "FAIL: wp-tailwind missing the no-empty-file rule"; exit 1; }

echo PASS
