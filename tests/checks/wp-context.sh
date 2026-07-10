#!/usr/bin/env bash
set -euo pipefail
f=commands/wp-context.md
test -f "$f" || { echo "FAIL: $f missing"; exit 1; }
grep -q 'allowed-tools:' "$f" || { echo "FAIL: frontmatter"; exit 1; }
grep -q 'argument-hint:' "$f" || { echo "FAIL: argument-hint"; exit 1; }
for token in 'wp-context' '.scope-manifest.json' 'wp-context:start' 'Project Constraints' 'docs' '.claude/CLAUDE.md'; do
  grep -q "$token" "$f" || { echo "FAIL: missing '$token'"; exit 1; }
done
test -f agents/wp-context.md || { echo "FAIL: agent missing"; exit 1; }
echo PASS
