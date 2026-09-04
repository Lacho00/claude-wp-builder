#!/usr/bin/env bash
# A demo's `position: absolute; left: Npx` is the mockup's coordinate, not a layout: the box is
# out of flow, so the first longer ACF value or the second language puts it on top of its
# neighbour. The rule that layout is flex/grid — and that `absolute` is earned only by a real
# superposition — must survive in every file that emits or converts layout CSS.
set -euo pipefail
fail=0

need() { # file, pattern, what
  grep -qE "$2" "$1" || { echo "FAIL: $1 lost $3"; fail=1; }
}

# The two design-system skills own the rule in full (plain CSS and Tailwind paths).
need skills/wp-css-system/SKILL.md      'Layout is flex or grid'            'the flex/grid layout rule'
need skills/wp-css-system/SKILL.md      'superposition'                     'the superposition exception'
need skills/wp-tailwind-system/SKILL.md '`absolute` is for superposition'   'the flex/grid layout rule'

# The agent that actually writes section CSS must carry it too — it is dispatched with the
# skill unread often enough that a pointer alone is not the contract.
need agents/wp-css.md 'superposition, not for layout' 'the flex/grid layout section'
need agents/wp-css.md 'Layout is flex or grid'        'the flex/grid rule in its Rules list'

# The test itself is what makes the rule applicable, not a taste statement. Keep it phrased.
for f in skills/wp-css-system/SKILL.md skills/wp-tailwind-system/SKILL.md agents/wp-css.md; do
  need "$f" 'does this survive if the content changes' 'the survives-a-content-change test'
done

[ "$fail" = 0 ] || exit 1
echo PASS
