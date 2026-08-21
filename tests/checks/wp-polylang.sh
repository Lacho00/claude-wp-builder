#!/usr/bin/env bash
set -euo pipefail
s=skills/wp-polylang/SKILL.md
test -f "$s" || { echo "FAIL: $s missing"; exit 1; }
head -1 "$s" | grep -q '^---$' || { echo "FAIL: no frontmatter"; exit 1; }
grep -q '^name: wp-polylang$' "$s" || { echo "FAIL: no name in frontmatter"; exit 1; }
grep -q '^description:' "$s" || { echo "FAIL: no description"; exit 1; }

# The API contract this whole feature rests on must be documented.
for token in pll_set_post_language pll_save_post_translations \
             pll_set_term_language pll_save_term_translations \
             pll_get_post_translations 'wp eval-file'; do
  grep -q "$token" "$s" || { echo "FAIL: SKILL.md missing '$token'"; exit 1; }
done

# The failure mode the skill exists to prevent must be named explicitly.
grep -qi 'post_translations' "$s" || { echo "FAIL: does not mention the post_translations taxonomy"; exit 1; }
grep -qi 'wp-bilingual' "$s" || { echo "FAIL: does not relate itself to wp-bilingual"; exit 1; }
echo PASS
