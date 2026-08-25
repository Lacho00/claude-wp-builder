#!/usr/bin/env bash
# Behaviour tests for the wp-polylang scripts against a real WordPress install.
# Skips (exit 0) when PLL_TEST_SITE is unset so the repo's checks stay green.
set -euo pipefail

SITE="${PLL_TEST_SITE:-}"
if [[ -z "$SITE" ]]; then
  echo "SKIP: set PLL_TEST_SITE to a WordPress root with Polylang active"
  exit 0
fi
[[ -d "$SITE" ]] || { echo "FAIL: PLL_TEST_SITE '$SITE' is not a directory"; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/skills/wp-polylang/scripts"
SRC="${PLL_TEST_SRC:-es}"
DST="${PLL_TEST_DST:-en}"
# The third language exists only so the "adding a language does not orphan the
# existing group" regression can be exercised. It is CREATED and DELETED by
# this suite, so the code below refuses to touch it unless this run is the one
# that created it (see the pre-existence probe further down). The default is a
# locale no real site is plausibly authored in -- that is insurance, not the
# safety mechanism; the pre-existence gate is.
THIRD="${PLL_TEST_THIRD:-szl}"
[[ "$THIRD" != "$SRC" && "$THIRD" != "$DST" ]] || { echo "FAIL: PLL_TEST_THIRD ('$THIRD') must differ from the source and target languages"; exit 1; }

run() { (cd "$SITE" && wp eval-file "$@" --allow-root); }

echo "── setup ──"
out="$(run "$SCRIPTS/pll-setup.php" "$SRC" "$DST")" || { echo "FAIL: setup exited non-zero"; echo "$out"; exit 1; }
grep -q "Polylang ready" <<<"$out" || { echo "FAIL: setup did not report ready"; echo "$out"; exit 1; }

echo "── setup is idempotent ──"
out2="$(run "$SCRIPTS/pll-setup.php" "$SRC" "$DST")" || { echo "FAIL: second setup exited non-zero"; exit 1; }
grep -q "Polylang ready" <<<"$out2" || { echo "FAIL: second setup did not report ready"; exit 1; }

echo "── setup rejects an unknown language ──"
if run "$SCRIPTS/pll-setup.php" "$SRC" "zz-not-a-language" >/dev/null 2>&1; then
  echo "FAIL: setup accepted a bogus language code"; exit 1
fi

echo "── seed this run's fixture content ──"
# Everything this suite needs in order to assert anything is CREATED here, not
# discovered on the site:
#
#   * two untranslated source-language pages, parent + child. The suite used to
#     hunt for an untranslated page that already existed, which made it pass
#     once and then fail on its own output -- the run before it had translated
#     every page on the site. A suite that fails on its own output reads as a
#     regression in the code under test, which is worse than one that never
#     passed.
#   * an untranslated attachment, so the "manifest contains an attachment"
#     regression guard (the 'inherit' post_status check) has something to find
#     on every run and not only on a virgin site.
#   * two items in the SOURCE-language menu: a top-level one pointing at the
#     parent page and a CHILD one (--parent-id) pointing at the child page.
#     This site's real menu is 4 "custom" and 8 "taxonomy" items -- zero
#     "post_type" items and zero nesting that survives import -- so without
#     these both the item re-pointing and the MENU parent fixup would have
#     nothing to check. (The pre-existing parent/child fixture only ever
#     exercised the post_parent fixup, a different mechanism in a different
#     part of the importer.)
#   * a post_type_archive menu item, the one remaining item type with no
#     coverage.
#
# All of it is removed again by cleanup(), trapped on EXIT immediately after
# the first object exists. This file has a dozen explicit `exit 1` sites and
# the teardown used to sit past all of them, so any failure left the fixture
# page and its menu item in the site's real menu, and every retry added
# another.
FIXTURE_PARENT_ID=""
FIXTURE_CHILD_ID=""
FIXTURE_MEDIA_ID=""
FIXTURE_ITEM_IDS=""
FIXTURE_MENU_ID=""
FIXTURE_ARCHIVE_PT=""
# Set ONLY once this run has itself created the third language. While it is
# empty, cleanup() does not go near that language -- see the probe below.
FIXTURE_THIRD_LANG=""
# Set only while a real post on the site has had its language stripped by the
# verify test below. cleanup() restores it; see the comment there.
VERIFY_VICTIM=""
VERIFY_VICTIM_LANG=""

# Every temp file this suite writes lives here, so a failure at any of the
# dozen `exit 1` sites cannot leak a manifest into /tmp. mktemp -d rather than
# `mktemp --suffix=.png`: --suffix is a GNU extension and is not available on
# BSD/macOS, where the fixture used to die before creating anything.
FIXTURE_TMPDIR="$(mktemp -d)"
FIXTURE_MEDIA_FILE="$FIXTURE_TMPDIR/pll-fixture.png"

cleanup() {
  local status=$?
  rm -rf "$FIXTURE_TMPDIR"
  # Nothing was created yet -- do not run a site mutation just to delete zero
  # objects. This matters because the trap is armed before the first fixture
  # object exists, on purpose, so the temp dir above is always removed.
  if [[ -z "$FIXTURE_PARENT_ID$FIXTURE_CHILD_ID$FIXTURE_MEDIA_ID$FIXTURE_ITEM_IDS$FIXTURE_ARCHIVE_PT$FIXTURE_THIRD_LANG$VERIFY_VICTIM" ]]; then
    return $status
  fi
  (cd "$SITE" \
    && PLL_FIX_POSTS="$FIXTURE_PARENT_ID,$FIXTURE_CHILD_ID,$FIXTURE_MEDIA_ID" \
       PLL_FIX_ITEMS="$FIXTURE_ITEM_IDS" \
       PLL_FIX_MENU="$FIXTURE_MENU_ID" \
       PLL_FIX_PT="$FIXTURE_ARCHIVE_PT" \
       PLL_FIX_SRC="$SRC" \
       PLL_FIX_DST="$DST" \
       PLL_FIX_THIRD="$FIXTURE_THIRD_LANG" \
       PLL_FIX_VICTIM="$VERIFY_VICTIM" \
       PLL_FIX_VICTIM_LANG="$VERIFY_VICTIM_LANG" \
       wp eval '
$posts      = array_filter( array_map( "intval", explode( ",", (string) getenv( "PLL_FIX_POSTS" ) ) ) );
$items      = array_filter( array_map( "intval", explode( ",", (string) getenv( "PLL_FIX_ITEMS" ) ) ) );
$src_menu   = (int) getenv( "PLL_FIX_MENU" );
$archive_pt = (string) getenv( "PLL_FIX_PT" );
$src        = (string) getenv( "PLL_FIX_SRC" );
$dst        = (string) getenv( "PLL_FIX_DST" );
$third      = (string) getenv( "PLL_FIX_THIRD" );

// Restore before any deletion: this is a REAL post on the site whose language
// the verify test stripped, not fixture output. If the run died between the
// break and the repair, this is the only thing that puts it back.
$victim = (int) getenv( "PLL_FIX_VICTIM" );
if ( $victim && get_post( $victim ) ) {
  pll_set_post_language( $victim, (string) getenv( "PLL_FIX_VICTIM_LANG" ) );
}

// Counterparts first, while the translation groups still exist.
$all = $posts;
foreach ( $posts as $id ) {
  foreach ( (array) pll_get_post_translations( $id ) as $tid ) { $all[] = (int) $tid; }
}
$all = array_values( array_unique( array_filter( $all ) ) );

// The archive item has no object id to match on, so the only thing left to
// identify its mirror by is the post type -- which is NOT unique to this
// fixture. It is therefore looked for in exactly one place: the TARGET-language
// menu of the location whose source menu is the one the fixture wrote into.
// The previous version accepted any menu other than the source menu, which
// hard-deletes a legitimate archive entry out of a footer menu or a hand-built
// target menu; the pre-flight guard below only ever inspected the source menu,
// so it never justified that wider sweep.
$theme        = get_stylesheet();
$opts         = get_option( "polylang" );
$assign       = isset( $opts["nav_menus"][ $theme ] ) ? (array) $opts["nav_menus"][ $theme ] : array();
$target_menus = array();
foreach ( $assign as $loc => $per ) {
  if ( ! is_array( $per ) || empty( $per[ $dst ] ) ) { continue; }
  if ( $src_menu && (int) ( isset( $per[ $src ] ) ? $per[ $src ] : 0 ) !== $src_menu ) { continue; }
  $target_menus[] = (int) $per[ $dst ];
}

// Menu items pointing at a fixture post are matched by what they POINT AT, in
// every menu, because the importer mints the target menu ids itself -- this
// script never sees them, and the post ids are unambiguous.
foreach ( (array) wp_get_nav_menus() as $menu ) {
  foreach ( (array) wp_get_nav_menu_items( $menu->term_id, array( "post_status" => "any" ) ) as $mi ) {
    $fixture_post    = ( "post_type" === $mi->type && in_array( (int) $mi->object_id, $all, true ) );
    $fixture_archive = ( "post_type_archive" === $mi->type && "" !== $archive_pt
                         && $mi->object === $archive_pt
                         && in_array( (int) $menu->term_id, $target_menus, true ) );
    if ( $fixture_post || $fixture_archive ) { wp_delete_post( (int) $mi->ID, true ); }
  }
}
// ...and the remembered source-menu ids, which also covers an item whose
// target post a previous partial cleanup already removed.
foreach ( $items as $iid ) { wp_delete_post( $iid, true ); }
foreach ( $all as $id ) { wp_delete_post( $id, true ); }

// A failure between adding the temporary third language and removing it again
// would otherwise leave it behind and break every later run. Gated on
// PLL_FIX_THIRD, which this suite sets only after confirming the language did
// NOT already exist and then creating it: everything carrying that language is
// therefore this run own output. Without the gate this block deletes every
// post and term of a language the user already had, on the failure path, on a
// site the suite may never even have reached the third-language block on.
if ( "" !== $third ) {
  $lang = PLL()->model->get_language( $third );
  if ( $lang ) {
    foreach ( get_posts( array( "post_type" => "any", "numberposts" => -1, "post_status" => "any", "fields" => "ids" ) ) as $pid ) {
      if ( pll_get_post_language( $pid ) === $third ) { wp_delete_post( $pid, true ); }
    }
    foreach ( array_keys( PLL()->model->get_translated_taxonomies() ) as $tax ) {
      $terms = get_terms( array( "taxonomy" => $tax, "hide_empty" => false ) );
      if ( is_wp_error( $terms ) ) { continue; }
      foreach ( $terms as $term ) {
        if ( pll_get_term_language( $term->term_id ) === $third ) { wp_delete_term( $term->term_id, $tax ); }
      }
    }
    PLL()->model->languages->delete( $lang->term_id );
  }
}
' --allow-root) >/dev/null 2>&1 || true
  return $status
}
trap cleanup EXIT

# The menu to fixture into must be the SOURCE-language one. Polylang's own
# per-language record is authoritative; the bare location is only accepted once
# it is confirmed not to be recorded as some other language's menu, since
# get_nav_menu_locations() also carries Polylang's synthetic `loc___lang` keys.
# TWO passes, not one: evaluating the fallback inside the same iteration as the
# per-language lookup lets a location whose bare menu happens to be unclaimed
# short-circuit ahead of a later location that carries a proper $assign record.
# Every authoritative record is therefore considered before any guess is.
FIXTURE_MENU_ID="$(cd "$SITE" && PLL_FIX_SRC="$SRC" wp eval '
$src    = getenv("PLL_FIX_SRC");
$theme  = get_stylesheet();
$opts   = get_option("polylang");
$assign = isset($opts["nav_menus"][$theme]) ? $opts["nav_menus"][$theme] : [];
$locs   = get_nav_menu_locations();
$registered = array_keys(get_registered_nav_menus());
foreach ($registered as $loc) {
  $per = isset($assign[$loc]) ? $assign[$loc] : [];
  if (!empty($per[$src])) { echo (int) $per[$src]; exit; }
}
foreach ($registered as $loc) {
  $per = isset($assign[$loc]) ? $assign[$loc] : [];
  if (empty($locs[$loc])) { continue; }
  $id = (int) $locs[$loc];
  $claimed_by_other_language = false;
  foreach ($per as $lang => $mid) {
    if ((int) $mid === $id && $lang !== $src) { $claimed_by_other_language = true; }
  }
  if ($claimed_by_other_language) { continue; }
  echo $id; exit;
}
' --allow-root)"
[[ -n "$FIXTURE_MENU_ID" ]] || { echo "FAIL: no registered menu location holds a $SRC menu to fixture into"; exit 1; }

# Must be a post type Polylang actually localizes the archive link of:
# PLL_Filters_Links::post_type_archive_link() localizes only when
# is_translated_post_type($pt) && "post" !== $pt. Picking any archive-bearing
# type would leave the localization assertion further down with nothing to
# check on some sites, and an assertion that silently checks nothing is the
# defect class this suite exists to avoid.
ARCHIVE_PT="$(cd "$SITE" && wp eval '
foreach (get_post_types(["public"=>true], "objects") as $pt) {
  if (!$pt->has_archive || "post" === $pt->name) { continue; }
  if (!PLL()->model->is_translated_post_type($pt->name)) { continue; }
  echo $pt->name; exit;
}
' --allow-root)"
[[ -n "$ARCHIVE_PT" ]] || { echo "FAIL: no translatable public post type (other than 'post') has an archive to build a post_type_archive menu item from"; exit 1; }

if ! (cd "$SITE" && PLL_FIX_MENU="$FIXTURE_MENU_ID" PLL_FIX_PT="$ARCHIVE_PT" wp eval '
foreach ((array) wp_get_nav_menu_items((int) getenv("PLL_FIX_MENU")) as $mi) {
  if ("post_type_archive" === $mi->type && $mi->object === getenv("PLL_FIX_PT")) { exit(1); }
}
' --allow-root); then
  echo "FAIL: the $SRC menu already has a post_type_archive item for '$ARCHIVE_PT'; the fixture assumes it is the only source of one so that cleanup can identify its mirror in the translated menu"
  exit 1
fi

FIXTURE_PARENT_ID="$(cd "$SITE" && wp post create --post_type=page --post_title="PLL fixture parent page" --post_status=publish --porcelain --allow-root)"
[[ -n "$FIXTURE_PARENT_ID" ]] || { echo "FAIL: could not create the fixture parent page"; exit 1; }

FIXTURE_CHILD_ID="$(cd "$SITE" && wp post create --post_type=page --post_title="PLL fixture child page" --post_status=publish --post_parent="$FIXTURE_PARENT_ID" --porcelain --allow-root)"
[[ -n "$FIXTURE_CHILD_ID" ]] || { echo "FAIL: could not create the fixture child page"; exit 1; }

# A real file, imported through WordPress, so the counterpart's
# _wp_attached_file linkage can be asserted for real further down.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d > "$FIXTURE_MEDIA_FILE"
FIXTURE_MEDIA_ID="$(cd "$SITE" && wp media import "$FIXTURE_MEDIA_FILE" --title="PLL fixture image" --porcelain --allow-root)"
[[ -n "$FIXTURE_MEDIA_ID" ]] || { echo "FAIL: could not import the fixture attachment"; exit 1; }

(cd "$SITE" && PLL_FIX_SRC="$SRC" PLL_FIX_IDS="$FIXTURE_PARENT_ID,$FIXTURE_CHILD_ID,$FIXTURE_MEDIA_ID" wp eval '
foreach (array_filter(array_map("intval", explode(",", getenv("PLL_FIX_IDS")))) as $id) {
  pll_set_post_language($id, getenv("PLL_FIX_SRC"));
}
' --allow-root) >/dev/null

FIXTURE_ITEM_PARENT="$(cd "$SITE" && wp menu item add-post "$FIXTURE_MENU_ID" "$FIXTURE_PARENT_ID" --title="PLL fixture parent page" --porcelain --allow-root)"
[[ -n "$FIXTURE_ITEM_PARENT" ]] || { echo "FAIL: could not add the fixture parent page to the $SRC menu"; exit 1; }
FIXTURE_ITEM_IDS="$FIXTURE_ITEM_PARENT"

FIXTURE_ITEM_CHILD="$(cd "$SITE" && wp menu item add-post "$FIXTURE_MENU_ID" "$FIXTURE_CHILD_ID" --title="PLL fixture child page" --parent-id="$FIXTURE_ITEM_PARENT" --porcelain --allow-root)"
[[ -n "$FIXTURE_ITEM_CHILD" ]] || { echo "FAIL: could not nest the fixture child page under the fixture parent menu item"; exit 1; }
FIXTURE_ITEM_IDS="$FIXTURE_ITEM_IDS,$FIXTURE_ITEM_CHILD"

FIXTURE_ITEM_ARCHIVE="$(cd "$SITE" && PLL_FIX_MENU="$FIXTURE_MENU_ID" PLL_FIX_PT="$ARCHIVE_PT" wp eval '
$id = wp_update_nav_menu_item((int) getenv("PLL_FIX_MENU"), 0, array(
  "menu-item-title"  => "PLL fixture archive",
  "menu-item-status" => "publish",
  "menu-item-type"   => "post_type_archive",
  "menu-item-object" => getenv("PLL_FIX_PT"),
));
if (is_wp_error($id)) { fwrite(STDERR, $id->get_error_message()); exit(1); }
echo (int) $id;
' --allow-root)"
[[ -n "$FIXTURE_ITEM_ARCHIVE" ]] || { echo "FAIL: could not add a post_type_archive item to the $SRC menu"; exit 1; }
FIXTURE_ITEM_IDS="$FIXTURE_ITEM_IDS,$FIXTURE_ITEM_ARCHIVE"
# Only NOW, once an archive item this suite created actually exists. Assigning
# it at discovery time armed cleanup()'s archive sweep on every run that failed
# before creating one -- a sweep for objects the run had never made.
FIXTURE_ARCHIVE_PT="$ARCHIVE_PT"

echo "  menu $FIXTURE_MENU_ID: pages $FIXTURE_PARENT_ID/$FIXTURE_CHILD_ID, media $FIXTURE_MEDIA_ID, items $FIXTURE_ITEM_IDS ($FIXTURE_ARCHIVE_PT archive)"

# Give the fixture parent page a link into the fixture child page BEFORE the
# first export below, so the export -> translate -> import cycle exercised
# further down this file (the "import writes linked, correctly-languaged
# counterparts" section) already carries this href straight through the
# import it does anyway. See "internal links in translated content point at
# translated targets" further down for the assertion built on it -- built on
# THIS RUN'S OWN fixture pages (ruling T9-A), never on the site's real
# content, so cleanup() tears it down for free along with the rest of the
# fixture.
FIXTURE_CHILD_PERMALINK="$(cd "$SITE" && PLL_CHILD="$FIXTURE_CHILD_ID" wp eval 'echo get_permalink((int) getenv("PLL_CHILD"));' --allow-root)"
[[ -n "$FIXTURE_CHILD_PERMALINK" ]] || { echo "FAIL: could not read the fixture child page's permalink"; exit 1; }

# The backslash sentinel rides along in the SAME post as the href, on purpose.
# The link-rewrite pass only writes post_content back when it actually
# rewrites something, so a post with no link never exercises the write at all
# -- the corruption and the rewrite have to happen to the same post for the
# assertion to be capable of failing.
#
# wp_slash() here is not decoration: wp_update_post() unslashes what it is
# given, so seeding this WITHOUT it stores "C:Userstest" and the assertion
# downstream would pass against a fixture that never held a backslash. That is
# the vacuous-assertion shape this branch has hit repeatedly; the read-back
# below proves the fixture really carries the sentinel before anything else
# runs.
FIXTURE_SLASH='C:\Users\test and a literal backslash \\ pair'
(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" PLL_HREF="$FIXTURE_CHILD_PERMALINK" PLL_SLASH="$FIXTURE_SLASH" wp eval '
$res = wp_update_post(wp_slash(array(
  "ID"           => (int) getenv("PLL_PARENT"),
  "post_content" => "<p>See the <a href=\"" . getenv("PLL_HREF") . "\">fixture child page</a>.</p>"
                  . "<p>" . getenv("PLL_SLASH") . "</p>",
)), true);
if (is_wp_error($res)) { fwrite(STDERR, $res->get_error_message()); exit(1); }
' --allow-root) || { echo "FAIL: could not add an internal link to the fixture parent page"; exit 1; }

FIXTURE_SLASH_READBACK="$(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" wp eval '
echo get_post_field("post_content", (int) getenv("PLL_PARENT"));
' --allow-root)"
[[ "$FIXTURE_SLASH_READBACK" == *"$FIXTURE_SLASH"* ]] || {
  echo "FAIL: the fixture parent does not actually contain the backslash sentinel after seeding --"
  echo "      the slash-preservation assertion downstream would be vacuous. Stored content:"
  echo "      $FIXTURE_SLASH_READBACK"
  exit 1
}

echo "── export produces a valid manifest ──"
MAN="$FIXTURE_TMPDIR/manifest.json"
run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$MAN" >/dev/null || { echo "FAIL: export exited non-zero"; exit 1; }
test -s "$MAN" || { echo "FAIL: export wrote nothing"; exit 1; }

php -r '
$m = json_decode(file_get_contents($argv[1]), true);
if (!is_array($m)) { fwrite(STDERR, "FAIL: manifest is not valid JSON\n"); exit(1); }
foreach (["source_lang","target_lang","items"] as $k) {
  if (!array_key_exists($k, $m)) { fwrite(STDERR, "FAIL: manifest missing $k\n"); exit(1); }
}
if ($m["source_lang"] !== $argv[2]) { fwrite(STDERR, "FAIL: wrong source_lang\n"); exit(1); }
if ($m["target_lang"] !== $argv[3]) { fwrite(STDERR, "FAIL: wrong target_lang\n"); exit(1); }
if (!count($m["items"])) { fwrite(STDERR, "FAIL: no items exported from a site with untranslated content\n"); exit(1); }
foreach ($m["items"] as $it) {
  foreach (["id","kind","hash","fields"] as $k) {
    if (!array_key_exists($k, $it)) { fwrite(STDERR, "FAIL: item missing $k: ".json_encode($it)."\n"); exit(1); }
  }
  if (!in_array($it["kind"], ["post","term","string","menu"], true)) {
    fwrite(STDERR, "FAIL: unknown kind {$it["kind"]}\n"); exit(1);
  }
}
$has_attachment = false;
foreach ($m["items"] as $it) {
  if (($it["post_type"] ?? "") === "attachment") { $has_attachment = true; break; }
}
if (!$has_attachment) {
  fwrite(STDERR, "FAIL: no attachment in the manifest -- 'inherit' status regression?\n"); exit(1);
}
echo "  items: ", count($m["items"]), "\n";
' "$MAN" "$SRC" "$DST" || exit 1

echo "── export excludes date-format strings ──"
DF="$(cd "$SITE" && wp option get date_format --allow-root)"
TF="$(cd "$SITE" && wp option get time_format --allow-root)"
php -r '
$m = json_decode(file_get_contents($argv[1]), true);
foreach ($m["items"] as $it) {
  if (($it["kind"] ?? "") !== "string") continue;
  $v = $it["fields"]["value"] ?? "";
  if ($v === $argv[2] || $v === $argv[3]) {
    fwrite(STDERR, "FAIL: date/time format leaked into manifest: $v\n"); exit(1);
  }
}
' "$MAN" "$DF" "$TF" || exit 1
rm -f "$MAN"

echo "── import writes linked, correctly-languaged counterparts ──"
MAN2="$FIXTURE_TMPDIR/manifest-translated.json"
run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$MAN2" >/dev/null

# Translate mechanically: prefix every value. Enough to prove the write path
# and to make the "identical to source" check in verify meaningful.
php -r '
$m = json_decode(file_get_contents($argv[1]), true);
foreach ($m["items"] as &$it) {
  foreach ($it["fields"] as $k => $v) {
    if ($k === "post_name" || $k === "slug") { $it["fields"][$k] = $v . "-" . $argv[2]; continue; }
    if (is_string($v) && $v !== "") $it["fields"][$k] = "[" . strtoupper($argv[2]) . "] " . $v;
  }
  if (!empty($it["acf"])) {
    foreach ($it["acf"] as $k => $v) $it["acf"][$k] = "[" . strtoupper($argv[2]) . "] " . $v;
  }
}
unset($it);
file_put_contents($argv[1], json_encode($m, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
' "$MAN2" "$DST"

# Output is kept (not discarded) on purpose: it is the only place the
# per-menu reconciliation line below can be read from, and a run() call that
# swallows it would hide silent item loss the same way the menu-only fixture
# above closes the "nothing to check" gap.
MENU_IMPORT_OUT="$(run "$SCRIPTS/pll-import.php" "$MAN2")" || { echo "FAIL: import exited non-zero"; echo "$MENU_IMPORT_OUT"; exit 1; }
echo "$MENU_IMPORT_OUT"

echo "── menu reconciliation: every source item is accounted for ──"
# Skipping an item with no target counterpart is correct behaviour (e.g. the
# 8 taxonomy items on this fixture whose product_cat terms have no language
# assigned at all) -- so this does NOT assert written === source. It asserts
# every source item landed as written OR skipped-with-a-reason, so a menu
# quietly losing items (neither written nor accounted for) fails loudly.
php -r '
$out = $argv[1];
if (!preg_match_all("/reconciliation: source=(\d+) written=(\d+) skipped=(\d+)/", $out, $m, PREG_SET_ORDER)) {
  fwrite(STDERR, "FAIL: no menu reconciliation line found in import output\n"); exit(1);
}
$total_written = 0;
foreach ($m as $row) {
  $s = (int) $row[1]; $w = (int) $row[2]; $sk = (int) $row[3];
  echo "  source=$s written=$w skipped=$sk\n";
  if ($s === 0) { fwrite(STDERR, "FAIL: reconciliation reports a 0-item source menu\n"); exit(1); }
  if ($w + $sk !== $s) { fwrite(STDERR, "FAIL: written($w) + skipped($sk) != source($s)\n"); exit(1); }
  $total_written += $w;
}
// Floor, not just the sum. written+skipped==source is satisfied by every path
// in the importer loop by construction -- each one bumps exactly one counter --
// so on its own it can never fail. A run that skipped ALL of its items would
// still balance perfectly while producing empty translated menus, and only this
// line catches that.
//
// Floored over the RUN, not per menu: a second location whose source menu
// consists entirely of items with no target counterpart legitimately yields
// written=0 -- the importer treats that as fine and it is fine, so failing on
// it would make the suite reject correct behaviour. Passing today with a
// per-menu floor was an accident of this site having exactly one location.
if ($total_written === 0) {
  fwrite(STDERR, "FAIL: reconciliation wrote 0 menu item(s) across " . count($m) . " menu(s)\n"); exit(1);
}
echo "  total written across " . count($m) . " menu(s): $total_written\n";
' "$MENU_IMPORT_OUT" || exit 1

(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$bad = 0; $checked = 0;
foreach (get_posts(["post_type"=>array_keys(PLL()->model->get_translated_post_types()),
                    "numberposts"=>-1,"post_status"=>"any","lang"=>$src,"fields"=>"ids"]) as $id) {
  if (pll_get_post_language($id) !== $src) continue;
  $t = pll_get_post_translations($id);
  if (empty($t[$dst])) { echo "  no counterpart for post $id\n"; $bad++; continue; }
  $tid = (int) $t[$dst];
  $checked++;
  if (pll_get_post_language($tid) !== $dst) { echo "  post $tid has wrong language\n"; $bad++; }
  $back = pll_get_post_translations($tid);
  if ((int)($back[$src] ?? 0) !== (int)$id) { echo "  group not symmetric for $id/$tid\n"; $bad++; }
  if (get_post_meta($tid, "_pll_src_hash", true) === "") { echo "  post $tid has no source hash\n"; $bad++; }
}
echo "  checked $checked counterpart(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: import produced broken translations"; exit 1; }

echo "── parent-child hierarchy is preserved across languages ──"
(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$bad = 0; $checked = 0;
foreach (get_posts(["post_type"=>"page","numberposts"=>-1,"post_status"=>"any","lang"=>$src,"fields"=>"ids"]) as $id) {
  $p = get_post($id);
  if (!$p || (int)$p->post_parent === 0) continue;
  $t = pll_get_post_translations($id);
  if (empty($t[$dst])) continue;
  $tid = (int) $t[$dst];
  $parent_t = pll_get_post_translations((int)$p->post_parent);
  if (empty($parent_t[$dst])) continue; // parent itself has no counterpart; nothing to fix up
  $checked++;
  $expected_parent = (int) $parent_t[$dst];
  $actual_parent = (int) get_post($tid)->post_parent;
  if ($actual_parent !== $expected_parent) {
    echo "  post $tid: expected parent $expected_parent, got $actual_parent\n"; $bad++;
  }
}
echo "  checked $checked parent-child relationship(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: parent hierarchy not preserved across languages"; exit 1; }

echo "── translated attachments have working file linkage ──"
(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$bad = 0; $checked = 0;
foreach (get_posts(["post_type"=>"attachment","numberposts"=>-1,"post_status"=>"inherit","lang"=>$src,"fields"=>"ids"]) as $id) {
  $t = pll_get_post_translations($id);
  if (empty($t[$dst])) { echo "  no counterpart for attachment $id\n"; $bad++; continue; }
  $tid = (int) $t[$dst];
  $checked++;
  $file = get_post_meta($tid, "_wp_attached_file", true);
  if ($file === "") { echo "  attachment $tid has no _wp_attached_file meta\n"; $bad++; continue; }
  $path = get_attached_file($tid);
  if (!$path || !file_exists($path)) { echo "  attachment $tid file does not exist on disk: $path\n"; $bad++; }
}
echo "  checked $checked attachment(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: translated attachments have broken file linkage"; exit 1; }

echo "── internal links in translated content point at translated targets ──"
# Built explicitly on THIS RUN's own fixture pages (ruling T9-A), not by
# hunting the site's real content -- editing a real page's content on a
# failure path is exactly the class of defect three other findings on this
# branch already came from, and cleanup() only knows how to remove what it
# itself created. The href was written into the fixture parent's
# post_content BEFORE the export/translate/import cycle above ran (see the
# fixture-seeding section), so MAN2 already carried it and the import above
# already exercised the link-rewrite pass on it once.
#
# Distinct exit codes for distinct reasons (ruling T9-B): 2 means the
# assertion checked nothing (no href to test -- a fixture defect, not an
# importer defect), 3 means a fixture counterpart is missing (setup broke
# earlier and this test cannot run at all), anything else nonzero means a
# real language mismatch was found. The caller below matches on the code,
# not just "nonzero", so each path reports its own reason instead of all
# three collapsing into one message.
set +e
LINK_OUT="$(cd "$SITE" && PLL_DST="$DST" PLL_PARENT="$FIXTURE_PARENT_ID" PLL_CHILD="$FIXTURE_CHILD_ID" wp eval '
$dst    = getenv("PLL_DST");
$parent = (int) getenv("PLL_PARENT");
$child  = (int) getenv("PLL_CHILD");

$t = pll_get_post_translations($parent);
if (empty($t[$dst])) { fwrite(STDERR, "fixture parent has no $dst counterpart\n"); exit(3); }
$parent_target = (int) $t[$dst];

$ct = pll_get_post_translations($child);
if (empty($ct[$dst])) { fwrite(STDERR, "fixture child has no $dst counterpart\n"); exit(3); }
$child_target = (int) $ct[$dst];

$content = get_post_field("post_content", $parent_target);
// \x27 is an apostrophe. A literal one cannot appear here: the whole PHP
// body is inside bash single quotes, which have no escape mechanism at all.
if (!preg_match_all("/href=([\"\x27])([^\"\x27]+)\\1/", $content, $m)) {
  fwrite(STDERR, "no href found in the fixture parent counterpart content\n");
  exit(2);
}

$checked = 0; $bad = 0;
foreach ($m[2] as $url) {
  $found = url_to_postid($url);
  if (!$found) { continue; } // external, or not a post URL -- nothing to check
  $checked++;
  $lang = pll_get_post_language($found);
  if ($lang !== $dst) {
    echo "  post $parent_target links to a $lang post ($found)\n";
    $bad++;
  } elseif ((int) $found !== $child_target) {
    echo "  post $parent_target links to $dst post $found, expected the fixture child counterpart $child_target\n";
    $bad++;
  }
}
echo "  checked $checked internal link(s)\n";
if ($checked === 0) { exit(2); }
exit($bad === 0 ? 0 : 1);
' --allow-root)"
LINK_STATUS=$?
set -e
echo "$LINK_OUT"
case $LINK_STATUS in
  0) ;;
  2) echo "FAIL: internal-link assertion checked nothing -- the fixture parent's translated content has no internal link to test"; exit 1 ;;
  3) echo "FAIL: fixture parent or child counterpart is missing -- cannot test link rewriting"; exit 1 ;;
  *) echo "FAIL: translated content links into the wrong language"; exit 1 ;;
esac

echo "── backslashes in content survive the round trip ──"
# WordPress unslashes everything handed to wp_insert_post/wp_update_post right
# before it hits the database, so any writer that does not wp_slash() its
# payload silently strips ONE level of backslashes from real content on every
# write. Two writers in pll-import.php touch this post: the main post write
# and the link-rewrite pass, which reads post_content out of the DB (already
# unslashed), rewrites the href and writes it straight back -- so a single
# rewritten link is enough to eat the backslashes of everything else in that
# post, and it compounds once per cycle.
#
# The sentinel was seeded into the fixture parent and read back at seeding
# time, so this assertion cannot pass against a fixture that never held one.
SLASH_TARGET_ID="$(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" PLL_DST="$DST" wp eval '
$t = pll_get_post_translations((int) getenv("PLL_PARENT"));
$dst = getenv("PLL_DST");
echo empty($t[$dst]) ? "" : (int) $t[$dst];
' --allow-root)"
[[ -n "$SLASH_TARGET_ID" ]] || { echo "FAIL: fixture parent has no $DST counterpart to check backslash survival on"; exit 1; }

SLASH_TARGET_CONTENT="$(cd "$SITE" && PLL_TID="$SLASH_TARGET_ID" wp eval '
echo get_post_field("post_content", (int) getenv("PLL_TID"));
' --allow-root)"

# The source must STILL hold it too: the rewrite pass is scoped to target
# posts, but a regression that widened it would corrupt the original.
SLASH_SOURCE_CONTENT="$(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" wp eval '
echo get_post_field("post_content", (int) getenv("PLL_PARENT"));
' --allow-root)"

[[ "$SLASH_TARGET_CONTENT" == *"$FIXTURE_SLASH"* ]] || {
  echo "FAIL: backslashes were stripped from the translated post_content -- a writer in pll-import.php is not wp_slash()ing its payload"
  echo "      expected to contain: $FIXTURE_SLASH"
  echo "      target $SLASH_TARGET_ID content: $SLASH_TARGET_CONTENT"
  exit 1
}
[[ "$SLASH_SOURCE_CONTENT" == *"$FIXTURE_SLASH"* ]] || {
  echo "FAIL: backslashes were stripped from the SOURCE post_content -- the import wrote to a post it should never touch"
  echo "      source $FIXTURE_PARENT_ID content: $SLASH_SOURCE_CONTENT"
  exit 1
}
echo "  backslash sentinel intact in source $FIXTURE_PARENT_ID and target $SLASH_TARGET_ID"

echo "── internal-link rewrite pass is idempotent (ruling T9-G) ──"
# A second IMPORT over the SAME manifest FILE is not the right way to
# exercise this: pll-import.php never writes target_id back into the
# manifest on disk, so replaying MAN2 verbatim makes every item look
# uncreated again and wp_insert_post() mints a SECOND counterpart --
# a pre-existing importer behaviour with or without this task's change, and
# not what a real second run looks like (measured: doing exactly this made
# the site grow duplicate posts on every "second run", which is the actual
# bug this comment exists to explain rather than reproduce as a false
# failure). A real second run always re-EXPORTS first, which is what
# "re-export after import is empty" a few lines below already proves yields
# ZERO items once a site is fully translated -- so a fresh export, imported
# again, is what actually exercises the link-rewrite/menu passes a second
# time against unchanged site content, since those two passes run
# unconditionally on every import regardless of what the manifest contains.
PARENT_TARGET_ID="$(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" PLL_DST="$DST" wp eval '
$t = pll_get_post_translations((int) getenv("PLL_PARENT"));
$dst = getenv("PLL_DST");
echo empty($t[$dst]) ? "0" : (int) $t[$dst];
' --allow-root)"
[[ -n "$PARENT_TARGET_ID" && "$PARENT_TARGET_ID" != "0" ]] || { echo "FAIL: could not resolve the fixture parent counterpart for the idempotency check"; exit 1; }

CONTENT_BEFORE="$(cd "$SITE" && PLL_TID="$PARENT_TARGET_ID" wp eval 'echo get_post_field("post_content", (int) getenv("PLL_TID"));' --allow-root)"

IDEMPOTENT_MAN="$FIXTURE_TMPDIR/manifest-idempotent.json"
run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$IDEMPOTENT_MAN" >/dev/null || { echo "FAIL: re-export for the idempotency check exited non-zero"; exit 1; }

IDEMPOTENT_OUT="$(run "$SCRIPTS/pll-import.php" "$IDEMPOTENT_MAN")" || { echo "FAIL: second import (idempotency check) exited non-zero"; echo "$IDEMPOTENT_OUT"; exit 1; }
echo "$IDEMPOTENT_OUT"
rm -f "$IDEMPOTENT_MAN"

grep -qE "Rewrote internal link\(s\) in 0 post\(s\) and 0 ACF reference field\(s\)\." <<<"$IDEMPOTENT_OUT" || {
  echo "FAIL: second import over an unchanged, fully-translated site rewrote a nonzero number of links/fields -- the link-rewrite pass is not idempotent"
  exit 1
}
grep -qE "Rewrote 0 custom menu item URL\(s\)\." <<<"$IDEMPOTENT_OUT" || {
  echo "FAIL: second import over an unchanged, fully-translated site rewrote a nonzero number of custom menu item URLs -- the pass is not idempotent"
  exit 1
}

CONTENT_AFTER="$(cd "$SITE" && PLL_TID="$PARENT_TARGET_ID" wp eval 'echo get_post_field("post_content", (int) getenv("PLL_TID"));' --allow-root)"
[[ "$CONTENT_BEFORE" == "$CONTENT_AFTER" ]] || { echo "FAIL: post_content changed on a re-run with no source change -- the link-rewrite pass is not idempotent"; exit 1; }
echo "  post_content byte-identical across the re-run (${#CONTENT_AFTER} bytes)"

echo "── re-export after import is empty (idempotent) ──"
MAN3="$FIXTURE_TMPDIR/manifest-reexport.json"
run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$MAN3" >/dev/null
php -r '
$m = json_decode(file_get_contents($argv[1]), true);
$n = count($m["items"]);
if ($n !== 0) { fwrite(STDERR, "FAIL: re-export still lists $n item(s); hashes were not recorded\n"); exit(1); }
' "$MAN3" || exit 1
rm -f "$MAN2" "$MAN3"

echo "── a third language survives an import for another target ──"
# pll_save_post_translations()/pll_save_term_translations() REPLACE the whole
# group rather than merging into it. A prior version of this script built a
# fresh two-key {source,target} array, which silently dropped every other
# language already in the group. This is not hypothetical: the documented
# workflow is "one target language per run, run it again for a third
# language" -- so that bug destroys its own earlier output on the second run.
#
# The scaffolding language is created here and destroyed at the end of the
# block, so this stays re-runnable against a persistent site. That teardown is
# also the reason for the probe below. pll-setup.php succeeds SILENTLY on a
# site that already has the language, so without a pre-existence record the
# teardown -- and worse, cleanup(), which is trapped over the WHOLE run -- could
# not tell "the language this run created" from "the language the user has been
# writing content in for a year". It deleted every post and every term of that
# language either way. A failure at any assertion above, long before this block
# was reached, was enough to trigger it.
#
# So: probe FIRST. If the language already exists, this run neither created it
# nor may delete it, and the assertion is SKIPPED rather than adapted -- an
# adapted assertion against pre-existing content would be asserting something
# other than what it says it asserts.
THIRD_PREEXISTS="$(cd "$SITE" && PLL_CHK_THIRD="$THIRD" wp eval '
echo PLL()->model->get_language(getenv("PLL_CHK_THIRD")) ? "1" : "0";
' --allow-root)"
case "$THIRD_PREEXISTS" in
  0|1) ;;
  *) echo "FAIL: could not determine whether language '$THIRD' already exists (probe said '$THIRD_PREEXISTS')"; exit 1 ;;
esac

if [[ "$THIRD_PREEXISTS" == "1" ]]; then
  echo "  SKIP: language '$THIRD' already exists on this site, so this run did not create it and must not delete it."
  echo "        Set PLL_TEST_THIRD to a language the site does NOT have to exercise this assertion."
else

run "$SCRIPTS/pll-setup.php" "$SRC" "$THIRD" >/dev/null || { echo "FAIL: could not add temporary language $THIRD"; exit 1; }
# Armed only now: the probe above proved the language was absent, so everything
# carrying it from here on is this run's own output and cleanup() may remove it.
FIXTURE_THIRD_LANG="$THIRD"

echo "── export refuses to guess a menu it cannot attribute to the source language ──"
# pll-export.php used to fall back to get_nav_menu_locations()[$loc] with no
# language check whenever Polylang had no per-language record for the source.
# That bare key holds the DEFAULT language's menu by Polylang's construction, so
# exporting FROM a non-default language handed the default language's menu over
# as if it were the source menu -- Spanish labels exported as the French source
# menu, silently. The temporary language above is exactly that shape: it exists,
# it has no menu of its own, and every location's bare menu belongs to somebody
# else. (The same fallback also fires for a location whose theme-mod entry is
# the falsy 0 that update_nav_menu_locations() writes for an unassigned menu.)
NAV_ASSIGN_JSON="$(cd "$SITE" && wp eval '
$o = get_option("polylang"); $t = get_stylesheet();
echo wp_json_encode(isset($o["nav_menus"][$t]) ? $o["nav_menus"][$t] : new stdClass());
' --allow-root)"
# How many registered locations are actually AMBIGUOUS for this source: no
# per-language record, but a bare menu that another language claims. If this is
# zero the assertion below proves nothing, so it is a hard failure.
AMBIGUOUS_LOCS="$(cd "$SITE" && PLL_CHK_THIRD="$THIRD" wp eval '
$third  = getenv("PLL_CHK_THIRD");
$o      = get_option("polylang"); $theme = get_stylesheet();
$assign = isset($o["nav_menus"][$theme]) ? (array) $o["nav_menus"][$theme] : [];
$locs   = get_nav_menu_locations();
$n = 0;
foreach (array_keys(get_registered_nav_menus()) as $loc) {
  $per = isset($assign[$loc]) ? (array) $assign[$loc] : [];
  if (!empty($per[$third])) { continue; }
  $cand = isset($locs[$loc]) ? (int) $locs[$loc] : 0;
  if (!$cand) { continue; }
  foreach ($per as $lang => $mid) {
    if ((int) $mid === $cand && $lang !== $third) { $n++; break; }
  }
}
echo $n;
' --allow-root)"
GUESS_MAN="$FIXTURE_TMPDIR/manifest-guess.json"
GUESS_OUT="$(run "$SCRIPTS/pll-export.php" "$THIRD" "$DST" "$GUESS_MAN" 2>&1)" || { echo "FAIL: export from the temporary language exited non-zero"; echo "$GUESS_OUT"; exit 1; }
php -r '
$m       = json_decode(file_get_contents($argv[1]), true);
$third   = $argv[2];
$assign  = json_decode($argv[3], true) ?: [];
$ambig   = (int) $argv[4];
$out     = $argv[5];
if ($ambig === 0) {
  fwrite(STDERR, "FAIL: no ambiguous menu location on this site -- the refusal assertion would check nothing\n"); exit(1);
}
// menu id => every language Polylang records it under.
$claims = [];
foreach ($assign as $loc => $per) {
  foreach ((array) $per as $lang => $mid) { $claims[(int) $mid][] = $lang; }
}
$bad = 0; $checked = 0;
foreach ($m["items"] as $it) {
  if (($it["kind"] ?? "") !== "menu") { continue; }
  $checked++;
  $mid = (int) ($it["menu_id"] ?? 0);
  foreach ($claims[$mid] ?? [] as $lang) {
    if ($lang !== $third) {
      fwrite(STDERR, "FAIL: export claimed menu $mid as the \"$third\" source menu for location {$it["location"]}, but Polylang records it as the \"$lang\" menu\n");
      $bad++;
    }
  }
}
if (substr_count($out, "refusing to guess") < $ambig) {
  fwrite(STDERR, "FAIL: export did not report refusing to guess for all $ambig ambiguous location(s):\n$out\n"); exit(1);
}
echo "  $ambig ambiguous location(s) refused, $checked menu item(s) exported\n";
exit($bad === 0 ? 0 : 1);
' "$GUESS_MAN" "$THIRD" "$NAV_ASSIGN_JSON" "$AMBIGUOUS_LOCS" "$GUESS_OUT" || { echo "FAIL: export guessed a menu belonging to another language"; exit 1; }
rm -f "$GUESS_MAN"

THIRD_MAN="$FIXTURE_TMPDIR/manifest-third.json"
THIRD_SRC_ID="$(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" PLL_CHK_THIRD="$THIRD" PLL_CHK_MAN="$THIRD_MAN" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST"); $third = getenv("PLL_CHK_THIRD");
$src_id = null;
foreach (get_posts(["post_type"=>"page","numberposts"=>-1,"post_status"=>"any","fields"=>"ids"]) as $id) {
  if (pll_get_post_language($id) !== $src) continue;
  $t = pll_get_post_translations($id);
  if (!empty($t[$dst])) { $src_id = $id; break; }
}
if (!$src_id) { fwrite(STDERR, "no source page with a target-language counterpart found\n"); exit(1); }
$manifest = array(
  "source_lang" => $src,
  "target_lang" => $third,
  "site_url"    => home_url(),
  "items"       => array( array(
    "id"        => "post:$src_id",
    "kind"      => "post",
    "post_type" => "page",
    "source_id" => (int) $src_id,
    "target_id" => null,
    "hash"      => str_repeat("f", 64),
    "fields"    => array("post_title" => "[" . strtoupper($third) . "] third language test"),
    "acf"       => array(),
  ) ),
);
file_put_contents(getenv("PLL_CHK_MAN"), json_encode($manifest));
echo $src_id;
' --allow-root)" || { echo "FAIL: could not build the third-language fixture"; exit 1; }

run "$SCRIPTS/pll-import.php" "$THIRD_MAN" >/dev/null || { echo "FAIL: import for a third language exited non-zero"; exit 1; }

(cd "$SITE" && PLL_CHK_SRC_ID="$THIRD_SRC_ID" PLL_CHK_DST="$DST" PLL_CHK_THIRD="$THIRD" wp eval '
$src_id = (int) getenv("PLL_CHK_SRC_ID"); $dst = getenv("PLL_CHK_DST"); $third = getenv("PLL_CHK_THIRD");
$t = pll_get_post_translations($src_id);
if (empty($t[$dst])) { echo "  pre-existing $dst counterpart was dropped from the group: " . json_encode($t) . "\n"; exit(1); }
if (empty($t[$third])) { echo "  $third counterpart missing from the group: " . json_encode($t) . "\n"; exit(1); }
echo "  group after adding $third: " . json_encode($t) . "\n";
exit(0);
' --allow-root) || { echo "FAIL: third-language import destroyed the existing translation group"; exit 1; }

# Clean up the scaffolding: delete the third-language post, any terms Polylang
# auto-duplicated into it (e.g. the default category -- add_language()
# duplicates default terms into every translated taxonomy, and
# languages->delete() only unlinks the language, it does not remove those
# term rows), and the temporary language itself, so re-running this suite
# against the same site starts from the same state. Safe to delete everything
# in that language for the same reason cleanup() is: the probe above proved the
# language did not exist before this run created it.
(cd "$SITE" && PLL_CHK_SRC_ID="$THIRD_SRC_ID" PLL_CHK_THIRD="$THIRD" wp eval '
$src_id = (int) getenv("PLL_CHK_SRC_ID"); $third = getenv("PLL_CHK_THIRD");
$t = pll_get_post_translations($src_id);
if (!empty($t[$third])) { wp_delete_post((int) $t[$third], true); }

foreach ( array_keys( PLL()->model->get_translated_taxonomies() ) as $tax ) {
  $terms = get_terms( array( "taxonomy" => $tax, "hide_empty" => false ) );
  if ( is_wp_error( $terms ) ) { continue; }
  foreach ( $terms as $term ) {
    if ( pll_get_term_language( $term->term_id ) === $third ) {
      wp_delete_term( $term->term_id, $tax );
    }
  }
}

$lang = PLL()->model->get_language($third);
if ($lang) { PLL()->model->languages->delete($lang->term_id); }
' --allow-root) >/dev/null
rm -f "$THIRD_MAN"
FIXTURE_THIRD_LANG=""

fi # third-language block

echo "── import refuses a manifest referencing missing objects ──"
BEFORE="$(cd "$SITE" && wp post list --post_type=any --format=count --allow-root)"
if run "$SCRIPTS/pll-import.php" "$REPO/tests/fixtures/polylang/manifest-translated.json" >/dev/null 2>&1; then
  echo "FAIL: import accepted a manifest with dangling references"; exit 1
fi
AFTER="$(cd "$SITE" && wp post list --post_type=any --format=count --allow-root)"
[[ "$BEFORE" == "$AFTER" ]] || { echo "FAIL: import wrote posts despite failing validation ($BEFORE -> $AFTER)"; exit 1; }

echo "── import refuses a term-only manifest with a dangling source_id ──"
# Isolated from the post item on purpose: get_term() returns NULL (not a
# WP_Error) for a nonexistent term id on a valid taxonomy, so a manifest that
# also contains a bad post item can pass validation for the wrong reason --
# the post check fails first and masks a broken term check. This fixture
# contains nothing else that could cause validation to fail.
TERM_BEFORE="$(cd "$SITE" && wp term list category --format=count --allow-root)"
if run "$SCRIPTS/pll-import.php" "$REPO/tests/fixtures/polylang/manifest-translated-term-only.json" >/dev/null 2>&1; then
  echo "FAIL: import accepted a term-only manifest with a dangling source_id"; exit 1
fi
TERM_AFTER="$(cd "$SITE" && wp term list category --format=count --allow-root)"
[[ "$TERM_BEFORE" == "$TERM_AFTER" ]] || { echo "FAIL: import created a term despite failing validation ($TERM_BEFORE -> $TERM_AFTER)"; exit 1; }

echo "── translated menu items point at target-language objects ──"
# wp eval takes NO positional args (unlike wp eval-file) — pass via the environment.
(cd "$SITE" && PLL_DST="$DST" wp eval '
$dst = getenv("PLL_DST");
$opts = get_option("polylang");
$theme = get_stylesheet();
$bad = 0; $checked = 0;
$locs = $opts["nav_menus"][$theme] ?? [];
if (!$locs) { echo "  no per-language menu assignments recorded\n"; exit(1); }
foreach ($locs as $loc => $per_lang) {
  if (empty($per_lang[$dst])) { echo "  location $loc has no $dst menu\n"; $bad++; continue; }
  foreach (wp_get_nav_menu_items($per_lang[$dst]) ?: [] as $mi) {
    if ($mi->type !== "post_type") continue;
    $checked++;
    $lang = pll_get_post_language($mi->object_id);
    if ($lang !== $dst) { echo "  menu item {$mi->ID} points at $lang object {$mi->object_id}\n"; $bad++; }
  }
}
echo "  checked $checked menu item(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: translated menu is wired to the wrong language"; exit 1; }

echo "── translated menu items keep their parent-child nesting ──"
# The importer builds the target menu in source order, which is not
# parent-first, so every item is written with parent 0 and re-parented in a
# second pass. That pass had zero coverage until the fixture above added a
# nested item: the only nested items on this site are taxonomy ones whose
# terms have no language, so both child and parent were skipped and the id map
# never yielded a parent to look up.
(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$opts = get_option("polylang"); $theme = get_stylesheet();
$locs = $opts["nav_menus"][$theme] ?? [];
if (!$locs) { echo "  no per-language menu assignments recorded\n"; exit(1); }
$bad = 0; $checked = 0;
foreach ($locs as $loc => $per_lang) {
  if (empty($per_lang[$src]) || empty($per_lang[$dst])) { echo "  location $loc has no $src/$dst menu pair\n"; $bad++; continue; }
  $source_items = wp_get_nav_menu_items($per_lang[$src]) ?: [];
  $target_items = wp_get_nav_menu_items($per_lang[$dst]) ?: [];
  // What a source item BECAME: the target menu ids are minted by the importer
  // and never reported, and the titles are translated, so the only stable
  // bridge between the two menus is the object each item points at.
  $by_object = [];
  foreach ($target_items as $ti) { if ($ti->type === "post_type") { $by_object[(int) $ti->object_id] = (int) $ti->ID; } }
  $counterpart = function ($mi) use ($by_object, $dst) {
    if ($mi->type !== "post_type") { return 0; }
    $t = pll_get_post_translations((int) $mi->object_id);
    if (empty($t[$dst])) { return 0; }
    return isset($by_object[(int) $t[$dst]]) ? $by_object[(int) $t[$dst]] : 0;
  };
  $src_by_id = [];
  foreach ($source_items as $si) { $src_by_id[(int) $si->ID] = $si; }
  foreach ($source_items as $si) {
    $parent = (int) $si->menu_item_parent;
    if (!$parent || empty($src_by_id[$parent])) { continue; }
    $mine   = $counterpart($si);
    $expect = $counterpart($src_by_id[$parent]);
    // Either end legitimately skipped (no counterpart to point at): the
    // importer leaves such an item at top level on purpose rather than guess.
    if (!$mine || !$expect) { continue; }
    $checked++;
    $actual = (int) get_post_meta($mine, "_menu_item_menu_item_parent", true);
    if ($actual !== $expect) { echo "  menu item $mine: expected parent $expect, got $actual\n"; $bad++; }
  }
}
echo "  checked $checked nested menu item(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: translated menu lost its parent-child nesting"; exit 1; }

echo "── post_type_archive menu items are copied, and resolve to the target language ──"
# An archive item is keyed by a post type slug, so there is no per-language
# object to re-point it at -- but it does not need one. wp_setup_nav_menu_item()
# resolves the URL at RENDER time via get_post_type_archive_link(), which
# Polylang localizes against the CURRENT language -- but only for post types it
# translates: PLL_Filters_Links::post_type_archive_link() (polylang/src/
# filters-links.php:200) localizes iff is_translated_post_type($pt) && "post"
# !== $pt, and returns the link untouched otherwise. So the item must be
# COPIED. Skipping it deletes a working nav entry from every translated menu;
# copying $mi->url instead would freeze the SOURCE permalink into the
# translated menu, which is why _menu_item_url is asserted empty here.
#
# _menu_item_url === "" plus url !== "" does NOT prove any of that on its own:
# under WP-CLI PLL()->curlang is null, so every archive link comes back
# unlocalized and the two states the assertion is meant to tell apart look
# identical. Localization IS the whole premise of copying rather than
# re-pointing, so curlang is set explicitly here and the link is compared
# against the same call made under the SOURCE language -- if the two agree, the
# translated menu is serving source-language archive links and the premise is
# false.
(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$opts = get_option("polylang"); $theme = get_stylesheet();
$locs = $opts["nav_menus"][$theme] ?? [];
if (!$locs) { echo "  no per-language menu assignments recorded\n"; exit(1); }

$src_lang = PLL()->model->get_language($src);
$dst_lang = PLL()->model->get_language($dst);
if (!$src_lang || !$dst_lang) { echo "  FAIL: could not load the language objects\n"; exit(1); }

// Everything below reads menu items with the TARGET language current, which is
// what a visitor browsing the translated site has.
PLL()->curlang = $dst_lang;

$bad = 0; $checked = 0; $localized = 0;
foreach ($locs as $loc => $per_lang) {
  if (empty($per_lang[$src]) || empty($per_lang[$dst])) { echo "  location $loc has no $src/$dst menu pair\n"; $bad++; continue; }
  $target_archives = [];
  foreach (wp_get_nav_menu_items($per_lang[$dst]) ?: [] as $ti) {
    if ($ti->type === "post_type_archive") { $target_archives[$ti->object] = $ti; }
  }
  foreach (wp_get_nav_menu_items($per_lang[$src]) ?: [] as $si) {
    if ($si->type !== "post_type_archive") { continue; }
    $checked++;
    if (empty($target_archives[$si->object])) {
      echo "  $dst menu is missing the archive item for post type {$si->object}\n"; $bad++; continue;
    }
    $ti = $target_archives[$si->object];
    $frozen = get_post_meta($ti->ID, "_menu_item_url", true);
    if ($frozen !== "") { echo "  archive item {$ti->ID} froze a source URL: $frozen\n"; $bad++; }
    if ($ti->url === "") { echo "  archive item {$ti->ID} resolves to no URL at all\n"; $bad++; continue; }

    // Only these are localized at all -- see the filter cited above.
    if (!PLL()->model->is_translated_post_type($si->object) || "post" === $si->object) { continue; }
    $localized++;
    PLL()->curlang = $dst_lang;
    $want_dst = get_post_type_archive_link($si->object);
    PLL()->curlang = $src_lang;
    $want_src = get_post_type_archive_link($si->object);
    PLL()->curlang = $dst_lang;
    if ($want_dst === $want_src) {
      echo "  Polylang did not localize the {$si->object} archive link at all ($want_dst); the premise for copying this item is false\n"; $bad++; continue;
    }
    if ($ti->url !== $want_dst) {
      echo "  archive item {$ti->ID} resolves to {$ti->url}, not the $dst link $want_dst\n"; $bad++; continue;
    }
    echo "  {$si->object} archive: $src -> $want_src, $dst -> {$ti->url}\n";
  }
}
echo "  checked $checked post_type_archive item(s), $localized of them localizable\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
if ($localized === 0) { echo "  FAIL: no localizable archive item checked; the localization claim went unverified\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: post_type_archive menu items did not survive translation"; exit 1; }

echo "── verify passes on a freshly imported site ──"
VERIFY_OUT="$(run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" 2>&1)" || {
  echo "$VERIFY_OUT"; echo "FAIL: verify rejected a site it should accept"; exit 1; }
echo "$VERIFY_OUT"

# An exit code alone would pass on a verifier that audited nothing. Assert the
# counts it reports are real.
V_POSTS="$(sed -n 's/.*posts=\([0-9]*\).*/\1/p' <<<"$VERIFY_OUT" | head -1)"
V_TERMS="$(sed -n 's/.*terms=\([0-9]*\).*/\1/p' <<<"$VERIFY_OUT" | head -1)"
[[ -n "$V_POSTS" && -n "$V_TERMS" ]] || { echo "FAIL: verify printed no audited counts"; exit 1; }
(( V_POSTS > 0 )) || { echo "FAIL: verify audited 0 posts — vacuous pass"; exit 1; }
echo "  verify audited $V_POSTS post(s), $V_TERMS term(s)"

echo "── verify catches a counterpart with no language ──"
# Exercises check 3 (the counterpart's language) IN ISOLATION. The victim is the
# fixture ATTACHMENT's counterpart, deliberately: no menu item points at an
# attachment, so check 1 cannot fire on it. The first version of this test broke
# a PAGE, and every page it could pick is a fixture page that a fixture menu
# item also points at -- so check 1 caught the breakage and the assertion still
# passed with check 3 deleted outright. An exit code says something failed, never
# WHICH check failed, so the check's own message is matched here.
#
# The victim is this run's own output, so nothing of the user's is touched.
# cleanup() restores it anyway (VERIFY_VICTIM below): a run that dies between the
# break and the repair would otherwise leave a language-less post behind, which
# is ruling T5-M's shape, and the restore is one line.
#
# Only the language taxonomy relationship is deleted; post_translations (the
# group) is a different taxonomy and is untouched, so pll_set_post_language()
# restores the original state exactly.
VICTIM="$(cd "$SITE" && PLL_MEDIA="$FIXTURE_MEDIA_ID" PLL_DST="$DST" wp eval '
$t   = pll_get_post_translations((int) getenv("PLL_MEDIA"));
$dst = getenv("PLL_DST");
echo empty($t[$dst]) ? "" : (int) $t[$dst];
' --allow-root)"
[[ -n "$VICTIM" ]] || { echo "FAIL: the fixture attachment has no $DST counterpart to break"; exit 1; }

# Armed before the break; cleared after the repair. cleanup() restores the
# language iff this is non-empty.
VERIFY_VICTIM="$VICTIM"
VERIFY_VICTIM_LANG="$DST"

# Break it the way a hand-edited database would: strip the language assignment.
(cd "$SITE" && PLL_VICTIM="$VICTIM" wp eval 'wp_delete_object_term_relationships((int) getenv("PLL_VICTIM"), "language");' --allow-root)

if VERIFY_BROKEN_OUT="$(run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" 2>&1)"; then
  echo "$VERIFY_BROKEN_OUT"
  echo "FAIL: verify accepted a post with no language"; exit 1
fi
grep -qF "post $VICTIM has language 'none', expected '$DST'" <<<"$VERIFY_BROKEN_OUT" || {
  echo "$VERIFY_BROKEN_OUT"
  echo "FAIL: verify rejected the site, but not with the counterpart-language check -- some other check fired, so that check is untested"
  exit 1
}
echo "  verify reported: $(grep -F "post $VICTIM has language" <<<"$VERIFY_BROKEN_OUT" | head -1)"

# Put it back so the suite is re-runnable.
(cd "$SITE" && PLL_VICTIM="$VICTIM" PLL_DST="$DST" wp eval 'pll_set_post_language((int) getenv("PLL_VICTIM"), getenv("PLL_DST"));' --allow-root)
VERIFY_VICTIM=""
run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" >/dev/null || { echo "FAIL: verify still failing after repair"; exit 1; }

echo "── verify catches a menu item pointing at the wrong language ──"
# Check 1 is the headline check of the verifier, and isolating check 3 above
# removed the accidental coverage it used to get: deleting check 1 entirely
# would otherwise leave this suite green. Re-point a TRANSLATED menu item at the
# SOURCE post it was translated from -- exactly what duplicating a menu by hand
# produces, and the breakage the verifier exists to catch first.
#
# No restore wiring: the item is the fixture's own, and cleanup() matches menu
# items by what they POINT AT against both the fixture posts and their
# counterparts, so it is deleted either way.
MENU_VICTIM="$(cd "$SITE" && PLL_DST="$DST" PLL_CHILD="$FIXTURE_CHILD_ID" wp eval '
$child = (int) getenv("PLL_CHILD"); $dst = getenv("PLL_DST");
$t = pll_get_post_translations($child);
if (empty($t[$dst])) { return; }
$target = (int) $t[$dst];
$opts = get_option("polylang"); $theme = get_stylesheet();
foreach ((array) ($opts["nav_menus"][$theme] ?? []) as $per) {
  if (empty($per[$dst])) { continue; }
  foreach ((array) wp_get_nav_menu_items((int) $per[$dst]) as $mi) {
    if ("post_type" === $mi->type && (int) $mi->object_id === $target) { echo (int) $mi->ID, " ", $target; return; }
  }
}
' --allow-root)"
[[ -n "$MENU_VICTIM" ]] || { echo "FAIL: no $DST menu item points at the fixture child page's counterpart"; exit 1; }
MENU_VICTIM_ITEM="${MENU_VICTIM% *}"
MENU_VICTIM_OBJ="${MENU_VICTIM#* }"

(cd "$SITE" && PLL_ITEM="$MENU_VICTIM_ITEM" PLL_OBJ="$FIXTURE_CHILD_ID" wp eval '
update_post_meta((int) getenv("PLL_ITEM"), "_menu_item_object_id", (int) getenv("PLL_OBJ"));
' --allow-root)

if MENU_BROKEN_OUT="$(run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" 2>&1)"; then
  echo "$MENU_BROKEN_OUT"
  echo "FAIL: verify accepted a $DST menu item pointing at a $SRC post"; exit 1
fi
grep -qF "points at a '$SRC' post ($FIXTURE_CHILD_ID)" <<<"$MENU_BROKEN_OUT" || {
  echo "$MENU_BROKEN_OUT"
  echo "FAIL: verify rejected the site, but not with the menu-item language check -- some other check fired, so that check is untested"
  exit 1
}
echo "  verify reported: $(grep -F "points at a '$SRC' post" <<<"$MENU_BROKEN_OUT" | head -1)"

(cd "$SITE" && PLL_ITEM="$MENU_VICTIM_ITEM" PLL_OBJ="$MENU_VICTIM_OBJ" wp eval '
update_post_meta((int) getenv("PLL_ITEM"), "_menu_item_object_id", (int) getenv("PLL_OBJ"));
' --allow-root)
run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" >/dev/null || { echo "FAIL: verify still failing after the menu item was re-pointed back"; exit 1; }

echo "── verify catches an internal link into the wrong language ──"
# Check 9 is the headline check of THIS task, and it had no test of its own:
# deleting the whole check left this suite green. Same reasoning as check 1
# above -- give the check the one condition it exists to catch, on the
# fixture's own counterpart, and require the verifier to name it.
#
# No restore wiring: the post carrying the bad href is the fixture's own
# counterpart, which cleanup() deletes on every path.
LINK_TARGET_ID="$(cd "$SITE" && PLL_CHILD="$FIXTURE_CHILD_ID" PLL_DST="$DST" wp eval '
$t = pll_get_post_translations((int) getenv("PLL_CHILD"));
echo empty($t[getenv("PLL_DST")]) ? "" : (int) $t[getenv("PLL_DST")];
' --allow-root)"
[[ -n "$LINK_TARGET_ID" ]] || { echo "FAIL: the fixture child page has no $DST counterpart to plant a link in"; exit 1; }

LINK_SRC_URL="$(cd "$SITE" && PLL_PARENT="$FIXTURE_PARENT_ID" wp eval '
echo get_permalink((int) getenv("PLL_PARENT"));
' --allow-root)"
[[ -n "$LINK_SRC_URL" ]] || { echo "FAIL: could not resolve the fixture parent page permalink"; exit 1; }

LINK_ORIG_CONTENT="$(cd "$SITE" && wp post get "$LINK_TARGET_ID" --field=post_content --allow-root)"
(cd "$SITE" && PLL_TID="$LINK_TARGET_ID" PLL_URL="$LINK_SRC_URL" wp eval '
wp_update_post(array("ID" => (int) getenv("PLL_TID"),
  "post_content" => "<p><a href=\"" . getenv("PLL_URL") . "\">volver</a></p>"));
' --allow-root >/dev/null)

if LINK_BROKEN_OUT="$(run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" 2>&1)"; then
  echo "$LINK_BROKEN_OUT"
  echo "FAIL: verify accepted a $DST post linking to a $SRC post"; exit 1
fi
grep -qF "links to a '$SRC' post ($FIXTURE_PARENT_ID) via an internal href" <<<"$LINK_BROKEN_OUT" || {
  echo "$LINK_BROKEN_OUT"
  echo "FAIL: verify rejected the site, but not with the internal-link check -- some other check fired, so check 9 is untested"
  exit 1
}
echo "  verify reported: $(grep -F "via an internal href" <<<"$LINK_BROKEN_OUT" | head -1)"

(cd "$SITE" && PLL_TID="$LINK_TARGET_ID" PLL_C="$LINK_ORIG_CONTENT" wp eval '
wp_update_post(array("ID" => (int) getenv("PLL_TID"), "post_content" => (string) getenv("PLL_C")));
' --allow-root >/dev/null)
run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" >/dev/null || { echo "FAIL: verify still failing after the planted link was removed"; exit 1; }

echo "── verify catches a custom menu item pointing at the wrong language ──"
# Check 1's 'custom' branch is new in Task 9 and had no test either: removing
# it left the suite green. A custom item carries a literal href instead of an
# object id, which is exactly what a hand-duplicated menu produces -- the Task
# 7 finding this branch exists to close.
CUSTOM_MENU_ID="$(cd "$SITE" && PLL_SRC_MENU="$FIXTURE_MENU_ID" PLL_SRC="$SRC" PLL_DST="$DST" wp eval '
$src_menu = (int) getenv("PLL_SRC_MENU"); $src = getenv("PLL_SRC"); $dst = getenv("PLL_DST");
$opts = get_option("polylang"); $theme = get_stylesheet();
foreach ((array) ($opts["nav_menus"][$theme] ?? []) as $per) {
  if (!is_array($per) || empty($per[$dst])) { continue; }
  if ($src_menu && (int) ($per[$src] ?? 0) !== $src_menu) { continue; }
  echo (int) $per[$dst]; return;
}
' --allow-root)"
[[ -n "$CUSTOM_MENU_ID" ]] || { echo "FAIL: no $DST menu is paired with the fixture's source menu"; exit 1; }

CUSTOM_ITEM_ID="$(cd "$SITE" && PLL_MENU="$CUSTOM_MENU_ID" PLL_URL="$LINK_SRC_URL" wp eval '
echo (int) wp_update_nav_menu_item((int) getenv("PLL_MENU"), 0, array(
  "menu-item-type"   => "custom",
  "menu-item-url"    => getenv("PLL_URL"),
  "menu-item-title"  => "PLL fixture custom link",
  "menu-item-status" => "publish",
));
' --allow-root)"
[[ "$CUSTOM_ITEM_ID" =~ ^[0-9]+$ && "$CUSTOM_ITEM_ID" -gt 0 ]] || { echo "FAIL: could not create the custom menu item"; exit 1; }
# Registered with the fixture's own item ids so cleanup() hard-deletes it on
# every path: a custom item has no object id, so the point-at matching in
# cleanup() cannot find it.
FIXTURE_ITEM_IDS="${FIXTURE_ITEM_IDS:+$FIXTURE_ITEM_IDS,}$CUSTOM_ITEM_ID"

if CUSTOM_BROKEN_OUT="$(run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" 2>&1)"; then
  echo "$CUSTOM_BROKEN_OUT"
  echo "FAIL: verify accepted a $DST custom menu item pointing at a $SRC post"; exit 1
fi
grep -qF "(custom URL) points at a '$SRC' post ($FIXTURE_PARENT_ID)" <<<"$CUSTOM_BROKEN_OUT" || {
  echo "$CUSTOM_BROKEN_OUT"
  echo "FAIL: verify rejected the site, but not with the custom-menu-item check -- some other check fired, so that branch is untested"
  exit 1
}
echo "  verify reported: $(grep -F "(custom URL) points at" <<<"$CUSTOM_BROKEN_OUT" | head -1)"

(cd "$SITE" && wp post delete "$CUSTOM_ITEM_ID" --force --allow-root >/dev/null)
run "$SCRIPTS/pll-verify.php" "$SRC" "$DST" >/dev/null || { echo "FAIL: verify still failing after the custom menu item was removed"; exit 1; }

echo "── remove this run's fixture ──"
# Deletion, not a re-run of export+import. The teardown used to resync by
# exporting and importing again with NO translation step in between, which
# wrote the SOURCE-language titles straight into the translated menu -- the
# suite's own teardown left the site serving an untranslated English menu.
# Dropping the fixture-derived items is all that was ever needed, and
# cleanup() does exactly that. It is idempotent and still trapped on EXIT, so
# calling it here only moves it ahead of the PASS line.
cleanup
trap - EXIT

# ── Task 8: ACF/SCF field-type coverage ─────────────────────────────────────
# Everything below runs AFTER trap - EXIT, i.e. with no cleanup-on-failure
# protection (see the file header). That is deliberate here, not an oversight:
# unlike every fixture above, the "PLL ACF fixture" page and its field group
# (wp-content/mu-plugins/pll-acf-fixture.php on $SITE) are a PERMANENT fixture
# kept on purpose (Task 8 ruling T8-A/Step 7), not something this run created
# and must remove. There is nothing here for a trap to tear down.
#
# Guarded so the suite still passes on a site with no custom-fields plugin:
# get_field() existing at all is the only signal this block depends on.
SKIPPED=""

if (cd "$SITE" && wp eval 'exit(function_exists("get_field") ? 0 : 1);' --allow-root); then
  echo "── ACF: every translatable field type round-trips ──"

  # FIXTURE_TMPDIR no longer exists -- cleanup() above already removed it.
  # This block has no trap protection (see the file header note reproduced
  # above), so its own temp dir is removed explicitly at the end of the
  # success path; a failure path below leaves it for post-mortem inspection.
  ACF_TMPDIR="$(mktemp -d)"

  # Looked up by slug, not a hardcoded post ID: the mu-plugin's field-group
  # location rule hardcodes this site's ID (595 at the time this was written),
  # but a DB rebuild that recreates the page under a different ID must not
  # silently turn this whole block into a no-op.
  ACF_FIXTURE_ID="$(cd "$SITE" && wp post list --post_type=page --name=pll-acf-fixture --field=ID --allow-root)"
  [[ -n "$ACF_FIXTURE_ID" ]] || { echo "FAIL: SCF is active but the 'PLL ACF fixture' page is missing -- Task 8 keeps it permanently, see pll-acf-fixture.php in the site's mu-plugins"; exit 1; }

  ACF_TARGET_ID="$(cd "$SITE" && PLL_FID="$ACF_FIXTURE_ID" PLL_DST="$DST" wp eval '
  $t = pll_get_post_translations((int) getenv("PLL_FID"));
  $dst = getenv("PLL_DST");
  echo empty($t[$dst]) ? "" : (int) $t[$dst];
  ' --allow-root)"

  if [[ -z "$ACF_TARGET_ID" ]]; then
    # First run ever against this site: no counterpart exists yet. One plain
    # export/import pass creates it so the sentinel-seeding step below always
    # has a target post to seed. Every subsequent run skips straight past this.
    ACF_BOOT_MAN="$ACF_TMPDIR/acf-bootstrap.json"
    run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$ACF_BOOT_MAN" >/dev/null
    php -r '
    $m = json_decode(file_get_contents($argv[1]), true);
    $fid = (int) $argv[2];
    $kept = array();
    foreach ($m["items"] as $it) {
      if (($it["kind"] ?? "") === "post" && (int) ($it["source_id"] ?? 0) === $fid) { $kept[] = $it; }
    }
    if (count($kept) !== 1) {
      fwrite(STDERR, "FAIL: expected exactly 1 bootstrap item for the ACF fixture, found ".count($kept)."\n");
      exit(1);
    }
    $m["items"] = $kept;
    file_put_contents($argv[1], json_encode($m, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
    ' "$ACF_BOOT_MAN" "$ACF_FIXTURE_ID" || exit 1
    run "$SCRIPTS/pll-import.php" "$ACF_BOOT_MAN" >/dev/null || { echo "FAIL: bootstrap import for the ACF fixture failed"; exit 1; }
    ACF_TARGET_ID="$(cd "$SITE" && PLL_FID="$ACF_FIXTURE_ID" PLL_DST="$DST" wp eval '
    $t = pll_get_post_translations((int) getenv("PLL_FID"));
    echo empty($t[getenv("PLL_DST")]) ? "" : (int) $t[getenv("PLL_DST")];
    ' --allow-root)"
    [[ -n "$ACF_TARGET_ID" ]] || { echo "FAIL: bootstrap import did not create a $DST counterpart for the ACF fixture"; exit 1; }
  fi

  echo "  fixture page: $SRC=$ACF_FIXTURE_ID, $DST=$ACF_TARGET_ID"

  # Task 9 (ruling T9-E): the permanent reference target for pll_link,
  # pll_page_link, pll_post_object and pll_relationship. Looked up by slug
  # for the same reason as ACF_FIXTURE_ID above. This pair is set up once,
  # by hand, on the test site -- see pll-acf-fixture.php's header comment --
  # and is never created or removed by this script.
  REF_SRC_ID="$(cd "$SITE" && wp post list --post_type=page --name=pll-acf-ref-target --field=ID --allow-root)"
  [[ -n "$REF_SRC_ID" ]] || { echo "FAIL: SCF is active but the 'PLL ACF ref target' fixture page is missing -- Task 9 (ruling T9-E) keeps it permanently, see pll-acf-fixture.php in the site's mu-plugins"; exit 1; }
  REF_EN_ID="$(cd "$SITE" && PLL_RID="$REF_SRC_ID" wp eval '
  $t = pll_get_post_translations((int) getenv("PLL_RID"));
  echo empty($t["en"]) ? "" : (int) $t["en"];
  ' --allow-root)"
  [[ -n "$REF_EN_ID" ]] || { echo "FAIL: the 'PLL ACF ref target' fixture page has no en counterpart"; exit 1; }
  REF_EN_PERMALINK="$(cd "$SITE" && PLL_RID="$REF_EN_ID" wp eval 'echo get_permalink((int) getenv("PLL_RID"));' --allow-root)"
  [[ -n "$REF_EN_PERMALINK" ]] || { echo "FAIL: could not read the ref-target en permalink"; exit 1; }
  echo "  ref target: es=$REF_SRC_ID, en=$REF_EN_ID"

  # Seed the TARGET's negative-control fields with values that DIFFER from the
  # source's, and force the export to see this post as stale. Without this,
  # "unchanged after import" would be trivially true (the fields were simply
  # never written) instead of proving the importer actively leaves someone
  # else's already-different data alone, and a site where nothing looks stale
  # would export zero items, making every assertion below pass vacuously.
  (cd "$SITE" && PLL_TID="$ACF_TARGET_ID" PLL_REF_SRC="$REF_SRC_ID" wp eval '
  $id      = (int) getenv("PLL_TID");
  $ref_src = (int) getenv("PLL_REF_SRC");
  update_field("pll_number", -1, $id);
  update_field("pll_true_false", 0, $id);
  update_field("pll_url", "https://example.com/target-sentinel", $id);
  update_field("pll_image", 80, $id);
  // Task 9 (ruling T9-E): stage the four reference fields pointing at the
  // SOURCE-language ref target, exactly what a naive verbatim copy (or a
  // prior run, before this pass existed) would leave behind. The assertions
  // after import prove the pass re-points every one of them to the en
  // counterpart -- without this staging step "re-pointed after import"
  // would be trivially true only because nothing was ever wrong to begin
  // with, the same vacuous-pass shape the sentinel seeding above exists to
  // avoid for the negative controls.
  update_field("pll_link", array("title" => "stale title", "url" => get_permalink($ref_src), "target" => ""), $id);
  update_field("pll_page_link", get_permalink($ref_src), $id);
  update_field("pll_post_object", $ref_src, $id);
  update_field("pll_relationship", array($ref_src), $id);
  // Clear the target\x27s repeater and flexible-content rows so every run
  // exercises the FIRST-WRITE path, where pllx_acf_write() has to build a row
  // from nothing. Without this the rows survive from the previous run, the
  // importer only ever overwrites one key inside an existing row, and the
  // flexible-content assertions below cannot fail: neutralising the
  // acf_fc_layout backfill in pll-import.php still leaves this suite green,
  // because the layout tag it exists to restore was never missing. Measured --
  // with the rows dropped first, the same mutation FAILS with "flexible-content
  // row count changed across the round trip (0 rows)".
  delete_field("pll_repeater", $id);
  delete_field("pll_flex", $id);
  delete_post_meta($id, "_pll_src_hash");
  ' --allow-root)

  ACF_MAN="$ACF_TMPDIR/acf-manifest.json"
  run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$ACF_MAN" >/dev/null || { echo "FAIL: ACF export exited non-zero"; exit 1; }

  # Keep ONLY the fixture's own item. The export walks the whole site, so
  # without this filter the manifest also carries the site's real menu --
  # importing that would rewrite the site's own 2 menus, which this suite must
  # never do outside the dedicated fixture-menu blocks above.
  php -r '
  $m = json_decode(file_get_contents($argv[1]), true);
  $fid = (int) $argv[2];
  $kept = array();
  foreach ($m["items"] as $it) {
    if (($it["kind"] ?? "") === "post" && (int) ($it["source_id"] ?? 0) === $fid) { $kept[] = $it; }
  }
  if (count($kept) !== 1) {
    fwrite(STDERR, "FAIL: expected exactly 1 ACF fixture item in the export, found ".count($kept)."\n");
    exit(1);
  }
  $acf = $kept[0]["acf"] ?? array();
  $n = count($acf);
  if ($n <= 0) {
    fwrite(STDERR, "FAIL: no acf keys exported at all -- the assertions below would have passed vacuously\n");
    exit(1);
  }
  $expected = array(
    "pll_text", "pll_textarea", "pll_wysiwyg",
    "pll_group.pll_group_text",
    "pll_repeater.0.pll_rep_text", "pll_repeater.0.pll_rep_textarea",
    "pll_repeater.1.pll_rep_text", "pll_repeater.1.pll_rep_textarea",
    "pll_flex.0.flex_a_text", "pll_flex.1.flex_b_text",
    "pll_link.title",
  );
  $missing = array_diff($expected, array_keys($acf));
  if ($missing) {
    fwrite(STDERR, "FAIL: export is missing expected acf key(s): ".implode(", ", $missing)."\n");
    exit(1);
  }
  // pll_link.url, pll_page_link, pll_post_object and pll_relationship are
  // references, not translatable text -- Task 9 (ruling T9-E) re-points them
  // in the link-rewrite pass instead, so none of them may ever appear here.
  $forbidden = array(
    "pll_number", "pll_true_false", "pll_url", "pll_image",
    "pll_flex.0.acf_fc_layout", "pll_flex.1.acf_fc_layout",
    "pll_link.url", "pll_link.target", "pll_page_link", "pll_post_object", "pll_relationship",
  );
  $leaked = array_intersect($forbidden, array_keys($acf));
  if ($leaked) {
    fwrite(STDERR, "FAIL: export leaked a non-translatable key into acf: ".implode(", ", $leaked)."\n");
    exit(1);
  }
  echo "  exported acf keys: $n (".count($expected)." expected present, ".count($forbidden)." forbidden confirmed absent)\n";
  $m["items"] = $kept;
  file_put_contents($argv[1], json_encode($m, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
  ' "$ACF_MAN" "$ACF_FIXTURE_ID" || exit 1

  # Translate mechanically -- same convention as the rest of this suite.
  php -r '
  $m = json_decode(file_get_contents($argv[1]), true);
  foreach ($m["items"] as &$it) {
    foreach ($it["fields"] as $k => $v) {
      if ($k === "post_name" || $k === "slug") { continue; }
      if (is_string($v) && $v !== "") { $it["fields"][$k] = "[" . strtoupper($argv[2]) . "] " . $v; }
    }
    foreach ($it["acf"] as $k => $v) {
      $it["acf"][$k] = "[" . strtoupper($argv[2]) . "] " . $v;
    }
  }
  unset($it);
  file_put_contents($argv[1], json_encode($m, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
  ' "$ACF_MAN" "$DST"

  run "$SCRIPTS/pll-import.php" "$ACF_MAN" >/dev/null || { echo "FAIL: ACF import exited non-zero"; exit 1; }

  ACF_RESULT="$(cd "$SITE" && PLL_TID="$ACF_TARGET_ID" wp eval '
  $id = (int) getenv("PLL_TID");
  echo json_encode(get_field_objects($id), JSON_UNESCAPED_UNICODE);
  ' --allow-root)"

  php -r '
  $o = json_decode($argv[1], true);
  if (!is_array($o) || !count($o)) { fwrite(STDERR, "FAIL: get_field_objects() on the target returned nothing\n"); exit(1); }

  $checks = 0;
  function pll_check(&$checks, $cond, $msg) {
    $checks++;
    if (!$cond) { fwrite(STDERR, "FAIL: $msg\n"); exit(1); }
  }

  pll_check($checks, ($o["pll_text"]["value"] ?? null) === "[EN] Texto simple en espanol", "pll_text did not round-trip translated");
  pll_check($checks, ($o["pll_textarea"]["value"] ?? null) === "[EN] Area de texto en espanol", "pll_textarea did not round-trip translated");
  pll_check($checks, strpos($o["pll_wysiwyg"]["value"] ?? "", "[EN]") !== false, "pll_wysiwyg did not round-trip translated");
  pll_check($checks, ($o["pll_group"]["value"]["pll_group_text"] ?? null) === "[EN] Texto dentro de un grupo", "group sub-field did not round-trip translated");

  // Guarded with is_array(), not just ??: a field that failed to save can come
  // back as an explicit `false` value rather than a missing key, and count()
  // on that throws instead of failing the assertion with a readable message.
  $rep = $o["pll_repeater"]["value"] ?? array();
  if ( ! is_array( $rep ) ) { $rep = array(); }
  pll_check($checks, count($rep) === 2, "repeater row count changed across the round trip (".count($rep)." rows)");
  pll_check($checks, ($rep[0]["pll_rep_text"] ?? null) === "[EN] Fila uno texto", "repeater row 0 text did not round-trip translated");
  pll_check($checks, ($rep[0]["pll_rep_textarea"] ?? null) === "[EN] Fila uno area de texto", "repeater row 0 textarea did not round-trip translated");
  pll_check($checks, ($rep[1]["pll_rep_text"] ?? null) === "[EN] Fila dos texto", "repeater row 1 text did not round-trip translated");
  pll_check($checks, ($rep[1]["pll_rep_textarea"] ?? null) === "[EN] Fila dos area de texto", "repeater row 1 textarea did not round-trip translated");

  $flex = $o["pll_flex"]["value"] ?? array();
  if ( ! is_array( $flex ) ) { $flex = array(); }
  pll_check($checks, count($flex) === 2, "flexible-content row count changed across the round trip (".count($flex)." rows)");
  pll_check($checks, ($flex[0]["acf_fc_layout"] ?? null) === "layout_a", "flexible-content row 0 lost its acf_fc_layout");
  pll_check($checks, ($flex[0]["flex_a_text"] ?? null) === "[EN] Texto de diseno A", "flexible-content row 0 text did not round-trip translated");
  pll_check($checks, ($flex[1]["acf_fc_layout"] ?? null) === "layout_b", "flexible-content row 1 lost its acf_fc_layout");
  pll_check($checks, ($flex[1]["flex_b_text"] ?? null) === "[EN] Texto de diseno B", "flexible-content row 1 text did not round-trip translated");

  pll_check($checks, (int) ($o["pll_number"]["value"] ?? null) === -1, "negative control pll_number was altered by the import");
  pll_check($checks, ($o["pll_true_false"]["value"] ?? null) === false, "negative control pll_true_false was altered by the import");
  pll_check($checks, ($o["pll_url"]["value"] ?? null) === "https://example.com/target-sentinel", "negative control pll_url was altered by the import");
  pll_check($checks, (int) ($o["pll_image"]["value"] ?? null) === 80, "negative control pll_image was altered by the import");

  // Task 9 (ruling T9-E): the four reference fields were staged above
  // pointing at the SOURCE-language ref target -- prove the link-rewrite
  // pass re-pointed every one of them to the en counterpart, and that the
  // link field title (translatable text, routed through the manifest like
  // any other text field) round-tripped independently of its url.
  $ref_en       = (int) $argv[2];
  $ref_en_perm  = $argv[3];
  pll_check($checks, ($o["pll_link"]["value"]["url"] ?? null) === $ref_en_perm, "link field url was not re-pointed to the en ref target (got " . ($o["pll_link"]["value"]["url"] ?? "null") . ")");
  pll_check($checks, strpos($o["pll_link"]["value"]["title"] ?? "", "[EN]") !== false, "link field title did not round-trip translated");
  pll_check($checks, ($o["pll_page_link"]["value"] ?? null) === $ref_en_perm, "page_link field was not re-pointed to the en ref target (got " . ($o["pll_page_link"]["value"] ?? "null") . ")");
  pll_check($checks, (int) ($o["pll_post_object"]["value"] ?? 0) === $ref_en, "post_object field was not re-pointed to the en ref target (got " . ($o["pll_post_object"]["value"] ?? "null") . ")");
  $rel = $o["pll_relationship"]["value"] ?? array();
  if (!is_array($rel)) { $rel = array(); }
  pll_check($checks, in_array($ref_en, array_map("intval", $rel), true), "relationship field was not re-pointed to the en ref target (got " . json_encode($rel) . ")");

  echo "  round-trip checks passed: $checks\n";
  ' "$ACF_RESULT" "$REF_EN_ID" "$REF_EN_PERMALINK" || exit 1

  # The SOURCE post itself must never be mutated by any of the above -- not
  # by the export (read-only, but worth confirming) and not by the importer
  # writing into the wrong post_id by mistake.
  ACF_SOURCE_STILL="$(cd "$SITE" && PLL_FID="$ACF_FIXTURE_ID" wp eval '
  $id = (int) getenv("PLL_FID");
  echo json_encode(array(
    "text"   => get_field("pll_text", $id),
    "number" => get_field("pll_number", $id),
    "bool"   => get_field("pll_true_false", $id),
    "url"    => get_field("pll_url", $id),
    "image"  => get_field("pll_image", $id),
  ));
  ' --allow-root)"
  php -r '
  $s = json_decode($argv[1], true);
  $n = 0;
  if (($s["text"] ?? null) === "Texto simple en espanol") { $n++; } else { fwrite(STDERR, "FAIL: source pll_text was mutated\n"); exit(1); }
  if ((int) ($s["number"] ?? -999) === 42) { $n++; } else { fwrite(STDERR, "FAIL: source pll_number was mutated\n"); exit(1); }
  if (($s["bool"] ?? null) === true) { $n++; } else { fwrite(STDERR, "FAIL: source pll_true_false was mutated\n"); exit(1); }
  if (($s["url"] ?? null) === "https://example.com/no-traducir") { $n++; } else { fwrite(STDERR, "FAIL: source pll_url was mutated\n"); exit(1); }
  if ((int) ($s["image"] ?? -1) === 85) { $n++; } else { fwrite(STDERR, "FAIL: source pll_image was mutated\n"); exit(1); }
  if ($n <= 0) { fwrite(STDERR, "FAIL: no negative controls were checked at all -- the assertions above would have passed vacuously\n"); exit(1); }
  echo "  negative controls confirmed unaltered (source and target): $n source + 4 target\n";
  ' "$ACF_SOURCE_STILL" || exit 1

  rm -rf "$ACF_TMPDIR"
else
  echo "  (skipping ACF assertions: no custom-fields plugin active)"
  SKIPPED="${SKIPPED:+$SKIPPED, }ACF"
fi

if [[ -n "${SKIPPED:-}" ]]; then
  echo "PASS (skipped: $SKIPPED)"
else
  echo "PASS"
fi
