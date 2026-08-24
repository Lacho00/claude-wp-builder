#!/usr/bin/env bash
# Every command that emits CSS must route by template, not hardcode wp-css.
set -euo pipefail
for f in commands/wp-page.md commands/wp-header.md commands/wp-footer.md; do
  grep -q 'wp-tailwind' "$f" \
    || { echo "FAIL: $f never mentions wp-tailwind"; exit 1; }
  grep -Eqi 'template.{0,40}tailwind|tailwind.{0,40}template' "$f" \
    || { echo "FAIL: $f does not read the project template"; exit 1; }
  grep -q 'wp-tailwind-system' "$f" \
    || { echo "FAIL: $f does not point the agent at wp-tailwind-system"; exit 1; }
done

# wp-page.md dispatches its CSS agent from a separate site per page type
# (blog, generic, legal, 404, search, embed, custom, ...). The file-level
# greps above are satisfied by a single routing block anywhere in the file,
# so they can't catch a secondary site that regresses to a bare, unrouted
# "Dispatch wp-css agent" line — the exact Task 5 failure mode, just with
# more branches. Walk every dispatch site instead of trusting a file-wide
# grep. This does not hardcode a site count: wp-page.md may grow more page
# types later and the loop below adapts to however many dispatch lines exist.
page=commands/wp-page.md

routing_line=$(grep -n '^### CSS agent routing$' "$page" | head -1 | cut -d: -f1)
[ -n "$routing_line" ] || { echo "FAIL: $page has no \"### CSS agent routing\" block"; exit 1; }

sites=$(grep -n '^Dispatch \*\*wp-css\*\* agent' "$page" || true)
[ -n "$sites" ] || { echo "FAIL: $page: found no wp-css dispatch sites — check pattern is stale"; exit 1; }

site_num=0
while IFS=: read -r lineno rest; do
  site_num=$((site_num + 1))

  [ "$lineno" -gt "$routing_line" ] \
    || { echo "FAIL: $page dispatch site #$site_num (line $lineno) appears before the CSS agent routing block (line $routing_line)"; exit 1; }

  if [ "$site_num" -eq 1 ]; then
    # The first dispatch site in the file sits directly under the routing
    # block with no other dispatch line before it — that adjacency IS its
    # coverage, so it is allowed to stay bare.
    continue
  fi

  # Every subsequent site is a second, independent branch the routing block
  # does not textually touch — it must carry its own inline marker naming
  # wp-tailwind, or a revert to a bare "Dispatch wp-css agent" line here
  # would silently fall back to the basic-only path.
  echo "$rest" | grep -qi 'wp-tailwind' \
    || { echo "FAIL: $page dispatch site #$site_num (line $lineno) has no inline tailwind routing marker: $rest"; exit 1; }
done <<< "$sites"

echo PASS
