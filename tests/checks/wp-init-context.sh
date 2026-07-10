#!/usr/bin/env bash
set -euo pipefail
f=commands/wp-init.md
grep -q 'wp-context' "$f" || { echo "FAIL: wp-init does not reference wp-context"; exit 1; }
grep -Eq 'docs/? (folder|directory|exists)|if .*docs' "$f" || { echo "FAIL: no docs/ existence condition"; exit 1; }
echo PASS
