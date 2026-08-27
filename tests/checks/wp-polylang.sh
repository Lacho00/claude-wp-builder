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

c=commands/wp-polylang.md
test -f "$c" || { echo "FAIL: $c missing"; exit 1; }
head -1 "$c" | grep -q '^---$' || { echo "FAIL: command has no frontmatter"; exit 1; }
grep -q 'allowed-tools:' "$c" || { echo "FAIL: no allowed-tools"; exit 1; }
grep -q 'argument-hint:' "$c" || { echo "FAIL: no argument-hint"; exit 1; }
for token in pll-setup.php pll-export.php pll-import.php pll-verify.php \
             'wp eval-file' wp-polylang; do
  grep -q "$token" "$c" || { echo "FAIL: command doc missing '$token'"; exit 1; }
done
grep -q 'wp plugin install polylang' "$c" || { echo "FAIL: command doc does not install Polylang"; exit 1; }

# ── Polylang i18n variants ──────────────────────────────────────────────────
# The contract test. Templates call these helpers and never get_field()
# directly, so a Polylang project works only as long as its i18n-polylang.php
# exposes EXACTLY what its own i18n.php does -- one missing helper is a fatal
# error on a real page, and one extra is a helper no template can rely on.
#
# Asserted PER STARTER, not across them: __tailwind__ and __cinematic__ have
# deliberately different contracts (nine helpers vs three), so a single global
# list would be wrong for both.
for starter in __tailwind__ __cinematic__; do
  base="starter-theme/$starter/inc/i18n.php"
  poly="starter-theme/_i18n-variants/$starter.php"

  [[ -f "$base" ]] || { echo "FAIL: $starter has no inc/i18n.php to mirror"; exit 1; }
  [[ -f "$poly" ]] || { echo "FAIL: no Polylang i18n variant for $starter"; exit 1; }

  php -l "$poly" >/dev/null 2>&1 || { echo "FAIL: the $starter Polylang variant is not valid PHP"; exit 1; }

  # The variant must NOT be shipped inside the theme tree: /wp-init copies the
  # whole starter directory, so a second file declaring the same functions
  # would ride along into every project and fatal the moment anything globs
  # inc/*.php. tests/checks/tailwind-starter.sh refuses that state outright.
  [[ ! -f "starter-theme/$starter/inc/i18n-polylang.php" ]] || {
    echo "FAIL: $starter ships a Polylang variant inside its own inc/ -- it must live in starter-theme/_i18n-variants/"
    exit 1
  }

  base_fns="$(grep -oP '^function \K[a-z_0-9]+' "$base" | sort)"
  poly_fns="$(grep -oP '^function \K[a-z_0-9]+' "$poly" | sort)"

  [[ -n "$base_fns" ]] || { echo "FAIL: no functions found in $starter/inc/i18n.php -- this check would be vacuous"; exit 1; }

  if [[ "$base_fns" != "$poly_fns" ]]; then
    echo "FAIL: $starter's Polylang variant does not expose the same helpers as its i18n.php"
    echo "  only in i18n.php:          $(comm -23 <(echo "$base_fns") <(echo "$poly_fns") | tr '\n' ' ')"
    echo "  only in the Polylang variant: $(comm -13 <(echo "$base_fns") <(echo "$poly_fns") | tr '\n' ' ')"
    exit 1
  fi

  # The variant must actually consult Polylang, not just be a copy of the
  # _suffix file under a different name.
  grep -q 'pll_current_language' "$poly" || {
    echo "FAIL: the $starter Polylang variant never calls pll_current_language() -- it is not a Polylang variant"
    exit 1
  }
  # And it must degrade instead of fataling when Polylang is inactive.
  grep -q "function_exists( *'pll_current_language' *)" "$poly" || {
    echo "FAIL: the $starter Polylang variant calls Polylang without guarding for it being inactive"
    exit 1
  }
done

# /wp-init must offer the choice, and record it.
grep -q '_i18n-variants' "commands/wp-init.md" || { echo "FAIL: /wp-init never installs a Polylang i18n variant"; exit 1; }
grep -qi 'polylang' "commands/wp-init.md" || { echo "FAIL: /wp-init does not mention Polylang at all"; exit 1; }

# The two i18n models must not be described as mutually exclusive any more.
grep -q 'no WPML, no Polylang' "skills/wp-bilingual/SKILL.md" && {
  echo "FAIL: wp-bilingual still claims the plugin does not support Polylang"
  exit 1
}

echo PASS
