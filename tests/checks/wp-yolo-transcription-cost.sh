#!/usr/bin/env bash
# Three costs a real full-site build paid for nothing.
#
# 1. wp-normalize captured verbatim `cssRules` for every section on the tailwind
#    path — a full read of every stylesheet and a full write of every rule — to
#    produce a field /wp-yolo Step 4 then forbids the section walk from reading.
# 2. Step 2.6 converted every copy of a repeated card. A directory page drawing
#    16 cards from 4 records, and a board page drawing 18 from 3, were the two
#    most expensive conversions in the run; in the theme all N collapse into one
#    template part inside a loop, so the extra conversions were discarded work.
# 3. wp-acf and wp-template each ship a "WP-CLI Integration" section telling the
#    agent to run `$WP ...`, while their frontmatter granted no Bash. Both agents
#    reported verification they could not run, and the orchestrator re-ran it.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "FAIL: $1"; exit 1; }

# --- 3. an agent told to run a shell must have one ------------------------
for a in wp-acf wp-template; do
  f=agents/$a.md
  grep -q '^tools:.*\bBash\b' "$f" || fail "$a is told to run WP-CLI but its frontmatter grants no Bash"
done
# ...and an agent that is NOT told to run one must not gain it by copy-paste.
for a in wp-css wp-tailwind wp-normalize; do
  f=agents/$a.md
  if grep -q '^tools:.*\bBash\b' "$f"; then
    grep -Eq '\$WP |wp --path|php -l' "$f" || fail "$a grants Bash but never needs a shell"
  fi
done

# --- 1. no CSS capture on the tailwind path -------------------------------
n=agents/wp-normalize.md
cap=$(awk '/^## Fidelity capture/,/^### Extended per-section schema/' "$n")
[ -n "$cap" ] || fail "no Fidelity capture region in wp-normalize"
grep -Fq 'Skip this capture entirely when the project' <<<"$cap" \
  || fail "wp-normalize still captures cssRules unconditionally"
grep -Fq '"cssRules": null' <<<"$cap" \
  || fail "wp-normalize does not say what to write instead of the skipped CSS"
grep -Fq 'fonts' <<<"$cap" \
  || fail "wp-normalize does not keep capturing fonts on both paths"
grep -Fq 'cannot be recovered from converted' <<<"$cap" \
  || fail "wp-normalize does not say why fonts survive the skip (conversion strips @font-face)"
grep -Fq '"cssRules": "<string>|null"' "$n" \
  || fail "the per-section schema still types cssRules as always-present"

# --- 2. a repeated card is transcribed once -------------------------------
grep -Fq '**Repeated cards collapse to one exemplar.**' <<<"$cap" \
  || fail "wp-normalize does not record repeated-card runs"
for k in '"selector"' '"count"' '"distinct"' '"exemplar"' '"variants"'; do
  grep -Fq "$k" "$n" || fail "the repetition block has no $k"
done
grep -Fq 'most' <<<"$cap" \
  || fail "wp-normalize does not say which sibling to pick as the exemplar"
grep -Fq 'Omit `repetition` when a list' <<<"$cap" \
  || fail "wp-normalize never says when NOT to collapse a list"
grep -Fq '"repetition": {' "$n" \
  || fail "the per-section schema does not carry the repetition block"

y=commands/wp-yolo.md
s26=$(awk '/^## Step 2\.6:/,/^## Step 3:/' "$y")
[ -n "$s26" ] || fail "no Step 2.6 region in wp-yolo"
grep -Fq 'Convert a repeated card once, not once per copy.' <<<"$s26" \
  || fail "Step 2.6 still converts every copy of a repeated card"
grep -Fq 'position-for-position' <<<"$s26" \
  || fail "Step 2.6 does not say how the exemplar's classes reach its siblings"
for a in href src alt 'data-*'; do
  grep -Fq "$a" <<<"$s26" || fail "Step 2.6 does not protect each sibling's own $a"
done
grep -Fq 'variant' <<<"$s26" \
  || fail "Step 2.6 has no escape hatch for a sibling that is really a variant"

echo PASS
