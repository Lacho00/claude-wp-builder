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
# The wording is "the verification that gates the move is not yours to run", not
# "you do not verify your own conversion". The latter contradicted this file's
# own Quality Checks section, which tells the agent to verify delimiters and
# `<style>` blocks before writing — a direct contradiction inside the file the
# actor split was about. A self-check before the `.tmp` write is fine and wanted;
# what the agent must not own is the GATE.
printf '%s' "$flatf" | grep -qF 'Then stop: you do not move, rename or delete `<output-path>`, and the verification that gates the move is not yours to run' \
  || { echo "FAIL: wp-tailwind does not stop after the temporary write — the move, and the verification that gates it, belong to /wp-tailwindify Step 4"; exit 1; }
printf '%s' "$flatf" | grep -qF 'that is a self-check, not the gate' \
  || { echo "FAIL: wp-tailwind does not separate its own Quality Checks self-check from /wp-tailwindify Step 4's gate — without that, Step 5 and the Quality Checks section contradict each other"; exit 1; }
printf '%s' "$flatf" | grep -qF 'Write the converted HTML to the output path provided' \
  && { echo "FAIL: wp-tailwind writes straight to the output path — that is the truncating in-place write the .tmp contract exists to prevent"; exit 1; }

# Mode gate must exist to prevent conversion-mode readers from missing authoring mode.
grep -q 'If it contains the literal token .author.' "$f" \
  || { echo "FAIL: wp-tailwind missing the mode-selection gate"; exit 1; }

echo PASS
