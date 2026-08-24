#!/usr/bin/env bash
# /wp-yolo reads Template: in step 1 but historically dropped it. It must now
# convert the demo and thread the template into every downstream dispatch.
set -euo pipefail
f=commands/wp-yolo.md

grep -q 'wp-tailwindify' "$f" \
  || { echo "FAIL: wp-yolo does not run /wp-tailwindify on the tailwind path"; exit 1; }
grep -q 'index-tailwind.html' "$f" \
  || { echo "FAIL: wp-yolo does not use the converted demo as the section-walk source"; exit 1; }
# Anchored on the heading itself: the loose 'Step 2.6' pattern survived deleting
# the whole block, because the two routing notes below reference it by name.
grep -q '^## Step 2\.6' "$f" \
  || { echo "FAIL: wp-yolo has no top-level Step 2.6 demo-conversion phase"; exit 1; }
# \b so this is not satisfied by the string "wp-tailwindify" alone.
grep -q 'wp-tailwind\b' "$f" \
  || { echo "FAIL: wp-yolo never routes to the wp-tailwind agent"; exit 1; }

# The routing note must land on BOTH section-walk sites (home + inner pages),
# not once at the top of the file.
n=$(grep -c 'Template routing' "$f" || true)
if [ "$n" -lt 2 ]; then
  echo "FAIL: found $n 'Template routing' note(s) in wp-yolo.md, expected 2 (home sections + inner pages)"; exit 1
fi

# The already-tailwind demo must be detected, not converted twice. Matched on the
# report string itself — the earlier 'already tailwind|no <style>|skip' alternation
# hit the bare word "skip" 12 times in the pre-existing steps and so gated nothing.
grep -q 'conversion skipped' "$f" \
  || { echo "FAIL: wp-yolo has no skip path for an already-converted demo"; exit 1; }

echo PASS
