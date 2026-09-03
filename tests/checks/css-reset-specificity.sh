#!/usr/bin/env bash
# A reset kept as a SCOPED rule outranks the classes it was meant to serve, and the
# failure is silent: `.page img { height:auto }` is (0,2,1) and beats
# `.page-step__icon { height:… }` at (0,2,0), so the image ignores its own class and
# paints at its intrinsic size while the class sits in the stylesheet looking right.
# getComputedStyle reports the reset's value and the class is visible in DevTools, so
# it reads as "my CSS is not loading". It cost a full debugging detour once, on images
# exported at 3x that therefore painted at triple their design size.
#
# Both CSS skills must carry the rule and the escape hatch, because both paths can
# write a page-scoped reset: wp-css-system on the plain-CSS path, wp-tailwind-system
# wherever a bare selector is KEPT rather than distributed.
set -euo pipefail

flat() { tr '\n' ' ' | sed -e 's/  */ /g'; }

for f in skills/wp-css-system/SKILL.md skills/wp-tailwind-system/SKILL.md; do
  [ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }
  t=$(flat < "$f")

  # The escape hatch itself. Naming :where() is the whole remedy; without it the
  # section can describe the problem and leave the reader with no way out.
  grep -q ':where(' <<<"$t" \
    || { echo "FAIL: $f never mentions :where() — a page-scoped reset has no zero-specificity form without it"; exit 1; }

  # WHY it works. ":where() is (0,0,0)" is the load-bearing fact; a bare mention of
  # the function invites someone to wrap the override instead of the reset.
  grep -Eq '0,0,0|zero.specificity|no weight|contributes nothing' <<<"$t" \
    || { echo "FAIL: $f mentions :where() without saying it carries no specificity — the reader cannot tell which side to wrap"; exit 1; }

  # The comparison that makes the bug findable. A section that says "watch your
  # specificity" and never contrasts the two scores does not let anyone recognise it.
  grep -Eq '\(0,2,1\)' <<<"$t" \
    || { echo "FAIL: $f does not score the scoped reset (0,2,1) — the point is that the element selector outranks a class, and only the numbers show it"; exit 1; }
  grep -Eq '\(0,2,0\)' <<<"$t" \
    || { echo "FAIL: $f does not score the losing class (0,2,0) — without both numbers the comparison is an assertion"; exit 1; }
done

echo PASS
