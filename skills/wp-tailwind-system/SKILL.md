---
name: wp-tailwind-system
description: Tailwind CSS conventions for themes built from the __tailwind__ starter — the decision ladder for utilities vs @apply, @theme tokens, file placement, and what is forbidden. Applies to template=tailwind only.
---

# WP Tailwind System

Applies when the project's `.claude/CLAUDE.md` says `Template: tailwind`. For
`template=basic`, use `wp-css-system` instead — the two are mutually exclusive.

## Decision ladder

Applied per element, in order. Stop at the first rung that holds.

1. **Tailwind utility classes in the markup.** The default, always. A section
   whose styling is expressible as utilities produces no CSS file entry at all.
2. **Same utility group on ≥2 pages** → semantic class in `utilities/site.css`,
   defined with `@apply`.
3. **Repeated within a single page only** → semantic class in
   `components/<slug>.css`, defined with `@apply`.
4. **Raw CSS** (no `@apply`) only for what Tailwind cannot express: `@keyframes`,
   `clip-path`, exotic selectors, third-party plugin overrides.

"Repeated" means the same group appears 3+ times, or on 2+ distinct pages. A
group used twice inside one section stays inline.

## File layout

Only these four directories exist under `assets/css/src/tailwindcss/`. Never
create a new directory.

```
main.css                  @import "tailwindcss"; @plugin; @theme{…}; then the @import list
base/                     resets and font-face
components/<slug>.css     one per page/template: home, contacto, servicios, 404, search, blog
components/buttons.css    shared components
layouts/                  header, footer, sidebar — only when a layout needs @apply rules
utilities/site.css        utility groups repeated across ≥2 pages
utilities/wordpress.css   WordPress core class overrides
utilities/animations.css  animation helpers
```

## Never create an empty file

A `.css` file exists only once it holds **at least one rule**. Write the rule and
the file in the same step, and add its `@import` to `main.css` in that same step.
Never scaffold a file "to fill in later" — that is the exact bug this convention
replaced.

Import order in `main.css`: `base` → `components` → `layouts` → `utilities`.

## Tokens

Colors and fonts live in the `@theme` block of `main.css`, injected by `/wp-init`:

```css
@theme {
  --color-primary: #3b82f6;
  --font-primary: "Inter", sans-serif;
}
```

Reference them as utilities — `bg-primary`, `text-primary`, `font-primary`. Never
redeclare a token in a `:root` block, and never hardcode a hex value that a token
already covers.

## Responsive

Mobile-first, using Tailwind's own prefixes. Never write a media query by hand.

```html
<div class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3 lg:gap-8">
```

## `@apply` idiom

```css
/* components/home.css */
.home-hero {
  @apply relative flex min-h-screen items-center justify-center bg-dark text-light;
}

.home-hero__title {
  @apply text-4xl font-bold tracking-tight md:text-6xl;
}
```

The class name still scopes under the section's `--block` name so parallel
section agents cannot collide on a selector.

## Forbidden

- `assets/css/styles.css` — that is the `template=basic` output surface. Never write it.
- BEM-with-custom-properties authoring (`.block__element` + `var(--x)` from `:root`). That is `wp-css-system`'s job, not this one.
- A `:root { --… }` block. Tokens belong in `@theme`.
- Any new directory under `assets/css/src/tailwindcss/`.
- An empty or comment-only `.css` file.
- A `<style>` block or a static `style=""` attribute in a PHP template. (Dynamic
  values driven by an ACF field — e.g. a background image URL — are the one
  exception.)
- Hand-written `@media` queries.

## Verify

```bash
bin/tailwind-native-check.sh <theme-dir>
```
