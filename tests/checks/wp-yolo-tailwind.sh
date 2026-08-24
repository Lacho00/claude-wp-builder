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
#
# Round 3. Four assertions in the round-2 file still gated nothing:
#   - the backup guard matched its own inversion ("only if ... already exists"),
#   - the --css assertion gated the phrase "the converted demo page" and so
#     survived re-pointing --css at the unconverted backup,
#   - the s26/s55 awk ranges had no closure proof, so renaming a heading
#     silently reopened them to EOF,
#   - and two ERE patterns matched the markdown arrow with a bare `.`, which
#     made the whole file FAIL under LC_ALL=C.
# Direction and literal paths from here on; grep -F wherever a fixed string will
# do, so the byte/character distinction cannot come back.
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
# If a terminator heading is ever renamed, awk's range runs to EOF and every
# "scoped" assertion below silently degrades back to a file-wide grep. That is
# not hypothetical: with s26 open to EOF, its assertions become satisfiable from
# Step 5.5, which also mentions the backup path and "item 3". Prove every range
# actually closed on the heading it claims to close on.
printf '%s\n' "$s26" | tail -1 | grep -q '^## Step 3:' \
  || fail "the Step 2.6 region is not terminated by a '## Step 3:' heading — the Step 2.6 assertions would silently become file-wide and be satisfiable from Step 5.5"
printf '%s\n' "$s4" | tail -1 | grep -q '^## Step 4\.5' \
  || fail "the Step 4 region is not terminated by a '## Step 4.5' heading — the section-walk assertions would silently become file-wide"
printf '%s\n' "$s55" | tail -1 | grep -q '^## Step 6:' \
  || fail "the Step 5.5 region is not terminated by a '## Step 6:' heading — the Step 5.5 assertions would silently become file-wide"

# Blockquote notes and list bullets wrap across lines, so a single sentence is
# not greppable line-by-line. Flatten each region to one line first.
# Strip only the leading blockquote marker (line-wise) — a global s/>//g would
# also eat the `>` in `demo/.original/<slug>.html` and in `<style>`.
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
#
# The backup lives in `demo/.original/`, NOT beside the page as
# `demo/<slug>.original.html`. `/wp-seed` (Step 5) maps every `demo/*.html` to a
# WP Page named after the file, so a sibling backup seeds a phantom page per
# demo page out of unconverted markup. A dot-prefixed subdirectory is outside
# `demo/*.html`, so it immunises every glob in the repo at once instead of
# needing an exclusion at each call site.
printf '%s' "$f26" | grep -qF 'demo/.original/<slug>.html' \
  || fail "Step 2.6 does not name the backup copy demo/.original/<slug>.html"
if printf '%s' "$f26" | grep -qF 'copy `demo/<slug>.html` to `demo/<slug>.original.html`'; then
  fail "Step 2.6 backs up to demo/<slug>.original.html — a sibling of demo/*.html, which /wp-seed turns into a phantom WP Page seeded from unconverted markup"
fi
printf '%s' "$f26" | grep -qF '/wp-tailwindify demo/<slug>.html --out demo/<slug>.html' \
  || fail "Step 2.6 does not convert in place — /wp-tailwindify's output path must be the demo page itself"

# The backup guard has to be asserted in its correct DIRECTION. The old pattern
# ('only if .{0,80}\.original\.html.{0,80}already exist') matched the inversion
# — "only if ... already exists" — just as happily, and under that inversion no
# backup is ever taken on the first run and the pristine original is overwritten
# with converted markup on every later one.
printf '%s' "$f26" | grep -qF 'only if `demo/.original/<slug>.html` does not already exist' \
  || fail 'Step 2.6 does not guard the backup with the literal "only if `demo/.original/<slug>.html` does not already exist"'
# Negative, general: every "already exist" in Step 2.6 must be negated. An
# un-negated one is the inverted guard.
if printf '%s' "$f26" | grep -oE '.{0,24}already exist' | grep -qv 'not already exist'; then
  fail "Step 2.6 has an un-negated \"already exist\" — the backup guard is inverted, so nothing is backed up on the first run and the pristine original is destroyed on every later one"
fi

# A truncated in-place write is otherwise unrecoverable: item 1's detect step
# reads the wreckage, finds no <style> block, calls the page already
# Tailwind-native and skips it forever. Verification must restore the backup
# over the demo page — in that direction, never the reverse.
printf '%s' "$f26" | grep -qF 'restore `demo/<slug>.html` from `demo/.original/<slug>.html`' \
  || fail "Step 2.6 does not restore the demo page from its backup when /wp-tailwindify's verification fails — a truncated page would be treated as already-converted forever"
if printf '%s' "$f26" | grep -qF 'restore `demo/.original/<slug>.html` from `demo/<slug>.html`'; then
  fail "Step 2.6's restore runs backwards — it overwrites the pristine backup with the failed conversion"
