---
description: Translate an existing WordPress site into a second language using Polylang
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
argument-hint: "<source_lang> <target_lang>"
---

# /wp-polylang

Translate an existing site into a second language through Polylang. Run from the
WordPress root.

**Required skill:** read `skills/wp-polylang/SKILL.md` before doing anything. It
documents the data model and the API contract, and the failure mode this command
exists to avoid.

## Step 1: Parse arguments

`$ARGUMENTS` is `<source_lang> <target_lang>`, e.g. `es en`. Both are required;
error and exit if either is missing:

```
Error: source and target language are required.
Usage: /wp-polylang <source_lang> <target_lang>
```

One target language per run. For a third language, run the command again.

Confirm the working directory is a WordPress root — `wp-config.php` must be
present. If it is not, stop and say so.

Set `SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/wp-polylang/scripts"`.

## Step 2: Ensure Polylang is installed

```bash
# Three states, not two: active, installed-but-deactivated, absent. `install` on an
# already-installed plugin is not a reliable activator, so try activation first.
wp plugin is-active polylang \
  || wp plugin activate polylang \
  || wp plugin install polylang --activate
```

## Step 3: Configure languages

```bash
wp eval-file "$SCRIPTS/pll-setup.php" <source_lang> <target_lang>
```

Creates whichever of the two languages Polylang does not already have configured,
using a sane predefined locale (`en` → `en_US`, `es` → `es_ES`, not Polylang's own
first-match, which is `en_AU` / `es_AR`). Succeeds silently — and prints
"Configured languages: …" either way — when both languages already exist, so it is
always safe to run.

Stop if it exits non-zero — it prints exactly what is wrong (Polylang not active,
an unrecognised language code, or source and target being the same language).

## Step 4: Export what needs translating

```bash
MANIFEST="$(mktemp -t pll-manifest-XXXXXX.json)"
wp eval-file "$SCRIPTS/pll-export.php" <source_lang> <target_lang> "$MANIFEST"
```

Walks every translatable post type and taxonomy — posts, terms, registered
strings, and per-language menus — and writes only what is missing or stale into
`$MANIFEST`. Prints `Exported <n> item(s), skipped <n> already current.` Read the
reported item count **and the unassigned-language warning**, if any.

Zero items has two very different meanings and they must not be conflated:

- 0 items and 0 unassigned: the site is already current. Report that and skip to Step 7.
- 0 items with unassigned objects reported: nothing was exported because the content has
  no language assigned at all. That is not "already current", it is "nothing was
  translatable". Report the unassigned counts verbatim and say the site needs its source
  language assigned before this command can do anything. Do not report success.

## Step 5: Translate

Read `$MANIFEST`. Write `$MANIFEST.translated` with the **same structure**,
replacing only the values inside each item's `fields` and `acf`.

Rules:

- Leave `id`, `hash`, `kind`, `source_id`, `target_id`, `post_type`, `taxonomy`,
  `location` and `menu_id` exactly as they are. `pll-import.php` matches on them
  and rejects the file if they drift.
- Translate `post_title`, `post_content`, `post_excerpt`, term `name` and
  `description`, menu item labels (`item_<db_id>` keys), and string values.
- Translate slugs too — `post_name` and term `slug`. `/servicios/` becomes
  `/services/`. Use lowercase words joined by hyphens, no accents.
- Preserve HTML structure inside `post_content`. Translate the text between
  tags, never the tags, attributes, shortcode names or URLs.
- Leave a value unchanged when it is a proper noun or a brand name.
- Never invent content. If a source value is empty, the translation is empty.

Write the file as UTF-8 JSON.

## Step 6: Import

```bash
wp eval-file "$SCRIPTS/pll-import.php" "$MANIFEST.translated"
```

Takes a single argument — the translated manifest; source and target language
come from the manifest itself. Validates the whole file before writing anything.
If it reports validation errors, fix the translated manifest and run it again —
nothing was written.

Prints `Wrote <n> item(s): <n> post(s), <n> attachment(s), <n> term(s), <n>
string(s).` and `Fixed <n> parent-child relationship(s).`

## Step 7: Verify

```bash
wp eval-file "$SCRIPTS/pll-verify.php" <source_lang> <target_lang>
```

Prints `Audited posts=<n> terms=<n> menu_items=<n> unassigned=<n> for <source> ->
<target>`, then either every failure (exit 1) or `PASS — 0 failures, <n>
warning(s).` (exit 0).

If it exits non-zero, report every failure verbatim. Do not describe the run as
successful when the verifier rejected it.

Warnings are not failures. "Same title as its source" is expected for brand
names and short labels.

## Step 8: Report

```
Polylang translation: <source> -> <target>

  Exported:    <n> item(s)
  Written:     <n> item(s)
  Verifier:    PASS (<n> warning(s))

  Posts:       <n>
  Terms:       <n>
  Menu items:  <n>

<any verifier warnings, verbatim>
```

Delete the manifest files when the run succeeds; keep them when it fails, and
say where they are.

## Notes

- Re-running is safe and cheap: unchanged content is skipped by hash, so a
  second run costs no tokens for anything already current.
- A run interrupted part way is resumed by running the command again. Hashes are
  recorded only after successful writes.
- WooCommerce products and their attribute taxonomies translate with free
  Polylang. The paid addon is only needed for cart, checkout and account page
  mapping, which this command does not touch.
