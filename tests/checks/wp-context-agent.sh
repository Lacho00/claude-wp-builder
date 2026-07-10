#!/usr/bin/env bash
set -euo pipefail
f=agents/wp-context.md
test -f "$f" || { echo "FAIL: $f missing"; exit 1; }
grep -q '^name: wp-context$' "$f" || { echo "FAIL: name frontmatter"; exit 1; }
grep -q '^tools:' "$f" || { echo "FAIL: tools frontmatter"; exit 1; }
for token in 'pdftotext' 'libreoffice' 'convert-to csv' '.scope-manifest.json' 'wp-context:start' 'delivery' 'idx' 'integrations' 'review'; do
  grep -q "$token" "$f" || { echo "FAIL: missing '$token'"; exit 1; }
done
echo PASS
