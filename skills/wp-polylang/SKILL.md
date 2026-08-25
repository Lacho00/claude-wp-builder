---
name: wp-polylang
description: Polylang multilingual methodology — one post per language joined by translation groups, driven through the pll_* API
user-invocable: false
---

# Polylang Multilingual System

This skill documents how to drive Polylang correctly from automation. It is the
alternative to `wp-bilingual`, which documents the ACF `_suffix` pattern. The two
are mutually exclusive per project: `_suffix` keeps one post with `hero_title`
and `hero_title_es`; Polylang keeps one post per language, each with the same
unsuffixed fields, joined into a translation group.

`wp-bilingual` remains the default. Choosing Polylang does not deprecate it.

## Data model

Polylang stores two things per translatable object:

| What | Where |
|---|---|
| The object's language | the `language` taxonomy (`term_language` for terms) |
| Which objects are translations of each other | the `post_translations` taxonomy (`term_translations` for terms) |

A translation group is a single term whose description holds a serialised map of
`lang => object_id`. Both taxonomies must agree. **Writing either one directly is
the mistake this document exists to prevent** — a group written by hand is
routinely asymmetric, and Polylang then reports the page as untranslated while
the database looks correct.

Always go through the API:

| Task | Call |
|---|---|
| Set a post's language | `pll_set_post_language( $post_id, $lang )` |
| Join posts as translations | `pll_save_post_translations( [ 'es' => 12, 'en' => 34 ] )` |
| Read a post's group | `pll_get_post_translations( $post_id )` |
| Set a term's language | `pll_set_term_language( $term_id, $lang )` |
| Join terms as translations | `pll_save_term_translations( [ 'es' => 5, 'en' => 9 ] )` |
| List configured languages | `pll_languages_list()` |
| Default language | `pll_default_language()` |

`pll_save_post_translations()` **replaces** the whole group rather than merging
into it — it is not a delta call. Passing only `{source, target}` silently drops
every other language already in that group, including languages the array
never mentions. The correct pattern is to read the existing group first with
`pll_get_post_translations()`, merge the source and target ids into it, and
save the merged result:

```php
$group = pll_get_post_translations( $source_id );
$group[ $source ] = $source_id;
$group[ $target ] = $target_id;
pll_save_post_translations( $group );
```

Same shape for terms with `pll_get_term_translations()` /
`pll_save_term_translations()`. `create_media_translation()` is the one
exception — it merges internally, so it does not need this pattern.

## Running PHP against a site

No `wp pll` command is available, so automation runs through `wp eval-file`:

```bash
wp eval-file script.php es en
```

- Positional arguments arrive as `$args`. `--flags` are **not** available; WP-CLI
  consumes those itself.
- The file is evaluated as real PHP source, so quoting is not a hazard the way it
  is with `wp eval "..."`.
- `__DIR__` resolves to the script's own directory despite the `eval()` wrapper,
  so scripts can `require_once __DIR__ . '/pll-lib.php'`.

## Menus

Per-language menu assignment lives in the `polylang` option, not in theme mods:

```php
$options = get_option( 'polylang' );
$options['nav_menus'][ $theme_slug ][ $location ][ $lang ] = $menu_term_id;
update_option( 'polylang', $options );
```

`combine_location()` (public instance method on `PLL_Nav_Menu`, inherited by
`PLL_Admin_Nav_Menu`) composes the synthetic `location___lang` key the admin UI
and the frontend use. It is a naming helper, not a storage API — Polylang reads
the option path above directly at `src/admin/admin-nav-menu.php:279`.

A translated menu whose items still point at source-language objects is the most
common Polylang misconfiguration, and it is invisible until a visitor clicks and
lands in the wrong language. Re-point every item with
`pll_get_post_translations()`.

## What free Polylang covers

Verified on Polylang 3.8.7 with no paid addon: `product` is translatable as a
post type, and `product_cat`, `product_tag`, `product_brand` and the `pa_*`
attribute taxonomies are all translatable. Product *content* needs no addon.

What does need the paid Polylang for WooCommerce addon is the runtime plumbing —
per-language cart, checkout and account page mapping, product variations, WC
emails. That is not content and is out of scope for content translation.

## ACF / SCF custom fields

`pllx_acf_payload()` in `pll-lib.php` flattens a post's custom-field values to a
dot-notation map (`pllx_acf_walk()`); `pllx_acf_write()` in `pll-import.php`
writes that map back through `update_field()`/`get_field()`. Both work against
whatever plugin defines `get_field_objects()`, `get_field()` and
`update_field()` — that is ACF or SCF, never both (see below).

**Translated** (the value is walked, sent through translation, written back):

