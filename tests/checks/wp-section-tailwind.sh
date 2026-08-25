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
#
# ...but grep -F on the FILE was line-anchored, and these two bullets are the
# longest lines in the repo (183 and 299 characters, in a file that otherwise
# wraps at ~90). Re-wrapping either of them at any sane column without changing a
# single word exited 1, and so did a re-word that preserved the direction exactly
# ("demo CSS — the SOURCE OF TRUTH" for "demo CSS, and the SOURCE OF TRUTH").
# That is a gate that fails on the obvious next correct edit, which is how gates
# get muted. Flatten the file to one line first — the same remedy
# tests/checks/wp-tailwind-agent.sh already uses — and match the bullet's opening
# clause rather than the whole sentence.
# ---------------------------------------------------------------------------
flatf=$(tr '\n' ' ' < "$f" | sed 's/  */ /g')

# The `basic` bullet, from its own marker to the `tailwind` marker that follows
# it. Scoping the SOURCE OF TRUTH claim to this span is what keeps it directed:
# the claim has to sit in the `basic` bullet, and swapping the two bullets moves
# it out of the span (as well as tripping the inversions below).
basic_css=$(printf '%s' "$flatf" | awk -v a='- `basic` → ' -v b='- `tailwind` → ' '
  {
    i = index($0, a)
    if (i == 0) exit 1
    s = substr($0, i)
    j = index(substr(s, length(a) + 1), b)
    print (j > 0) ? substr(s, 1, length(a) + j - 1) : s
  }') \
  || { echo "FAIL: wp-section's --css definition has no \`basic\` bullet"; exit 1; }

printf '%s' "$basic_css" | grep -qF -- "the section's **verbatim** demo CSS" \
  || { echo "FAIL: wp-section does not bind --css on \`basic\` to the section's **verbatim** demo CSS"; exit 1; }
printf '%s' "$basic_css" | grep -qF -- 'SOURCE OF TRUTH' \
  || { echo "FAIL: wp-section's \`basic\` --css bullet does not call the verbatim demo CSS the transcription's SOURCE OF TRUTH"; exit 1; }
printf '%s' "$flatf" | grep -qF -- '- `tailwind` → the converted demo page itself' \
  || { echo "FAIL: wp-section does not bind --css on \`tailwind\` to the converted demo page itself"; exit 1; }
printf '%s' "$flatf" | grep -qF 'not** a source of verbatim declarations' \
  || { echo "FAIL: wp-section does not say the tailwind --css source is a geometry reference rather than a source of verbatim declarations"; exit 1; }
# Inversions, matched file-wide (on the flattened text) so an inverted duplicate
# added anywhere in the file is caught, not just the first bullet pair.
if printf '%s' "$flatf" | grep -qF '`basic` → the converted demo page'; then
  echo "FAIL: wp-section hands the converted Tailwind demo to template=basic — the contract is inverted"; exit 1
fi
if printf '%s' "$flatf" | grep -qF -- "\`tailwind\` → the section's **verbatim** demo CSS"; then
  echo "FAIL: wp-section hands the verbatim plain-CSS demo blob to template=tailwind as the SOURCE OF TRUTH — the contract is inverted"; exit 1
fi

# The CONTACT section's two-phase dispatch must route by template too — it must
# not hardcode wp-css as its Agent 3, and must point at the routing table instead.
contact_block=$(awk '/### For CONTACT sections: Two-Phase Dispatch/,/^Wait for all Phase 1 agents to complete/' "$f")
echo "$contact_block" | grep -q '^#### Agent 3: wp-css$' \
  && { echo "FAIL: CONTACT block still hardcodes wp-css as Agent 3"; exit 1; }
echo "$contact_block" | grep -qi 'CSS agent routing' \
  || { echo "FAIL: CONTACT block's Agent 3 does not point at the CSS agent routing table"; exit 1; }

echo PASS
