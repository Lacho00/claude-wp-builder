#!/usr/bin/env bash
# The tailwind-native path must be discoverable from the docs: the two commands
# and the skill in the README, the behavior change in the CHANGELOG, and the
# manifest keyword that makes the plugin findable for "tailwind".
#
# Needle discipline: every needle below is a single unbreakable token, so a
# re-wrap of the surrounding prose cannot split it. Names are asserted at full
# length (or backtick-delimited) because a bare `wp-tailwind` is subsumed by
# `wp-tailwindify`, `wp-tailwind-system` and `wp-tailwind-migrate` alike.
set -euo pipefail

# ---- README: the commands, the skill, the agent -----------------------------
grep -Fq 'wp-tailwindify' README.md \
  || { echo "FAIL: README does not document /wp-tailwindify"; exit 1; }
grep -Fq 'wp-tailwind-migrate' README.md \
  || { echo "FAIL: README does not document /wp-tailwind-migrate"; exit 1; }
grep -Fq 'wp-tailwind-system' README.md \
  || { echo "FAIL: README does not list the wp-tailwind-system skill"; exit 1; }
# Backtick-delimited so `wp-tailwindify` / `wp-tailwind-system` cannot satisfy it.
grep -Fq '`wp-tailwind`' README.md \
  || { echo "FAIL: README does not list the wp-tailwind agent"; exit 1; }

# The wp-css-system README row must no longer claim to cover every theme.
# Accept any wording a careful author would actually use to scope it. A bare
# `basic` needle would false-fail on "plain-CSS path only" / "non-Tailwind
# themes", both of which are correct. If you scope the row with a word not
# listed here, EXTEND this alternation — do not leave the assertion failing on
# your own correct edit.
row=$(grep -F 'wp-css-system' README.md || true)
grep -Eqi 'basic|plain.css|non.tailwind|without tailwind' <<<"$row" \
  || { echo "FAIL: README wp-css-system row is not scoped to the basic/plain-CSS path"; exit 1; }

# ---- CHANGELOG: a NEW entry, above the last release -------------------------
# NOTE: a bare `grep -qi tailwind CHANGELOG.md` gates NOTHING — the file already
# carried tailwind mentions from 1.7.0 and earlier before this work started.
# Assert the new entry's own contents, inside its own line range.
new_head=$(grep -n -m1 '^## \[' CHANGELOG.md | cut -d: -f1 || true)
[ -n "$new_head" ] || { echo "FAIL: CHANGELOG has no version headings"; exit 1; }
grep -q '^## \[1\.7\.0\]' CHANGELOG.md \
  || { echo "FAIL: the 1.7.0 heading this check anchors on is gone; re-derive the range"; exit 1; }
old_head=$(grep -n -m1 '^## \[1\.7\.0\]' CHANGELOG.md | cut -d: -f1)
[ "$new_head" -lt "$old_head" ] \
  || { echo "FAIL: the tailwind entry is not above [1.7.0] — CHANGELOG is newest-first"; exit 1; }

# End the range at the SECOND heading, not at [1.7.0]. Everything between the two is
# already-released text, and `assets/css/styles.css` appears there — anchoring on 1.7.0
# let a bullet from an older release satisfy an assertion written about the newest one.
next_head=$(grep -n '^## \[' CHANGELOG.md | sed -n 2p | cut -d: -f1)
[ -n "$next_head" ] || { echo "FAIL: CHANGELOG has only one version heading; the range cannot be closed"; exit 1; }
entry=$(sed -n "${new_head},$((next_head - 1))p" CHANGELOG.md)
grep -Fq 'wp-tailwind-migrate' <<<"$entry" \
  || { echo "FAIL: the new CHANGELOG entry does not mention /wp-tailwind-migrate"; exit 1; }
grep -Fq 'wp-tailwind-system' <<<"$entry" \
  || { echo "FAIL: the new CHANGELOG entry does not mention the wp-tailwind-system skill"; exit 1; }
grep -Fq 'assets/css/styles.css' <<<"$entry" \
  || { echo "FAIL: the new CHANGELOG entry does not say what the defect actually was"; exit 1; }

# ---- Manifest: discoverable by keyword --------------------------------------
# Whitespace-stripped so the assertion survives any reformatting of the JSON,
# and quote-delimited so it matches the array element exactly (a hypothetical
# "tailwind-css" keyword would not satisfy it).
manifest=$(tr -d '[:space:]' < .claude-plugin/plugin.json)
case "$manifest" in
  *'"keywords":['*) ;;
  *) echo "FAIL: .claude-plugin/plugin.json has no keywords array"; exit 1;;
esac
keywords=${manifest#*'"keywords":['}
keywords=${keywords%%]*}
case "$keywords" in
  *'"tailwind"'*) ;;
  *) echo "FAIL: plugin.json keywords do not include \"tailwind\""; exit 1;;
esac

echo PASS
