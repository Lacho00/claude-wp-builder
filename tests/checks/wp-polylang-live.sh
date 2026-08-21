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
  if (!in_array($it["kind"], ["post","term","string"], true)) {
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

echo PASS
