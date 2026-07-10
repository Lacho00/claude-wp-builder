#!/usr/bin/env bash
set -euo pipefail
f=commands/wp-yolo.md
for token in '.scope-manifest.json' 'delivery' 'wp-page embed' 'out of scope' 'reconcile'; do
  grep -q "$token" "$f" || { echo "FAIL: missing '$token'"; exit 1; }
done
grep -Eq 'no demo HTML|no HTML|needs demo' "$f" || { echo "FAIL: no approved-but-missing-HTML handling"; exit 1; }
echo PASS
