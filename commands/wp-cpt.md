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

### CSS agent routing

Read `Template:` from `.claude/CLAUDE.md`. When `Template:` is `tailwind`, dispatch
`wp-tailwind`; when it is `basic`, dispatch `wp-css`.

- `basic` → dispatch `wp-css` exactly as described below.
- `tailwind` → dispatch `wp-tailwind` in **author** mode instead, passing the CPT name
  (which selects `components/<name>.css`) and the block name. The agent reads
  `skills/wp-tailwind-system/SKILL.md` for the decision ladder. It writes utility
  classes into the markup and only adds `@apply` rules where the ladder demands
  them. It must never write `assets/css/styles.css`.

Dispatch exactly one of the two, never both.

This routing governs every "Dispatch **wp-css** agent" step below (the archive/single/card
CSS in Step 4, and the teaser section in Step 5) — each one marks its `tailwind`
counterpart with `(routed — see "CSS agent routing" above)` rather than repeating the
block.

Routing matters here because `--from-demo` reads `demo/index.html`, and on the `tailwind`
path `/wp-yolo` Step 4 item 2 runs `/wp-cpt` *after* Step 2.6 has converted that file in
place. The markup this command reads is already Tailwind-native; building its CSS through
`wp-css` would leak plain CSS straight into `front-page.php` via the teaser.

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

Dispatch **wp-css** agent (routed — see "CSS agent routing" above; on `tailwind`, dispatch `wp-tailwind` in author mode instead):

> Add `.<name>-archive`, `.<name>-card`, `.<name>-single` CSS within delimiters using design tokens.

## Step 5: Teaser query-section (unless --no-teaser)

Dispatch **wp-template** + **wp-acf** + **wp-css** (mirror the /wp-section flow; the CSS agent is routed — see "CSS agent routing" above; on `tailwind`, dispatch `wp-tailwind` in author mode instead):

> `template-parts/section-<name>.php`:
> - `WP_Query( ['post_type' => '<name>', 'posts_per_page' => N, 'orderby' => 'menu_order'] )`
> - Section chrome from ACF: `prefix_get_field('<name>_heading')`, intro, button label
> - Render N cards via `template-parts/<name>/card.php`
> - "Show more" button → `get_post_type_archive_link('<name>')`
> `fields/section-<name>.php`: chrome-only ACF group (heading, intro, button_label) — NOT the items
> Inject `get_template_part('template-parts/section', '<name>')` into `front-page.php` at the sections placeholder.

## Step 6: Seed helper

**Always emit `inc/seed/<name>.php`** — a single runnable seeder that creates the N `<name>`
posts from the demo cards / detail pages. It must be executable standalone via the project's
WP-CLI wrapper (`$WP eval-file inc/seed/<name>.php`) so a later `/wp-yolo` Phase 3 (or a
manual run) can create the posts deterministically. For each post: create it
(`wp_insert_post` with `post_type => '<name>'`), set its ACF fields, and sideload the card
image (`media_sideload_image`) into the media library and set it as the thumbnail.
Make it idempotent where practical (skip if a post with the same title already exists).
Primary language only; flag secondary.

## Step 7: Print Summary
List every file created and the registered post type, archive URL, and seed count.
