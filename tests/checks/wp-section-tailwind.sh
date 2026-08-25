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

# ---------------------------------------------------------------------------
# The per-template definition of `--css` in Step 1 is the canonical statement of
# this contract — `commands/wp-yolo.md` Step 4 and its check both defer to it
# ("per the transcription overlay below"). It was ungated: swapping the two
# bullets, so `basic` got the converted Tailwind demo and `tailwind` got the
# verbatim CSS "SOURCE OF TRUTH", left 0 of 26 checks failing. That swap is a
# straight inversion of the contract this branch exists to establish, so bind
# each template to its own source by name and reject the other direction.
#
# grep -F throughout: the bullets contain a literal `→` (3 bytes in UTF-8) and a
# bare `.` in an ERE does not match it under LC_ALL=C.
# ---------------------------------------------------------------------------
grep -qF -- "- \`basic\` → the section's **verbatim** demo CSS, and the SOURCE OF TRUTH for the transcription" "$f" \
  || { echo "FAIL: wp-section does not bind --css on \`basic\` to the section's verbatim demo CSS as the transcription's SOURCE OF TRUTH"; exit 1; }
grep -qF -- '- `tailwind` → the converted demo page itself (HTML, converted in place by `/wp-yolo` Step 2.6)' "$f" \
  || { echo "FAIL: wp-section does not bind --css on \`tailwind\` to the converted demo page itself"; exit 1; }
grep -qF 'not** a source of verbatim declarations' "$f" \
  || { echo "FAIL: wp-section does not say the tailwind --css source is a geometry reference rather than a source of verbatim declarations"; exit 1; }
# Inversions.
grep -qF '`basic` → the converted demo page' "$f" \
  && { echo "FAIL: wp-section hands the converted Tailwind demo to template=basic — the contract is inverted"; exit 1; }
grep -qF "\`tailwind\` → the section's **verbatim** demo CSS" "$f" \
  && { echo "FAIL: wp-section hands the verbatim plain-CSS demo blob to template=tailwind as the SOURCE OF TRUTH — the contract is inverted"; exit 1; }

# The CONTACT section's two-phase dispatch must route by template too — it must
# not hardcode wp-css as its Agent 3, and must point at the routing table instead.
contact_block=$(awk '/### For CONTACT sections: Two-Phase Dispatch/,/^Wait for all Phase 1 agents to complete/' "$f")
echo "$contact_block" | grep -q '^#### Agent 3: wp-css$' \
  && { echo "FAIL: CONTACT block still hardcodes wp-css as Agent 3"; exit 1; }
echo "$contact_block" | grep -qi 'CSS agent routing' \
  || { echo "FAIL: CONTACT block's Agent 3 does not point at the CSS agent routing table"; exit 1; }

echo PASS
