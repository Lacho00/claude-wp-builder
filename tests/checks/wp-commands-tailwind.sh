#!/usr/bin/env bash
# Every command that emits CSS must route by template, not hardcode wp-css.
set -euo pipefail
for f in commands/wp-page.md commands/wp-header.md commands/wp-footer.md commands/wp-cpt.md; do
  grep -q 'wp-tailwind' "$f" \
    || { echo "FAIL: $f never mentions wp-tailwind"; exit 1; }
  grep -Eqi 'template.{0,40}tailwind|tailwind.{0,40}template' "$f" \
    || { echo "FAIL: $f does not read the project template"; exit 1; }
  grep -q 'wp-tailwind-system' "$f" \
    || { echo "FAIL: $f does not point the agent at wp-tailwind-system"; exit 1; }
done

# wp-page.md dispatches its CSS agent from a separate site per page type
# (blog, generic, legal, 404, search, embed, custom, ...). wp-cpt.md does the
# same from two sites (the archive/single/card CSS, and the teaser section that
# gets injected into front-page.php). The file-level greps above are satisfied
# by a single routing block anywhere in the file, so they can't catch a
# secondary site that regresses to a bare, unrouted "Dispatch wp-css agent"
# line — the exact Task 5 failure mode, just with more branches. Walk every
# dispatch site instead of trusting a file-wide grep.
#
# Both files get the same treatment, and for the same reason: a file-wide grep
# cannot tell a routed site from an unrouted one. wp-cpt.md has fewer sites than
# wp-page.md, but "fewer" is not "one" — its teaser site is the one that writes
# into front-page.php, so an unrouted regression there leaks plain CSS into the
# home page on the tailwind path. Neither loop hardcodes a site count: both
# files may grow more dispatch sites later and the walk adapts.
#
# The site pattern matches any dispatch line naming **wp-css**, not just lines
# that begin "Dispatch **wp-css** agent" — wp-cpt.md's teaser site dispatches
# three agents from one line ("Dispatch **wp-template** + **wp-acf** +
# **wp-css**"), and a pattern anchored on wp-css coming first would skip it.
walk_sites() {
  local page=$1 routing_line sites site_num lineno rest

  routing_line=$(grep -n -m1 '^### CSS agent routing$' "$page" | cut -d: -f1 || true)
  [ -n "$routing_line" ] || { echo "FAIL: $page has no \"### CSS agent routing\" block"; exit 1; }

  sites=$(grep -nE '^[[:space:]>*-]*Dispatch .*\*\*wp-css\*\*' "$page" || true)
  [ -n "$sites" ] || { echo "FAIL: $page: found no wp-css dispatch sites — check pattern is stale"; exit 1; }

  site_num=0
  while IFS=: read -r lineno rest; do
    site_num=$((site_num + 1))

    [ "$lineno" -gt "$routing_line" ] \
      || { echo "FAIL: $page dispatch site #$site_num (line $lineno) appears before the CSS agent routing block (line $routing_line)"; exit 1; }

    # Every site is an independent branch the routing block does not textually
    # touch — it must carry its own inline marker naming wp-tailwind, or a
    # revert to a bare "Dispatch wp-css agent" line here would silently fall
    # back to the basic-only path.
    echo "$rest" | grep -qi 'wp-tailwind' \
      || { echo "FAIL: $page dispatch site #$site_num (line $lineno) has no inline tailwind routing marker: $rest"; exit 1; }

    # Direction, not adjacency: the marker must hand wp-tailwind to `tailwind`.
    # A marker reading "on `basic`, dispatch `wp-tailwind`" names both tokens
    # and would satisfy the grep above while routing the wrong way round.
    echo "$rest" | grep -qF 'on `tailwind`, dispatch `wp-tailwind` in author mode instead' \
      || { echo "FAIL: $page dispatch site #$site_num (line $lineno) does not route \`tailwind\` (and only \`tailwind\`) to wp-tailwind: $rest"; exit 1; }
  done <<< "$sites"
}

walk_sites commands/wp-page.md
walk_sites commands/wp-cpt.md

echo PASS
