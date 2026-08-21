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

echo "── seed a real post_type menu item + a parent/child pair for this run ──"
# This site's real menu is 4 "custom" and 8 "taxonomy" items -- zero
# "post_type" items, so the re-pointing this whole task exists for would
# otherwise never run. Add one: a temporary child page, parented to an
# existing untranslated page (also exercising the parent-child fixup with a
# real, non-zero case), linked into the registered menu location. Both are
# translated by the same import as everything else below -- posts/terms are
# exported/imported before the menu (see pll-export.php/pll-import.php
# ordering), so the child's target counterpart exists by the time the menu
# item is re-pointed. Cleaned up at the very end of this file.
FIXTURE_PARENT_ID="$(cd "$SITE" && PLL_FIX_SRC="$SRC" PLL_FIX_DST="$DST" wp eval '
$src = getenv("PLL_FIX_SRC"); $dst = getenv("PLL_FIX_DST");
foreach (get_posts(["post_type"=>"page","numberposts"=>-1,"post_status"=>"publish","fields"=>"ids"]) as $id) {
  if (pll_get_post_language($id) !== $src) continue;
  $t = pll_get_post_translations($id);
  if (empty($t[$dst])) { echo $id; exit; }
}
' --allow-root)"
[[ -n "$FIXTURE_PARENT_ID" ]] || { echo "FAIL: could not find an untranslated page to parent the menu fixture to"; exit 1; }

FIXTURE_CHILD_ID="$(cd "$SITE" && wp post create --post_type=page --post_title="PLL menu fixture page" --post_status=publish --post_parent="$FIXTURE_PARENT_ID" --porcelain --allow-root)"
[[ -n "$FIXTURE_CHILD_ID" ]] || { echo "FAIL: could not create the menu fixture page"; exit 1; }
(cd "$SITE" && PLL_FIX_SRC="$SRC" PLL_FIX_CHILD="$FIXTURE_CHILD_ID" wp eval '
pll_set_post_language( (int) getenv("PLL_FIX_CHILD"), getenv("PLL_FIX_SRC") );
' --allow-root) >/dev/null

FIXTURE_MENU_ID="$(cd "$SITE" && wp eval '
$regs = array_keys(get_registered_nav_menus());
$locs = get_nav_menu_locations();
foreach ($regs as $loc) { if (!empty($locs[$loc])) { echo (int) $locs[$loc]; exit; } }
' --allow-root)"
[[ -n "$FIXTURE_MENU_ID" ]] || { echo "FAIL: no registered menu location has an assigned menu to fixture into"; exit 1; }

FIXTURE_ITEM_ID="$(cd "$SITE" && wp menu item add-post "$FIXTURE_MENU_ID" "$FIXTURE_CHILD_ID" --title="PLL menu fixture page" --porcelain --allow-root)"
[[ -n "$FIXTURE_ITEM_ID" ]] || { echo "FAIL: could not add the fixture page to the source menu"; exit 1; }

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

echo "── clean up the menu/parent-child fixture ──"
(cd "$SITE" && PLL_FIX_CHILD="$FIXTURE_CHILD_ID" PLL_FIX_ITEM="$FIXTURE_ITEM_ID" PLL_FIX_DST="$DST" wp eval '
$child = (int) getenv("PLL_FIX_CHILD");
$dst   = getenv("PLL_FIX_DST");
$t = pll_get_post_translations($child);
if (!empty($t[$dst])) { wp_delete_post((int) $t[$dst], true); }
wp_delete_post($child, true);
wp_delete_post((int) getenv("PLL_FIX_ITEM"), true);
' --allow-root) >/dev/null

# The target menu still mirrors the just-deleted item -- the importer only
# rebuilds a target menu when it runs. Re-run the real export/import once
# more (now that the fixture item is gone, the menu's item set -- and so its
# stored hash -- has genuinely changed) so the site's final state has no
# trace of this fixture, matching one clean suite run.
RESYNC_MAN="$(mktemp)"
run "$SCRIPTS/pll-export.php" "$SRC" "$DST" "$RESYNC_MAN" >/dev/null
run "$SCRIPTS/pll-import.php" "$RESYNC_MAN" >/dev/null || { echo "FAIL: post-fixture resync import exited non-zero"; exit 1; }
rm -f "$RESYNC_MAN"

echo PASS