fi
printf '%s' "$f26" | grep -qiF 'report the page as unconverted' \
  || fail "Step 2.6 does not report a page whose conversion failed verification as unconverted"

# The re-point item must say downstream reads the CONVERTED markup, and must
# name the readers it covers — items 3 and 4 (header/footer) were missed once
# already because the old wording scoped re-pointing to items 5 and 6 only.
printf '%s' "$f26" | grep -qF 'every later reader picks up Tailwind-native markup' \
  || fail "Step 2.6 does not state that every later reader picks up the converted markup"
# item 2 is /wp-cpt: it reads demo/index.html via --from-demo and runs at Step 4
# item 2, i.e. after Step 2.6. It is a CSS-emitting reader like the rest.
for item in 'item 2' 'item 3' 'item 4' 'item 5' 'item 6'; do
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
#
# These assertions used grep -E with a bare `.` standing in for the markdown
# arrow. `.` is one character in a UTF-8 locale and one BYTE in C, where the
# 3-byte `→` never matched — so the whole check FAILed under LC_ALL=C, and a
# gate that fails spuriously in CI gets muted, silencing all 30-odd assertions
# in this file. Every pattern below is grep -F (byte-exact, locale-independent)
# or an ERE containing the literal arrow bytes.
printf '%s' "$f4" | grep -qF "\`basic\` → the section's verbatim demo \`cssRules\` from the manifest, which on this path is the source of truth" \
  || fail "Step 4 does not scope the manifest cssRules 'source of truth' claim to template=basic"

# The tailwind --css source must be asserted BY PATH at both section-walk sites.
# The old assertion gated the phrase "the converted demo page", which survived
# re-pointing the source at the unconverted backup and survived deleting the
# "never <backup>" clause outright — precisely the defect class this round
# exists to eliminate.
printf '%s' "$f4" | grep -qF '`tailwind` → the converted demo page itself, `demo/index.html`' \
  || fail "Step 4's home section walk does not point the tailwind --css source at the literal path demo/index.html"
printf '%s' "$f4" | grep -qF "on \`tailwind\`, this page's converted demo file \`demo/<slug>.html\`" \
  || fail "Step 4's inner-page section walk does not point the tailwind --css source at the literal path demo/<slug>.html"
printf '%s' "$f4" | grep -qF 'never the backup at `demo/.original/<slug>.html`' \
  || fail "Step 4 does not exclude the demo/.original/ backup as a --css source"
printf '%s' "$f4" | grep -qF 'stale on this path' \
  || fail "Step 4 does not state that the manifest cssRules are stale on the tailwind path"

# File-wide negative: nowhere in wp-yolo may a --css source resolve to the
# backup. Every legitimate mention of `demo/.original/` is a backup/restore
# operation inside Step 2.6 or an explicit prohibition, so the backup path must
# never sit where a source is being designated — directly after a `→`, or
# directly after the words "converted demo".
fall=$(flat "$(cat "$f")")
if printf '%s' "$fall" | grep -Eq '→ `?demo/\.original/|converted demo[^.]{0,30}`demo/\.original/|--css[^.]{0,60}`demo/\.original/'; then
  fail "a --css source line in $f resolves to demo/.original/ — the unconverted backup, which is exactly the re-point this check exists to catch"
fi

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
grep -qF 'demo/.original/<slug>.html' "$t" \
  || fail "$t still describes /wp-yolo Step 2.6's backup as a sibling of demo/*.html rather than demo/.original/<slug>.html"

# An in-place write that is interrupted destroys the demo page with no recovery
# path, and prose ("must not emit a partial file") is not a mechanism. Require
# temp-then-move, gated on the Step 4 verification.
ft=$(flat "$(cat "$t")")
printf '%s' "$ft" | grep -qF 'writes the converted HTML to a temporary path (`<output-path>.tmp`)' \
  || fail "$t does not require the agent to write to a temporary path (\`<output-path>.tmp\`) instead of the output path"
printf '%s' "$ft" | grep -qF "moves it over the output path **only after** Step 4's verification passes" \
  || fail "$t does not require the temporary file to be moved over the output path only after Step 4's verification passes"
printf '%s' "$ft" | grep -qF 'If verification fails, discard the temporary file and leave the output path exactly as it was' \
  || fail "$t does not discard the temporary file and leave the output path untouched when verification fails"
# Direction: moving first and verifying after is the truncating write itself.
if printf '%s' "$ft" | grep -Eq "moves it over the output path (\*\*)?(before|regardless of|and then|first)"; then
  fail "$t moves the temporary file into place before Step 4's verification — that is the destructive in-place write the temp path exists to prevent"
fi
printf '%s' "$ft" | grep -qF 'Only if 2 and 3 both hold, move the temporary file over the output path' \
  || fail "$t's Step 4 does not make the move conditional on both verification checks"

echo PASS
