#!/usr/bin/env bash
set -euo pipefail
f=agents/wp-normalize.md
test -f "$f" || { echo "FAIL: $f missing"; exit 1; }
grep -q '^name: wp-normalize$' "$f" || { echo "FAIL: name frontmatter"; exit 1; }
grep -q '^tools:' "$f" || { echo "FAIL: tools frontmatter"; exit 1; }
for token in 'SECTION:' '.yolo-manifest.json' 'confidence' 'has_archive' 'View all|Show more|See all' 'static-repeater|repeater' 'contentTypes'; do
  grep -Eq "$token" "$f" || { echo "FAIL: missing '$token'"; exit 1; }
done
echo PASS