| Field type | Key shape |
|---|---|
| `text`, `textarea`, `wysiwyg` | `name` |
| `group` (one level) | `group_name.sub_name` |
| `repeater` (one level) | `repeater_name.ROW_INDEX.sub_name` |
| `flexible_content` (one level) | `flex_name.ROW_INDEX.sub_name` |

A `flexible_content` row's own `acf_fc_layout` tag is never emitted as a
translatable key — it is a machine identifier, not text — but the importer
still needs it to write a valid row. A row the target already has keeps its
existing tag untouched by the read-modify-write; a row being created for the
first time (a brand-new translation counterpart) gets it backfilled from the
corresponding row on the *source* post, since that's the only other place
that still identifies the row's layout. Without this, a fresh flexible-content
row written through the same dot-notation path as a repeater row is invalid
and SCF/ACF silently drops the whole field — this was measured, not assumed
(see `tests/checks/wp-polylang-live.sh` and the Task 8 report in
`.superpowers/sdd/2026-08-21-wp-polylang-retrofit/`).

**Copied verbatim, never translated** (present in the field group, absent
from the dot-notation map, untouched by the importer): `image`, `number`,
`true_false`, `url`, and any other type not listed above.

**`clone` fields are deliberately never walked as their own type.** With the
default *seamless* display, a clone's sub-fields surface as ordinary siblings
under their own names in `get_field_objects()` and are already covered by the
branches above — walking `clone` too would re-emit the same value under a
second key. With *group* display, `get_field_objects()` returns the clone as
a **second** object (type `clone`) whose value duplicates the original
field's, backed by the same underlying meta; walking that would emit the same
text twice under two different dotted keys, and writing both back
independently risks the second write clobbering the first with a different
translation. Both shapes were probed live before reaching this conclusion —
adding a `clone` branch would open the exact "translate the same thing twice
and let the last write win" defect class this plan exists to close, not
prevent it.

**Ceiling:** one level of nesting inside `group`, `repeater` and
`flexible_content` — a group nested inside a repeater or a flexible-content
layout is not walked. Widen `pllx_acf_walk()` if a project needs more.

Verified against **Secure Custom Fields (SCF) 6.9.5** — the free,
wordpress.org fork that ships `repeater`, `group`, `flexible_content` and
`clone`, which ACF sells as PRO. ACF's free tier has none of those four types
and exposes the rest of this surface (`text`, `textarea`, `wysiwyg`, plain
`group`, plain `repeater`) through the identical API, so passing against SCF
implies passing against ACF free. ACF PRO was not available to test against
(no licence). **ACF and SCF cannot both be active** — both define
`get_field()`, `get_field_objects()` and `update_field()`, and activating the
second one over the first fatals the site. Install exactly one.

## Strings

`pll_register_string()` registers a string for translation, but only the theme or
plugin that owns a string can register it. Polylang itself registers four strings
under the `WordPress` context: `blogname`, `blogdescription`, `date_format`, and
`time_format`. Empty values are absent from the table, so a site with no tagline
shows three entries instead of four.

The `date_format` and `time_format` options contain PHP date formats, not prose.
The Spanish-locale default for `date_format` is `j \d\e F \d\e Y`; English-locale
is `F j, Y`. Translating these produces garbage. Exclude them by comparing against
`get_option('date_format')` and `get_option('time_format')` rather than by
guessing at their shape.

Theme strings written as `__()` / `_e()` are **gettext**, a different mechanism
entirely, translated through `.po`/`.mo` files and not through Polylang's string
table. Do not conflate the two.

## Activation behaviour

Activating Polylang assigns a default language only to the post types and
taxonomies that were already registered as translatable **at that moment**. A
post type or taxonomy enabled for translation later (a common retrofit step —
e.g. turning on `product`/`product_cat` after the plugin has been running for
a while) keeps every one of its existing objects with **no language assigned
at all**. `pll_get_post_language()` / `pll_get_term_language()` return `false`
for them, not the default language.

This matters for automation: a query filtered by `'lang' => $source` silently
excludes objects with no language — they never enter the result set, so
nothing downstream can see, count, or warn about them. Verified live on
Polylang 3.8.7: a WooCommerce catalogue (7 products, 9 `product_cat` terms)
enabled after initial activation had zero objects assigned any language,
while `post`/`page`/`attachment`/`category` — all present at activation —
were fully tagged. Anything that walks a site to find translatable content
must query without a `lang` filter, classify each object's language itself,
and count and report what has none — never assume "activated" means
"assigned everywhere."

On a site being retrofitted, the work is therefore not just creating
counterparts and joining them into groups — it may also require assigning a
source language to content Polylang never touched in the first place.
