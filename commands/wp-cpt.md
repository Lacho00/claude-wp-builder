---
description: Custom post type builder — registers a CPT and generates its fields, archive, single, optional teaser query-section, and seed helper
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
argument-hint: "<name> [--no-teaser] [--from-demo <section-name>]"
---

# WP CPT — Custom Post Type Builder

Register a custom post type and generate everything it needs: registration, ACF fields bound to the type, archive + single templates, an optional home/teaser query-section, and a seed helper.

## Step 1: Parse Arguments
- **First word** = CPT name, singular lowercase (e.g., `team`, `service`, `project`). Required.
- `--no-teaser` = skip the teaser query-section.
- `--from-demo <section-name>` = read field/seed hints from that section in `demo/index.html`.

If no name: print usage error and exit.

## Step 2: Read Project Context
Read `.claude/CLAUDE.md` for function prefix, theme slug, languages, theme directory. If missing, tell the user to run `/wp-init` first and exit.

## Step 3: Register the CPT and generate fields (parallel)

Dispatch **wp-template** agent:

> Generate `inc/post-types/<name>.php`:
> - `register_post_type( '<name>', [...] )` hooked on `init` via `add_action`
> - Labels for singular/plural (primary language from CLAUDE.md)
> - `'public' => true`, `'has_archive' => true`, `'menu_icon'` (choose a dashicon fitting the noun),
>   `'supports' => ['title','editor','thumbnail']`, `'rewrite' => ['slug' => '<name>']`
> - Escaping on labels; text domain = theme slug
> Then ensure `functions.php` `require`s every file in `inc/post-types/` (add a glob-require loop if not present).

Dispatch **wp-acf** agent:

> Generate `fields/<name>.php`:
> - Field group bound with location rule `post_type == <name>`
> - Fields inferred from the demo card (or `--from-demo` section): image (photo/thumbnail),
>   text (name/title — usually the post title, skip if so), text (role/subtitle), textarea/wysiwyg (bio/description),
>   repeater (socials: platform + url) when present
> - Bilingual variants per `wp-bilingual` when languages has a secondary
> - Group key: `group_<name>`

## Step 4: Archive and single templates

Dispatch **wp-template** agent:

> Generate `archive-<name>.php`:
> - `get_header()`, archive intro/title, grid loop over the main query rendering each item as a card
>   (reuse `template-parts/<name>/card.php`), `the_posts_pagination()`, `get_footer()`
> Generate `single-<name>.php`:
> - `get_header()`, item detail rendered from the CPT ACF fields via `prefix_get_field()`,
>   `get_footer()`, BEM classes `.<name>-single__*`
> Generate `template-parts/<name>/card.php`:
> - Single card markup shared by archive + teaser: thumbnail, title (`get_the_title()`),
>   role, excerpt/bio; permalink via `get_permalink()`

Dispatch **wp-css** agent:

> Add `.<name>-archive`, `.<name>-card`, `.<name>-single` CSS within delimiters using design tokens.

## Step 5: Teaser query-section (unless --no-teaser)

Dispatch **wp-template** + **wp-acf** + **wp-css** (mirror the /wp-section flow):

> `template-parts/section-<name>.php`:
> - `WP_Query( ['post_type' => '<name>', 'posts_per_page' => N, 'orderby' => 'menu_order'] )`
> - Section chrome from ACF: `prefix_get_field('<name>_heading')`, intro, button label
> - Render N cards via `template-parts/<name>/card.php`
> - "Show more" button → `get_post_type_archive_link('<name>')`
> `fields/section-<name>.php`: chrome-only ACF group (heading, intro, button_label) — NOT the items
> Inject `get_template_part('template-parts/section', '<name>')` into `front-page.php` at the sections placeholder.

## Step 6: Seed helper

Append to the theme's seed routine (or emit `inc/seed/<name>.php`) WP-CLI calls to create N `<name>` posts
from the demo cards / detail pages: `wp post create --post_type=<name> --post_title='...' --porcelain`,
then set ACF fields and sideload the card image into the media library and set the thumbnail.
Primary language only; flag secondary.

## Step 7: Print Summary
List every file created and the registered post type, archive URL, and seed count.
