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
FIXTURE_MEDIA_FILE=""
FIXTURE_ITEM_IDS=""
FIXTURE_MENU_ID=""
FIXTURE_ARCHIVE_PT=""

cleanup() {
  local status=$?
  if [[ -n "$FIXTURE_MEDIA_FILE" ]]; then rm -f "$FIXTURE_MEDIA_FILE"; fi
  (cd "$SITE" \
    && PLL_FIX_POSTS="$FIXTURE_PARENT_ID,$FIXTURE_CHILD_ID,$FIXTURE_MEDIA_ID" \
       PLL_FIX_ITEMS="$FIXTURE_ITEM_IDS" \
       PLL_FIX_MENU="$FIXTURE_MENU_ID" \
       PLL_FIX_PT="$FIXTURE_ARCHIVE_PT" \
       wp eval '
$posts      = array_filter( array_map( "intval", explode( ",", (string) getenv( "PLL_FIX_POSTS" ) ) ) );
$items      = array_filter( array_map( "intval", explode( ",", (string) getenv( "PLL_FIX_ITEMS" ) ) ) );
$src_menu   = (int) getenv( "PLL_FIX_MENU" );
$archive_pt = (string) getenv( "PLL_FIX_PT" );

// Counterparts first, while the translation groups still exist.
$all = $posts;
foreach ( $posts as $id ) {
  foreach ( (array) pll_get_post_translations( $id ) as $tid ) { $all[] = (int) $tid; }
}
$all = array_values( array_unique( array_filter( $all ) ) );

// Menu items are matched by what they POINT AT, in every menu, because the
// importer mints the target menu ids itself -- this script never sees them.
// The archive item has no object id to match on, so it is identified by its
// post type, in menus other than the source one; the fixture refuses to run
// (above) if the source menu already had such an item, which is what makes
// that safe.
foreach ( (array) wp_get_nav_menus() as $menu ) {
  foreach ( (array) wp_get_nav_menu_items( $menu->term_id, array( "post_status" => "any" ) ) as $mi ) {
    $fixture_post    = ( "post_type" === $mi->type && in_array( (int) $mi->object_id, $all, true ) );
    $fixture_archive = ( "post_type_archive" === $mi->type && "" !== $archive_pt
                         && $mi->object === $archive_pt && (int) $menu->term_id !== $src_menu );
    if ( $fixture_post || $fixture_archive ) { wp_delete_post( (int) $mi->ID, true ); }
  }
}
// ...and the remembered source-menu ids, which also covers an item whose
// target post a previous partial cleanup already removed.
foreach ( $items as $iid ) { wp_delete_post( $iid, true ); }
foreach ( $all as $id ) { wp_delete_post( $id, true ); }

// A failure between adding the temporary "fr" language and removing it again
// would otherwise leave it behind and break every later run.
$fr = PLL()->model->get_language( "fr" );
if ( $fr ) {
  foreach ( get_posts( array( "post_type" => "any", "numberposts" => -1, "post_status" => "any", "fields" => "ids" ) ) as $pid ) {
    if ( pll_get_post_language( $pid ) === "fr" ) { wp_delete_post( $pid, true ); }
  }
  foreach ( array_keys( PLL()->model->get_translated_taxonomies() ) as $tax ) {
    $terms = get_terms( array( "taxonomy" => $tax, "hide_empty" => false ) );
    if ( is_wp_error( $terms ) ) { continue; }
    foreach ( $terms as $term ) {
      if ( pll_get_term_language( $term->term_id ) === "fr" ) { wp_delete_term( $term->term_id, $tax ); }
    }
  }
  PLL()->model->languages->delete( $fr->term_id );
}
' --allow-root) >/dev/null 2>&1 || true
  return $status
}

# The menu to fixture into must be the SOURCE-language one. Polylang's own
# per-language record is authoritative; the bare location is only accepted once
# it is confirmed not to be recorded as some other language's menu, since
# get_nav_menu_locations() also carries Polylang's synthetic `loc___lang` keys.
FIXTURE_MENU_ID="$(cd "$SITE" && PLL_FIX_SRC="$SRC" wp eval '
$src    = getenv("PLL_FIX_SRC");
$theme  = get_stylesheet();
$opts   = get_option("polylang");
$assign = isset($opts["nav_menus"][$theme]) ? $opts["nav_menus"][$theme] : [];
$locs   = get_nav_menu_locations();
foreach (array_keys(get_registered_nav_menus()) as $loc) {
  $per = isset($assign[$loc]) ? $assign[$loc] : [];
  if (!empty($per[$src])) { echo (int) $per[$src]; exit; }
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

FIXTURE_ARCHIVE_PT="$(cd "$SITE" && wp eval '
foreach (get_post_types(["public"=>true], "objects") as $pt) {
  if (!$pt->has_archive) { continue; }
  echo $pt->name; exit;
}
' --allow-root)"
[[ -n "$FIXTURE_ARCHIVE_PT" ]] || { echo "FAIL: no public post type has an archive to build a post_type_archive menu item from"; exit 1; }

if ! (cd "$SITE" && PLL_FIX_MENU="$FIXTURE_MENU_ID" PLL_FIX_PT="$FIXTURE_ARCHIVE_PT" wp eval '
foreach ((array) wp_get_nav_menu_items((int) getenv("PLL_FIX_MENU")) as $mi) {
  if ("post_type_archive" === $mi->type && $mi->object === getenv("PLL_FIX_PT")) { exit(1); }
}
' --allow-root); then
  echo "FAIL: the $SRC menu already has a post_type_archive item for '$FIXTURE_ARCHIVE_PT'; the fixture assumes it is the only source of one so that cleanup can identify its mirror in the translated menu"
  exit 1
fi

FIXTURE_PARENT_ID="$(cd "$SITE" && wp post create --post_type=page --post_title="PLL fixture parent page" --post_status=publish --porcelain --allow-root)"
trap cleanup EXIT
[[ -n "$FIXTURE_PARENT_ID" ]] || { echo "FAIL: could not create the fixture parent page"; exit 1; }

FIXTURE_CHILD_ID="$(cd "$SITE" && wp post create --post_type=page --post_title="PLL fixture child page" --post_status=publish --post_parent="$FIXTURE_PARENT_ID" --porcelain --allow-root)"
[[ -n "$FIXTURE_CHILD_ID" ]] || { echo "FAIL: could not create the fixture child page"; exit 1; }

# A real file, imported through WordPress, so the counterpart's
# _wp_attached_file linkage can be asserted for real further down.
FIXTURE_MEDIA_FILE="$(mktemp --suffix=.png)"
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

FIXTURE_ITEM_ARCHIVE="$(cd "$SITE" && PLL_FIX_MENU="$FIXTURE_MENU_ID" PLL_FIX_PT="$FIXTURE_ARCHIVE_PT" wp eval '
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

echo "  menu $FIXTURE_MENU_ID: pages $FIXTURE_PARENT_ID/$FIXTURE_CHILD_ID, media $FIXTURE_MEDIA_ID, items $FIXTURE_ITEM_IDS ($FIXTURE_ARCHIVE_PT archive)"

echo "── export produces a valid manifest ──"
MAN="$(mktemp)"
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
MAN2="$(mktemp)"
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
foreach ($m as $row) {
  $s = (int) $row[1]; $w = (int) $row[2]; $sk = (int) $row[3];
  echo "  source=$s written=$w skipped=$sk\n";
  if ($s === 0) { fwrite(STDERR, "FAIL: reconciliation reports a 0-item source menu\n"); exit(1); }
  // Floor, not just the sum. written+skipped==source is satisfied by every
  // path in the importer loop by construction -- each one bumps exactly one
  // counter -- so on its own it can never fail. A menu that skipped ALL of its
  // items would still balance perfectly while producing an empty translated
  // menu, and only this line catches that.
  if ($w === 0) { fwrite(STDERR, "FAIL: reconciliation wrote 0 of $s source item(s)\n"); exit(1); }
  if ($w + $sk !== $s) { fwrite(STDERR, "FAIL: written($w) + skipped($sk) != source($s)\n"); exit(1); }
}
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

echo "── re-export after import is empty (idempotent) ──"
MAN3="$(mktemp)"
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
# Uses a temporary 'fr' language and cleans it up (and the post it created)
# afterward so this is safe to re-run against a persistent site.
run "$SCRIPTS/pll-setup.php" "$SRC" fr >/dev/null || { echo "FAIL: could not add temporary language fr"; exit 1; }

THIRD_MAN="$(mktemp)"
THIRD_SRC_ID="$(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" PLL_CHK_MAN="$THIRD_MAN" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$src_id = null;
foreach (get_posts(["post_type"=>"page","numberposts"=>-1,"post_status"=>"any","fields"=>"ids"]) as $id) {
  if (pll_get_post_language($id) !== $src) continue;
  $t = pll_get_post_translations($id);
  if (!empty($t[$dst])) { $src_id = $id; break; }
}
if (!$src_id) { fwrite(STDERR, "no source page with a target-language counterpart found\n"); exit(1); }
$manifest = array(
  "source_lang" => $src,
  "target_lang" => "fr",
  "site_url"    => home_url(),
  "items"       => array( array(
    "id"        => "post:$src_id",
    "kind"      => "post",
    "post_type" => "page",
    "source_id" => (int) $src_id,
    "target_id" => null,
    "hash"      => str_repeat("f", 64),
    "fields"    => array("post_title" => "[FR] third language test"),
    "acf"       => array(),
  ) ),
);
file_put_contents(getenv("PLL_CHK_MAN"), json_encode($manifest));
echo $src_id;
' --allow-root)" || { echo "FAIL: could not build the third-language fixture"; exit 1; }

run "$SCRIPTS/pll-import.php" "$THIRD_MAN" >/dev/null || { echo "FAIL: import for a third language exited non-zero"; exit 1; }

(cd "$SITE" && PLL_CHK_SRC_ID="$THIRD_SRC_ID" PLL_CHK_DST="$DST" wp eval '
$src_id = (int) getenv("PLL_CHK_SRC_ID"); $dst = getenv("PLL_CHK_DST");
$t = pll_get_post_translations($src_id);
if (empty($t[$dst])) { echo "  pre-existing $dst counterpart was dropped from the group: " . json_encode($t) . "\n"; exit(1); }
if (empty($t["fr"])) { echo "  fr counterpart missing from the group: " . json_encode($t) . "\n"; exit(1); }
echo "  group after adding fr: " . json_encode($t) . "\n";
exit(0);
' --allow-root) || { echo "FAIL: third-language import destroyed the existing translation group"; exit 1; }

# Clean up the scaffolding: delete the fr post, any terms Polylang
# auto-duplicated into fr (e.g. the default category -- add_language()
# duplicates default terms into every translated taxonomy, and
# languages->delete() only unlinks the language, it does not remove those
# term rows), and the temporary language itself, so re-running this suite
# against the same site starts from the same state.
(cd "$SITE" && PLL_CHK_SRC_ID="$THIRD_SRC_ID" wp eval '
$src_id = (int) getenv("PLL_CHK_SRC_ID");
$t = pll_get_post_translations($src_id);
if (!empty($t["fr"])) { wp_delete_post((int) $t["fr"], true); }

foreach ( array_keys( PLL()->model->get_translated_taxonomies() ) as $tax ) {
  $terms = get_terms( array( "taxonomy" => $tax, "hide_empty" => false ) );
  if ( is_wp_error( $terms ) ) { continue; }
  foreach ( $terms as $term ) {
    if ( pll_get_term_language( $term->term_id ) === "fr" ) {
      wp_delete_term( $term->term_id, $tax );
    }
  }
}

$lang = PLL()->model->get_language("fr");
if ($lang) { PLL()->model->languages->delete($lang->term_id); }
' --allow-root) >/dev/null
rm -f "$THIRD_MAN"

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

echo "── post_type_archive menu items are copied, not dropped ──"
# An archive item is keyed by a post type slug, so there is no per-language
# object to re-point it at -- but it does not need one. wp_setup_nav_menu_item()
# resolves the URL at RENDER time via get_post_type_archive_link(), and
# Polylang localizes that against the current language (measured on this site,
# Polylang 3.8.7 / force_lang=1: /tienda/ with curlang=es, /en/tienda/ with
# curlang=en). So the item must be COPIED. Skipping it deletes a working nav
# entry from every translated menu; copying $mi->url instead would freeze the
# SOURCE permalink into the translated menu, which is why _menu_item_url is
# asserted empty here.
(cd "$SITE" && PLL_CHK_SRC="$SRC" PLL_CHK_DST="$DST" wp eval '
$src = getenv("PLL_CHK_SRC"); $dst = getenv("PLL_CHK_DST");
$opts = get_option("polylang"); $theme = get_stylesheet();
$locs = $opts["nav_menus"][$theme] ?? [];
if (!$locs) { echo "  no per-language menu assignments recorded\n"; exit(1); }
$bad = 0; $checked = 0;
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
    if ($ti->url === "") { echo "  archive item {$ti->ID} resolves to no URL at all\n"; $bad++; }
  }
}
echo "  checked $checked post_type_archive item(s)\n";
if ($checked === 0) { echo "  FAIL: assertion checked nothing\n"; exit(1); }
exit($bad === 0 ? 0 : 1);
' --allow-root) || { echo "FAIL: post_type_archive menu items did not survive translation"; exit 1; }

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

echo PASS
