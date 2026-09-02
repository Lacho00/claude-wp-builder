---
name: wp-tailwind-system
description: Tailwind CSS conventions for themes built from the __tailwind__ starter — the decision ladder for utilities vs @apply, @theme tokens, file placement, and what is forbidden. Applies to template=tailwind only.
user-invocable: false
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

Exactly four directories are sanctioned under `assets/css/src/tailwindcss/`:
`base`, `components`, `layouts`, `utilities`. Never create a fifth.

The four are not all present in a fresh theme. Git cannot track an empty
directory, so the starter ships only the ones that already hold a file —
`layouts/` in particular is absent until something writes into it. Any of the
four may be created when the first rule that belongs there is written, in the
same step as that rule. Creating one of the four is not creating a new
directory; a fifth name is, whatever it holds.

```
main.css                  @import "tailwindcss"; @plugin; @theme{…}; then the @import list
base/                     resets and font-face
components/<slug>.css     one per page/template: home, contact, services, 404, search, blog
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

### Name the breakpoints; never ship `max-[<n>px]:`

A demo converted from a design tool carries media queries at the FRAME widths it was
drawn at — 1599, 1023, 759 — and none of those is a default Tailwind stop. Translating
each one literally gives `max-[1599px]:`, `max-[1023px]:`, `max-[759px]:`, hundreds of
them, and that is a defect, not a detail:

- **It breaks anything the scanner cannot see.** Tailwind compiles a variant only while
  some scanned file uses it. Markup that lives in the DATABASE — a CF7 form, a widget, a
  block pattern — silently loses every rule the day the theme normalizes its variants.
  (This has shipped: a footer form lost its whole responsive layout that way.)
- **Each pair leaves a 1px dead band.** `max-[759px]` and a `min-width: 760px` rule agree
  only by luck; the arbitrary form invites off-by-one boundaries nobody re-checks.
- It is unreadable, and it makes every future width change a find-and-replace.

So: take the widths the demo actually switches at, declare them ONCE in `@theme`, and use
the named prefixes everywhere.

```css
@theme {
  --breakpoint-sm:  430px;
  --breakpoint-md:  760px;
  --breakpoint-lg: 1024px;
  --breakpoint-xl: 1281px;
  --breakpoint-3xl: 1600px;
}
```

```html
<!-- wrong -->
<div class="max-[1023px]:col-span-full max-[759px]:pt-5">
<!-- right: max-lg = below 1024, max-md = below 760 -->
<div class="max-lg:col-span-full max-md:pt-5">
```

Mind the boundary when converting: `max-[759px]` is `≤ 759`, and `max-md` with
`--breakpoint-md: 760px` is `< 760`. Same rule. Re-measure at the stop itself after the
change — an off-by-one here moves a whole layout one pixel early.

An arbitrary variant is acceptable only for a one-off width that is genuinely not a
breakpoint of the design (a single `max-[891px]:` where one field wraps). If it appears
more than twice, it is a breakpoint: name it.

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

## Preflight

`@import "tailwindcss"` brings Preflight, Tailwind's own reset. It replaces the
browser's default stylesheet, so a theme whose every declaration was
translated correctly still does not render like the plain-CSS demo it came
from. Measured in a browser at six widths, on a faithful conversion of a
three-page demo:

| Element | Browser default | Under Preflight | Measured effect |
|---|---|---|---|
| `<button>` | `Arial 13.33px`, normal | inherits — `system-ui 16px/25.6px` | nav toggle grew |
| `<img>` | `display:inline; max-width:none` | `display:block; max-width:100%` | service card 197.9px → 190.7px |
| `<p>` | UA margin `14.4px` | `margin: 0` | footer column 71.04px → 56.8px |
| `<a>` | `text-decoration: underline` | `none` | logo link lost its underline |
| page | — | — | total height 1130.21px → 1108.78px |

Two consequences:

1. Where the demo leaned on a UA default, re-add it explicitly as a utility on
   the element — `inline`, `max-w-none`, `my-[0.9em]`, `underline`. The demo
   never declared these, so nothing in its CSS tells you they are load-bearing;
   only the rendered comparison does.
2. Fix the element, not the baseline. A reset of your own in `base` that undoes
   Preflight globally gives the theme two competing resets and moves every
   later section.

## Bare element selectors

A demo stylesheet reaches elements no class covers — `a { color: … }`,
`h1, h2, h3 { … }`, `body { … }`, `*, *::before, *::after { … }`. Each carries
real declarations and none has a class to convert.

- Default: **distribute**. Put the declarations, as utilities, on every element
  the selector actually reaches. `body { … }` is the same operation with one
  target: the `<body>` tag's own `class` attribute.
- Exception: keep it as a rule in `base` when it reaches markup the demo does
  not contain (WordPress-generated output, plugin markup), or when it is a
  global no per-element utility can carry — `*, *::before, *::after {
  box-sizing: border-box }`, which Preflight already sets.

**A bare selector is dead only when every element it matches already carries a
class that sets the same property — check the elements, not the stylesheet.**
Enumerate the matches in the markup and read each `class` attribute. "Every
`<a>` has a class" is exactly the reasoning that has already shipped a defect
here: one logo link carried no class, so `a { color: var(--color-brand) }` was
dropped and that anchor rendered in the body colour.

## Tailwind v4, not v3

The starter installs Tailwind `^4.1`. Four differences bite, and the v3-shaped
answer to each is wrong in a way that still compiles:

- **Gradient direction utilities are `bg-linear-to-r`** (v4), not
  `bg-gradient-to-r` (v3).
- **The built-in palette is OKLCH**, so its hex values are not v3's: `gray-300`
  is `#d1d5dc` where a pre-v4 demo typically declared `#d1d5db`, while
  `gray-200` happens to be identical. The class name cannot tell you which case
  you are in, so the rule is **exact match or arbitrary value**: use a scale
  name only when its value equals the declared value byte for byte, otherwise
  keep the demo's literal (`border-[#d1d5db]`). A value that came from a
  `:root` custom property is a token — map it into `@theme` and reference it by
  name instead.
