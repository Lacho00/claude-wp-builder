#!/usr/bin/env bash
# /wp-yolo reads Template: in step 1 but historically dropped it. It must now
# convert the demo IN PLACE (with a backup) in Step 2.6 and route every
# downstream dispatch by template.
#
# Round 2 rewrite. The previous version of this file still printed PASS under
# four mutations that invert its meaning:
#   1. re-pointing downstream back at the ORIGINAL, unconverted demo,
#   2. flipping the skip gate to "skip when template == tailwind",
#   3. flipping the routing notes so `basic` gets the Tailwind agent,
#   4. moving both routing notes out of Step 4 to the top of the file.
# The cause was the same each time: assertions that only proved a *word* was
# present somewhere in the file, never that a *claim* pointed the right way in
# the right place. Every assertion below is anchored on the direction of the
# claim and scoped to the region that has to carry it.
set -euo pipefail
f=commands/wp-yolo.md
t=commands/wp-tailwindify.md

fail() { echo "FAIL: $1"; exit 1; }

test -f "$f" || fail "$f missing"
test -f "$t" || fail "$t missing"

# ---------------------------------------------------------------------------
# Regions. A file-wide grep is what let mutation 4 pass: the routing notes
# belong to the two section-walk sites inside Step 4, and Step 4 ends at
# "## Step 4.5: Font carry" — not at end of file, or the scoping is fiction.
# ---------------------------------------------------------------------------
s26=$(awk '/^## Step 2\.6/,/^## Step 3:/' "$f")
s4=$(awk '/^## Step 4:/,/^## Step 4\.5/' "$f")
s55=$(awk '/^## Step 5\.5/,/^## Step 6:/' "$f")
[ -n "$s26" ] || fail "wp-yolo has no top-level Step 2.6 demo-conversion phase"
[ -n "$s4" ]  || fail "wp-yolo has no Step 4 build region delimited by Step 4.5"
[ -n "$s55" ] || fail "wp-yolo has no Step 5.5 demo-parity-gate region"
# If the terminator heading is ever renamed, awk's range runs to EOF and every
# "scoped" assertion below silently degrades back to a file-wide grep. Prove the
# range actually closed.
printf '%s\n' "$s4" | tail -1 | grep -q '^## Step 4\.5' \
  || fail "the Step 4 region is not terminated by a '## Step 4.5' heading — the section-walk assertions would silently become file-wide"

# Blockquote notes and list bullets wrap across lines, so a single sentence is
# not greppable line-by-line. Flatten each region to one line first.
# Strip only the leading blockquote marker (line-wise) — a global s/>//g would
# also eat the `>` in `demo/<slug>.original.html` and in `<style>`.
flat() { printf '%s' "$1" | sed 's/^[[:space:]]*>[[:space:]]\?//' | tr '\n' ' ' | sed 's/  */ /g'; }
f26=$(flat "$s26")
f4=$(flat "$s4")
f55=$(flat "$s55")

# ---------------------------------------------------------------------------
# Step 2.6 — the conversion phase itself
# ---------------------------------------------------------------------------

# The gate must skip on `basic`, i.e. RUN on `tailwind`. Asserting the literal
# condition, not "some skip-ish word appears": the old `grep -q skip` was
# satisfied by the inverted gate and by 12 unrelated uses of the word.
printf '%s' "$f26" | grep -qF 'Skip this step entirely when `template == basic`' \
  || fail 'Step 2.6 does not gate on "Skip this step entirely when `template == basic`" — tailwind is the path that must convert'
if printf '%s' "$f26" | grep -qF 'Skip this step entirely when `template == tailwind`'; then
  fail "Step 2.6 skips itself on the tailwind path — that is the only path that needs conversion"
fi

printf '%s' "$f26" | grep -qF '/wp-tailwindify' \
  || fail "Step 2.6 does not run /wp-tailwindify on the tailwind path"

# Multi-page demos are wp-yolo's premise (item 6 walks every inner page), so
# the conversion cannot be a single hardcoded home-page run.
printf '%s' "$f26" | grep -qF '**every** page in the manifest' \
  || fail "Step 2.6 does not loop the conversion over every page in the manifest"

# In-place conversion contract: a backup under a fixed name, and an output path
# that is the demo page itself. Without the second half, nothing downstream
# reads the converted markup — the Task 7 defect.
printf '%s' "$f26" | grep -qF 'demo/<slug>.original.html' \
  || fail "Step 2.6 does not name the backup copy demo/<slug>.original.html"
printf '%s' "$f26" | grep -qF '/wp-tailwindify demo/<slug>.html --out demo/<slug>.html' \
  || fail "Step 2.6 does not convert in place — /wp-tailwindify's output path must be the demo page itself"
printf '%s' "$f26" | grep -Eq 'only if .{0,80}\.original\.html.{0,80}already exist' \
  || fail "Step 2.6 does not guard the backup against being overwritten on a re-run"

# The re-point item must say downstream reads the CONVERTED markup, and must
# name the readers it covers — items 3 and 4 (header/footer) were missed once
# already because the old wording scoped re-pointing to items 5 and 6 only.
printf '%s' "$f26" | grep -qF 'every later reader picks up Tailwind-native markup' \
  || fail "Step 2.6 does not state that every later reader picks up the converted markup"
