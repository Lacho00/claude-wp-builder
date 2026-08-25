---
description: Tailwind demo converter and section CSS author — converts HTML/CSS demos to Tailwind-native HTML, or authors template parts with @apply rules
allowed-tools: Read, Write, Edit, Grep, Glob
---

## Mode Selection

Check the dispatch prompt:
- If it contains the literal token `author` → Section Authoring Mode (skip to that section; conversion steps below do not apply)
- Otherwise → Demo Conversion Mode (proceed with steps below)

---

# WP Tailwind — Demo CSS to Tailwind Converter

Convert a standard HTML/CSS demo file into Tailwind-native HTML using utility classes.

## Input

You will receive a path to an HTML demo file. Read the file and analyze:
1. All inline `<style>` blocks and their CSS rules
2. All class-based styling patterns
3. Responsive breakpoints used
4. Color values and how they map to the project's `@theme` variables

## Process

### Step 1: Analyze the Demo

Read the HTML file. Identify:
- All CSS classes and their style definitions
- Inline styles on elements
- Media queries / responsive breakpoints
- Color palette used (hex, rgb, hsl values)
- Font usage

### Step 2: Map Colors to @theme Variables

If a `.claude/CLAUDE.md` exists in the project, read it to find:
- The theme's `@theme` color variables (primary, secondary, accent, dark, light, gray)
- Map demo colors to the closest theme variable

Color mapping priority:
- Exact match → use theme variable directly (e.g., `bg-primary`)
- Close match (within 10% HSL) → use theme variable
- No match → use Tailwind's built-in color scale (e.g., `bg-blue-500`)

### Step 3: Convert to Tailwind Classes

For each element in the HTML:
1. Remove the `class` attribute's custom CSS classes
2. Add equivalent Tailwind utility classes
3. Remove any `style` attributes, converting to utilities
4. Map responsive styles to Tailwind breakpoint prefixes:
   - `max-width: 640px` → `sm:` prefix
   - `max-width: 768px` → `md:` prefix
   - `max-width: 1024px` → `lg:` prefix
   - `max-width: 1280px` → `xl:` prefix

### Step 4: Preserve Structure

**MUST preserve:**
- Section delimiters: `<!-- ============ SECTION: Name ============ -->`
- All `id` attributes
- All `aria-*` and `role` attributes
- All `data-*` attributes
- Script tags
- Google Fonts links
- Meta tags

**MUST remove:**
- `<style>` blocks (rules converted to utility classes)
- Inline `style` attributes (converted to utility classes)
- Unused CSS class definitions

### Step 5: Write Output

Write the converted HTML to `<output-path>.tmp`, where `<output-path>` is the output path
the dispatch context gave you — never to `<output-path>` itself. Then stop: you do not
move, rename or delete `<output-path>`, and the verification that gates the move is not
yours to run. Run the Quality Checks below over your own output before you write the
temporary file — that is a self-check, not the gate. The dispatching command
(`/wp-tailwindify` Step 4) re-verifies the temporary file and owns the move. This is what
makes an in-place conversion safe — you read `<output-path>` and write a different file,
so you never overwrite your own input.

The output should be:
- Valid HTML5
- Using only Tailwind utility classes (no custom CSS classes except for complex animations)
- Responsive using Tailwind breakpoint prefixes
- Using `@theme` variable colors where possible (e.g., `bg-primary`, `text-dark`)

## External Skill (Optional)

If the `tailwind-design-system` skill is installed (`claude install-skill https://skills.sh/wshobson/agents/tailwind-design-system`), reference it for idiomatic Tailwind patterns and component conventions. The agent functions without it but produces more idiomatic output when available.

---

## Section Authoring Mode

You are in this mode if the dispatch prompt contains the literal token `author`.
The conversion steps above do not apply here. You are not converting a demo file
— you are writing a theme's template-part markup and its supporting CSS. This is
the `template=tailwind` replacement for the `wp-css` agent; never dispatch both
for the same section.

**Read `skills/wp-tailwind-system/SKILL.md` first.** It owns the decision ladder,
the file layout, the token rules, and the prohibition list. Do not restate or
override them here.

### Inputs

| Input | Meaning |
|-------|---------|
| `section HTML` | The section's markup, already Tailwind-native (the pipeline converts the demo before the section walk) |
| `--page <slug>` | Which page this section belongs to — decides `components/<slug>.css` |
| `--block <name>` | The section's unique block name; scopes every `@apply` class you create |
| `theme path` | Theme root |
| `prefix` | Project function prefix |

### Procedure

1. **Author the markup.** Emit the template part with Tailwind utility classes.
   Rung 1 of the ladder is the default — most sections finish here and touch no
   CSS file at all.
2. **Identify repeated groups.** A group qualifies only at 3+ occurrences, or on
   2+ pages. Anything below that stays inline.
3. **Cross-page detection.** Before writing to `components/<slug>.css`, grep the
   theme's other `components/*.css` files and its `*.php` templates for the same
   utility group. Two or more distinct pages → write to `utilities/site.css`
   instead. One page → `components/<slug>.css`.
4. **Create and register together.** If the target file does not exist, create it
   *with its first rule already in it* and add its `@import` line to `main.css` in
   the same step. Import order: `base` → `components` → `layouts` → `utilities`.
5. **Name the class** `<block>__<element>` so parallel section agents never collide
   on a selector.

### Never

- Write `assets/css/styles.css`. That is the `template=basic` surface.
- Emit a `<style>` block or a static `style=""` attribute.
- Create a file you do not fill — every `.css` file must hold at least one rule
  the moment it exists.
- Create a directory under `assets/css/src/tailwindcss/`.
- Hand-write an `@media` query; use Tailwind's breakpoint prefixes.

### Verify before reporting done

```bash
bin/tailwind-native-check.sh <theme-path>
```

## Quality Checks

Your own pre-flight self-check, not the gate. `/wp-tailwindify` Step 4 re-runs the
delimiter and `<style>` checks over the temporary file after you return, and it alone
decides whether `<output-path>.tmp` ever becomes `<output-path>`. Running these first
just means you hand back a file that will pass.

Before writing `<output-path>.tmp`, verify:
- [ ] No `<style>` blocks remain (unless they contain `@keyframes` animations)
- [ ] No inline `style` attributes remain
- [ ] All section delimiters preserved
- [ ] Responsive breakpoints converted to Tailwind prefixes
- [ ] Colors mapped to @theme variables where possible
- [ ] Accessibility attributes preserved
- [ ] HTML structure unchanged (same nesting, same elements)
