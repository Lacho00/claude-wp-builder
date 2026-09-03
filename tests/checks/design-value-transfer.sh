#!/usr/bin/env bash
# Three ways a design frame's numbers were transcribed correctly and still rendered wrong.
# All three cost real debugging on a build that was otherwise value-exact, and none of them
# is visible from the CSS: the declared value matches the frame, and the page is off anyway.
#
#   1. Frame y-coordinates are page coordinates in a page that has no site chrome. The theme
#      adds a breadcrumb the design never drew, and everything below it inherits the offset.
#   2. Section gaps are authored, not generated (53, 73, 103, 94, 107, 117, 147, 128, 73) —
#      a single spacing token is uniformly wrong, and splitting a gap across two paddings
#      renders their sum.
#   3. A px width in the frame is a fraction of that frame's track. Frozen as px in a
#      max-width query it holds the narrow-frame width up to the breakpoint and opens a gutter.
#
# The stale-stylesheet row in /wp-debug is guarded here too: the filemtime() rule already
# existed in wp-theme-standards, but that only reaches themes this plugin generated, and the
# symptom was diagnosed twice as something else before anyone read the enqueue.
set -euo pipefail

flat() { tr '\n' ' ' | sed -e 's/  */ /g'; }

f=agents/wp-css.md
[ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }
t=$(flat < "$f")

# 1. Chrome offset. Requires the RULE (positions are relative), not just the anecdote.
printf '%s' "$t" | grep -Eqi 'breadcrumb' \
  || { echo "FAIL: $f does not name the chrome that shifts a frame's y-coordinates — 'the theme adds things' is not something a reader can check for"; exit 1; }
printf '%s' "$t" | grep -Eqi 'distances between neighbours|distance between neighbours|never as page coordinates' \
  || { echo "FAIL: $f warns about chrome without giving the rule — vertical positions must be taken as distances between neighbours, not page coordinates"; exit 1; }

# 2. Irregular gaps. The gap list is the evidence; without numbers this reads as a style
# preference and a single spacing token survives it.
printf '%s' "$t" | grep -Eq '53, 73, 103' \
  || { echo "FAIL: $f asserts the section gaps are irregular without showing the measured list — the numbers are what rule out a single spacing token"; exit 1; }
printf '%s' "$t" | grep -Eqi 'padding-bottom: 0|padding-bottom:0' \
  || { echo "FAIL: $f does not say to give each gap to ONE side — split across two paddings the rendered gap is their sum"; exit 1; }

# 3. px that is really a proportion.
printf '%s' "$t" | grep -Eq '93\.33%|proportion of its track|fraction of the content track' \
  || { echo "FAIL: $f does not cover a frame px width being a proportion of its track — frozen as px it holds the narrow-frame width to the breakpoint"; exit 1; }

# The /wp-debug row for a stale stylesheet.
d=commands/wp-debug.md
[ -f "$d" ] || { echo "FAIL: $d missing"; exit 1; }
td=$(flat < "$d")
printf '%s' "$td" | grep -q 'filemtime' \
  || { echo "FAIL: $d has no row for a stylesheet edit that does not show up — a static version constant keeps the URL stable while the file changes, and filemtime() is the fix"; exit 1; }
printf '%s' "$td" | grep -Eqi '\?ver=' \
  || { echo "FAIL: $d does not name the ?ver= query string as the tell — it is the one thing that distinguishes this from every other caching explanation"; exit 1; }

echo PASS
