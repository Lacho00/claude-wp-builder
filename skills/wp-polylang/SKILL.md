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
