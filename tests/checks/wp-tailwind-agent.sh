#!/usr/bin/env bash
# wp-tailwind must do double duty: demo conversion AND section authoring
# (the wp-css replacement on the tailwind path).
set -euo pipefail
f=agents/wp-tailwind.md

# Sentences wrap across lines, and a line-anchored grep silently loses an
# assertion the moment someone re-wraps a paragraph. Flatten once and match
# against that.
flatf=$(tr '\n' ' ' < "$f" | sed 's/  */ /g')

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
grep -q 'Create a file you do not fill' "$f" \
  || { echo "FAIL: wp-tailwind missing the no-empty-file rule"; exit 1; }

# Conversion mode writes a TEMPORARY path and stops. `/wp-tailwindify` Step 3
# hands the agent `<output-path>.tmp` and keeps the verification and the move
# for itself (Step 4 runs after the agent returns, so the agent could not
# condition the move on it even if it wanted to). This file used to say "Write
# the converted HTML to the output path provided", which contradicted that and
# reinstated the destructive in-place write.
printf '%s' "$flatf" | grep -qF 'Write the converted HTML to `<output-path>.tmp`' \
  || { echo "FAIL: wp-tailwind does not write the conversion to \`<output-path>.tmp\`"; exit 1; }
printf '%s' "$flatf" | grep -qF 'never to `<output-path>` itself' \
  || { echo "FAIL: wp-tailwind does not forbid writing \`<output-path>\` itself"; exit 1; }
printf '%s' "$flatf" | grep -qF 'Then stop: you do not move, rename or delete `<output-path>`, and you do not verify your own conversion' \
  || { echo "FAIL: wp-tailwind does not stop after the temporary write — the verification and the move belong to /wp-tailwindify Step 4"; exit 1; }
printf '%s' "$flatf" | grep -qF 'Write the converted HTML to the output path provided' \
  && { echo "FAIL: wp-tailwind writes straight to the output path — that is the truncating in-place write the .tmp contract exists to prevent"; exit 1; }

# Mode gate must exist to prevent conversion-mode readers from missing authoring mode.
grep -q 'If it contains the literal token .author.' "$f" \
  || { echo "FAIL: wp-tailwind missing the mode-selection gate"; exit 1; }

echo PASS
