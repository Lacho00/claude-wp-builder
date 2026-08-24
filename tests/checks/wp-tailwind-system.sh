#!/usr/bin/env bash
# The wp-tailwind-system skill must carry the full decision ladder and the
# prohibition list, so agents cannot fall back to the BEM/custom-property path.
set -euo pipefail
f=skills/wp-tailwind-system/SKILL.md

[ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }

# The four rungs of the decision ladder.
for rung in 'utility classes in the markup' '2 pages' 'utilities/site\.css' 'components/<slug>\.css' '@keyframes'; do
  grep -Eq "$rung" "$f" || { echo "FAIL: skill missing decision-ladder element '$rung'"; exit 1; }
done

# Prohibitions.
for banned in 'assets/css/styles\.css' 'BEM' ':root' 'new director'; do
  grep -Eq "$banned" "$f" || { echo "FAIL: skill missing prohibition on '$banned'"; exit 1; }
done

# Token source must be @theme, not :root custom properties.
grep -q '@theme' "$f" || { echo "FAIL: skill does not point tokens at the @theme block"; exit 1; }

# The no-empty-file rule.
grep -Eqi 'at least one rule|never create an empty' "$f" \
  || { echo "FAIL: skill missing the no-empty-file rule"; exit 1; }

echo PASS
