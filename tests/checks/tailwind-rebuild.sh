#!/usr/bin/env bash
# functions.php enqueues only the compiled assets/css/dist/main.css. Every command that
# writes utility classes into templates must recompile it before reporting done, or the
# live site (and /wp-yolo's parity gate) shows the CSS built at /wp-init time — no sections.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "FAIL: $*"; exit 1; }
b=bin/tailwind-rebuild.sh

[ -x "$b" ] || fail "$b missing or not executable"
grep -Fq 'npm run --silent tailwindbuild' "$b" || fail "$b does not run tailwindbuild"
grep -Fq -- 'tailwindcss.*--watch' "$b" || fail "$b does not detect a running watcher"
grep -Fq '/proc/$1/cwd' "$b" || fail "$b matches watchers globally — one in another theme would suppress this theme's build"
grep -Fq 'exit 0' "$b" || fail "$b has no silent exit for non-Tailwind themes"

# behavior: non-tailwind dir → silent success
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
out=$(bash "$b" "$tmp") && [ -z "$out" ] || fail "$b is not a silent no-op on a non-Tailwind theme (out: $out)"

# behavior: tailwind theme with a fake npm on PATH → calls tailwindbuild, not build
mkdir -p "$tmp/t/assets/css/src/tailwindcss" "$tmp/t/node_modules" "$tmp/fakebin"
echo '{}' > "$tmp/t/package.json"
printf '#!/usr/bin/env bash\necho "npm $*" >> "%s/npm.log"\n' "$tmp" > "$tmp/fakebin/npm"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/fakebin/pgrep"   # pretend no watcher
chmod +x "$tmp/fakebin/npm" "$tmp/fakebin/pgrep"
PATH="$tmp/fakebin:$PATH" bash "$b" "$tmp/t" >/dev/null
grep -Fq 'run --silent tailwindbuild' "$tmp/npm.log" || fail "$b did not invoke npm run tailwindbuild on a Tailwind theme"
! grep -Eq 'run( --silent)? build$' "$tmp/npm.log" || fail "$b ran the full build script instead of tailwindbuild"

# behavior: a watcher running in ANOTHER directory must not suppress this theme's build
if [ -d /proc/self ]; then
  mkdir -p "$tmp/other"
  (cd "$tmp/other" && exec -a 'tailwindcss -i x -o y --watch' sleep 30) & other=$!
  (cd "$tmp/t"     && exec -a 'tailwindcss -i x -o y --watch' sleep 30) & mine=$!
  sleep 0.2
  printf '#!/usr/bin/env bash\necho %s\n' "$other" > "$tmp/fakebin/pgrep"
  : > "$tmp/npm.log"
  PATH="$tmp/fakebin:$PATH" bash "$b" "$tmp/t" >/dev/null
  grep -Fq 'tailwindbuild' "$tmp/npm.log" || { kill $other $mine; fail "$b skipped the build because of a watcher in a different theme"; }
  printf '#!/usr/bin/env bash\necho %s\n' "$mine" > "$tmp/fakebin/pgrep"
  : > "$tmp/npm.log"
  out=$(PATH="$tmp/fakebin:$PATH" bash "$b" "$tmp/t")
  kill $other $mine 2>/dev/null; wait $other $mine 2>/dev/null || true
  [ ! -s "$tmp/npm.log" ] && grep -Fq 'skipping build' <<<"$out" \
    || fail "$b rebuilt over a watcher that owns this theme's dist/"
fi

# every builder that writes template classes calls it before its summary
for c in wp-section wp-header wp-footer wp-page wp-cpt; do
  f=commands/$c.md
  grep -Fq 'bin/tailwind-rebuild.sh' "$f" || fail "$f never recompiles Tailwind after authoring"
  awk '/tailwind-rebuild.sh/{seen=1} /^## Step [0-9.]+: Print Summary/{ if(!seen){exit 1} }' "$f" \
    || fail "$f rebuilds after Print Summary — the report would list files the browser cannot see yet"
done

# /wp-yolo: once, before finalize / responsive-check / the parity gate
f=commands/wp-yolo.md
grep -Fq 'bin/tailwind-rebuild.sh' "$f" || fail "$f never recompiles Tailwind before its gate"
awk '/tailwind-rebuild.sh/{seen=1} /^\*\*`\/wp-responsive-check`\*\*|^[0-9]+\. \*\*`\/wp-responsive-check`\*\*/{ if(!seen){exit 1} }' "$f" \
  || fail "$f runs /wp-responsive-check before rebuilding Tailwind"
grep -Fq 'parity' "$f" || fail "$f lost its parity gate"

# /wp-init tells the user how to see the site live
grep -Fq 'npm run preview' commands/wp-init.md || fail "wp-init no longer mentions npm run preview"
grep -Eqi 'second terminal|keep it running' commands/wp-init.md || fail "wp-init does not say to keep npm run preview running while building"

echo PASS
