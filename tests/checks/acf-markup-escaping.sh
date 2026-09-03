#!/usr/bin/env bash
# A section headline is a `text` field that carries two tags on purpose: a <span> the CSS
# paints as a highlight pill, and <br> where the design breaks the line. Both of the usual
# escaping answers are wrong for it — esc_html() prints the tags and destroys the design,
# wp_kses_post() admits <iframe>, <img>, inline style and a class on any tag, so a headline
# field becomes a way to restyle the page. The third answer, wp_kses() with a two-tag
# allowlist, was missing from both files that decide how a value gets printed.
#
# The allowlist is also the enforcement for a rule found the hard way: a CSS class inside
# field content is not a thing that exists. Which break applies at which width is
# presentation and belongs in the stylesheet, addressed by position.
set -euo pipefail

flat() { tr '\n' ' ' | sed -e 's/  */ /g'; }

for f in skills/wp-theme-standards/SKILL.md agents/wp-template.md; do
  [ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }
  t=$(flat < "$f")

  # The third escaping answer must exist, and must be the ALLOWLIST form. A bare
  # `wp_kses` token is satisfied by `wp_kses_post`, which is the function this rule
  # exists to steer away from — so require the two tags it allows.
  printf '%s' "$t" | grep -Eq "wp_kses\(" \
    || { echo "FAIL: $f offers no wp_kses() with an explicit allowlist — a headline that carries <br> and <span> has no correct escaper without it"; exit 1; }
  printf '%s' "$t" | grep -Eq "'br' *=> *array\(\)|'br' *=> *\[\]" \
    || { echo "FAIL: $f shows wp_kses() without naming the allowed tags — an allowlist nobody can copy is prose"; exit 1; }
  printf '%s' "$t" | grep -Eq "'span' *=> *array\(\)|'span' *=> *\[\]" \
    || { echo "FAIL: $f allowlists <br> but not <span> — the highlight pill is half the reason this field carries markup"; exit 1; }

  # Why not the easy one. Without this the reader picks wp_kses_post() and never learns
  # it hands a headline field the run of the page.
  printf '%s' "$t" | grep -q 'wp_kses_post' \
    || { echo "FAIL: $f never contrasts against wp_kses_post() — the reader has no reason not to use it here"; exit 1; }
  # Name the tags it admits, not the adjective. The first draft of this gate accepted
  # `inline .?style` case-insensitively and was satisfied by an unrelated "Inline Styles"
  # heading elsewhere in the same file — a gate that passes on prose it was not written
  # for is worse than no gate. `iframe` and `class on any tag` appear nowhere else.
  printf '%s' "$t" | grep -Eqi 'iframe|class on any tag' \
    || { echo "FAIL: $f does not say what wp_kses_post() lets through — 'too permissive' is not actionable, and the reader needs the tags to weigh the blast radius"; exit 1; }

  # the_field()/the_sub_field() echo unescaped. Both files must forbid them by name;
  # "escape everything" has already coexisted with templates full of the_field().
  printf '%s' "$t" | grep -q 'the_field(' \
    || { echo "FAIL: $f never names the_field() — it echoes unescaped and reads as the natural template call, which is how raw output ships"; exit 1; }
done

# The presentation half, stated once where the escaping contract lives.
t=$(flat < skills/wp-theme-standards/SKILL.md)
printf '%s' "$t" | grep -q 'nth-of-type' \
  || { echo "FAIL: wp-theme-standards does not show choosing the break by POSITION — without it the only way to vary a break per width is a class in the field, which the allowlist forbids"; exit 1; }
printf '%s' "$t" | grep -Eqi 'whitespace|word gap|wordnext' \
  || { echo "FAIL: wp-theme-standards omits the display:none whitespace trap — hiding a <br> glues the words on either side of it"; exit 1; }

echo PASS