- **Gradients interpolate in OKLab.** `linear-gradient(90deg, rgba(0,0,0,.6),
  rgba(0,0,0,.1))` compiles to `oklab()` stops whose midpoint differs from the
  demo's sRGB ramp. That is correct v4 output; do not chase the difference with
  extra stops.
- **`transition-colors duration-200` is not `transition: background-color .2s
  ease`.** It animates ten properties on `cubic-bezier(0.4, 0, 0.2, 1)`. When
  the demo named one property and `ease`, keep both:
  `transition-[background-color] duration-200 ease-[ease]`.

## `.btn` is already taken

The starter ships `components/buttons.css` with its own `.btn`, and a demo's
button group usually earns a class of its own at rung 2 or 3. Two sanctioned
files defining one selector is a silent conflict — the later `@import` wins.
Never write a second `.btn`. Either adopt the starter's `.btn` where the demo's
values match it, or give the demo's group the section's block name
(`.hero__btn`, `.btn--<block>`), which the block-scoping rule requires anyway.
Read `components/buttons.css` before writing any button class.

## Forbidden

- `assets/css/styles.css` — that is the `template=basic` output surface. Never write it.
- BEM-with-custom-properties authoring (`.block__element` + `var(--x)` from `:root`). That is `wp-css-system`'s job, not this one.
- A `:root { --… }` block. Tokens belong in `@theme`.
- Any directory under `assets/css/src/tailwindcss/` other than `base`,
  `components`, `layouts` and `utilities`. Never create a fifth. (Those four are
  governed by **File layout** above, not by this rule.)
- An empty or comment-only `.css` file.
- A `<style>` block or a static `style=""` attribute in a PHP template. (Dynamic
  values driven by an ACF field — e.g. a background image URL — are the one
  exception.)
- Hand-written `@media` queries.

## `hidden` is two different things

Tailwind's `hidden` utility is `display: none`. HTML's `hidden` ATTRIBUTE is a
separate mechanism, and it is the one JavaScript toggles (`el.hidden = false`).
Put both on the same element and the element never appears: clearing the attribute
leaves the class, and the class still says `display: none`.

Anything a script shows and hides — a status line, a live region, a panel — is
hidden with the ATTRIBUTE alone. Never with the utility, and never with both.

```html
<!-- wrong: the script clears the attribute, the class keeps it invisible -->
<p class="newsletter__status hidden …" hidden></p>
<!-- right -->
<p class="newsletter__status …" hidden></p>
```

The same applies to any class that is really a state (`opacity-0`,
`pointer-events-none`): pick ONE mechanism per element and let the script own it.

## Verify

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/tailwind-native-check.sh" <theme-dir>
```

The script ships with the plugin and the working directory is the user's project,
so the path must be rooted at `${CLAUDE_PLUGIN_ROOT}`; a bare relative `bin/…` path
resolves to nothing there and exits 127.