for item in 'item 3' 'item 4' 'item 5' 'item 6'; do
  printf '%s' "$f26" | grep -qF "$item" \
    || fail "Step 2.6's re-point item does not account for $item as a reader of the converted demo"
done
printf '%s' "$f26" | grep -Eq 'never[[:space:]]*a build source' \
  || fail "Step 2.6 does not state that the .original.html backup is never a build source"
if printf '%s' "$f26" | grep -Eqi 'read[s]?( from)?[^.]{0,40}(original|unconverted|plain-CSS) demo'; then
  fail "Step 2.6 claims a later reader still reads the original/unconverted demo"
fi

# The already-tailwind demo must be detected, not converted twice. Matched on
# the report string itself — an 'already tailwind|no <style>|skip' alternation
# hit the bare word "skip" 12 times in unrelated steps and so gated nothing.
printf '%s' "$f26" | grep -qF 'conversion skipped' \
  || fail "Step 2.6 has no skip path for an already-converted demo"

# ---------------------------------------------------------------------------
# Step 4 — the two section-walk dispatch sites
# ---------------------------------------------------------------------------

# Backticks, because a bare \b is satisfied by "wp-tailwind-system" (the `-`
# is a word boundary) and would survive deleting every agent reference.
grep -qF '`wp-tailwind`' "$f" \
  || fail "wp-yolo never names the wp-tailwind agent"

# The routing note must land on BOTH section-walk sites (home + inner pages),
# and must land INSIDE Step 4 — hoisting both notes to the top of the file used
# to satisfy the old file-wide count.
n=$(printf '%s\n' "$s4" | grep -c 'Template routing' || true)
[ "$n" -ge 2 ] || fail "found $n 'Template routing' note(s) inside Step 4, expected 2 (home sections + inner pages)"

# Direction, not adjacency: the sentence that hands `tailwind` (never `basic`)
# to the wp-tailwind agent must appear at both sites.
d=$(printf '%s' "$f4" | grep -oF 'is `tailwind`, `/wp-section` dispatches `wp-tailwind` in author mode instead of `wp-css`' | wc -l || true)
[ "$d" -ge 2 ] || fail "found $d correctly-directed routing sentence(s) in Step 4, expected 2 — tailwind must be the value that gets the wp-tailwind agent"
if printf '%s' "$f4" | grep -qF 'is `basic`, `/wp-section` dispatches `wp-tailwind`'; then
  fail "a Step 4 routing note hands the Tailwind agent to template=basic"
fi

# /wp-section takes no template argument — it reads Template: itself
# (commands/wp-section.md, "CSS agent routing"). The old wording told the
# orchestrator to "pass the project's Template: value", which invents a flag
# that does nothing.
p=$(printf '%s' "$f4" | grep -oF 'reads `Template:` from `.claude/CLAUDE.md` itself' | wc -l || true)
[ "$p" -ge 2 ] || fail "found $p note(s) saying /wp-section reads Template: itself, expected 2"
if printf '%s' "$f4" | grep -qiF "Pass the project's \`Template:\` value"; then
  fail "a Step 4 routing note still tells the caller to pass a Template: value /wp-section does not accept"
fi

# --css source is template-dependent: the manifest cssRules were captured from
# the plain-CSS original in Step 2, so they are stale on the tailwind path.
printf '%s' "$f4" | grep -Eq '`basic` . .{0,140}source of truth' \
  || fail "Step 4 does not scope the manifest cssRules 'source of truth' claim to template=basic"
printf '%s' "$f4" | grep -Eq '`tailwind` . the converted demo page' \
  || fail "Step 4 does not point the tailwind --css source at the converted demo page"
printf '%s' "$f4" | grep -qF 'stale on this path' \
  || fail "Step 4 does not state that the manifest cssRules are stale on the tailwind path"

# ---------------------------------------------------------------------------
# Step 5.5 — the parity-gate auto-fix must not re-inject plain CSS
# ---------------------------------------------------------------------------
printf '%s' "$f55" | grep -qF 'skills/wp-tailwind-system/SKILL.md' \
  || fail "Step 5.5's auto-fix has no tailwind branch citing the wp-tailwind-system decision ladder"
printf '%s' "$f55" | grep -qF 'Step 2.6-converted' \
  || fail "Step 5.5's tailwind repair does not read from the Step 2.6-converted demo"
printf '%s' "$f55" | grep -qiF 'never write a raw css declaration into a theme css file on the tailwind path' \
  || fail "Step 5.5 does not forbid writing a raw CSS declaration into theme CSS on the tailwind path"

# ---------------------------------------------------------------------------
# /wp-tailwindify must accept the output path Step 2.6 passes it
# ---------------------------------------------------------------------------
grep -qF -- '--out <output-path>' "$t" \
  || fail "$t does not document an --out <output-path> argument"
grep -qF -- 'argument-hint: "[path/to/demo.html] [--out <output-path>]"' "$t" \
  || fail "$t's argument-hint does not advertise --out"
grep -qF 'index-tailwind.html' "$t" \
  || fail "$t lost its default output path (<demo-dir>/index-tailwind.html) — standalone use must be unchanged"
grep -qiF 'in-place' "$t" \
  || fail "$t does not document that --out may name the input file (in-place conversion)"

echo PASS
