#!/usr/bin/env bash
# /wp-section must route its CSS agent by template. On tailwind it dispatches
# wp-tailwind in author mode; on basic it keeps wp-css unchanged.
set -euo pipefail
f=commands/wp-section.md

grep -q 'wp-tailwind' "$f" \
  || { echo "FAIL: wp-section never mentions wp-tailwind"; exit 1; }
grep -Eqi 'template.{0,40}tailwind|tailwind.{0,40}template' "$f" \
  || { echo "FAIL: wp-section does not read the project template"; exit 1; }
grep -q 'author' "$f" \
  || { echo "FAIL: wp-section does not pass the author token to wp-tailwind"; exit 1; }
grep -q 'wp-tailwind-system' "$f" \
  || { echo "FAIL: wp-section does not point the agent at wp-tailwind-system"; exit 1; }

# The basic path must survive untouched.
grep -q 'assets/css/styles.css' "$f" \
  || { echo "FAIL: wp-section lost the basic path's styles.css target"; exit 1; }

# The transcription overlay needs its tailwind variant.
awk '/TRANSCRIPTION MODE OVERLAY/,/^---$/' "$f" | grep -q 'tailwind' \
  || { echo "FAIL: transcription overlay has no tailwind branch"; exit 1; }

# The CONTACT section's two-phase dispatch must route by template too — it must
# not hardcode wp-css as its Agent 3, and must point at the routing table instead.
contact_block=$(awk '/### For CONTACT sections: Two-Phase Dispatch/,/^Wait for all Phase 1 agents to complete/' "$f")
echo "$contact_block" | grep -q '^#### Agent 3: wp-css$' \
  && { echo "FAIL: CONTACT block still hardcodes wp-css as Agent 3"; exit 1; }
echo "$contact_block" | grep -qi 'CSS agent routing' \
  || { echo "FAIL: CONTACT block's Agent 3 does not point at the CSS agent routing table"; exit 1; }

echo PASS
