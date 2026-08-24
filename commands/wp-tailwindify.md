---
description: Convert an HTML/CSS demo to Tailwind-native HTML — preserves section delimiters, maps colors to @theme variables
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
argument-hint: "[path/to/demo.html] [--out <output-path>]"
---

# WP Tailwindify — Convert Demo to Tailwind

Convert a standard HTML/CSS demo file into Tailwind-native HTML.

## Step 1: Locate the Demo File and Resolve the Output Path

Parse `$ARGUMENTS`:
- **First non-flag word** = the input demo file.
  - If it is provided and is a file path, use that file.
  - Otherwise, check for `demo/index.html` in the current working directory.
  - If no demo file found, ask the user for the path.
- **`--out <output-path>`** = where to write the converted HTML (optional). When
  omitted, the output path defaults to `<demo-dir>/index-tailwind.html` — the original
  behavior, unchanged for standalone/manual use.

`--out` may name the input file itself. That is a deliberate **in-place conversion**:
the caller is responsible for having kept a backup first (this is how `/wp-yolo`
Step 2.6 uses the command — it copies `demo/<slug>.html` to `demo/<slug>.original.html`
and then converts `demo/<slug>.html` onto itself, so every downstream reader that names
`demo/<slug>.html` picks up Tailwind-native markup with no argument change).

Verify the input file exists and is an HTML file.

## Step 2: Read and Validate

Read the demo HTML file. Check:
- Does it contain `<style>` blocks or inline styles? (If not, it may already be Tailwind-native — confirm with user.)
- Does it have section delimiters? (Warn if missing — suggest running `/wp-polish` first.)

## Step 3: Dispatch Conversion Agent

Dispatch the `wp-tailwind` agent (@agents/wp-tailwind) with the following context:

- Input file path: `<demo-file-path>`
- Output file path: the resolved output path from Step 1 — the `--out` value when given,
  otherwise `<demo-dir>/index-tailwind.html` (alongside the original)
- Project CLAUDE.md path (if exists): for @theme color mapping

When the output path equals the input path, tell the agent it is overwriting its own
input: it must finish reading and converting before writing, and must not emit a partial
file.

## Step 4: Verify Output

After the agent completes:
1. Read the output file
2. Verify section delimiters are preserved (count should match original)
3. Verify no `<style>` blocks remain (except `@keyframes`)
4. Report the conversion result to the user

## Step 5: Offer Next Steps

```
=== Demo Converted to Tailwind ===
Original:  <original-path>
Tailwind:  <output-path>
Sections:  <count> preserved

Next steps:
- Review the converted demo in a browser
- If satisfied, replace the original: cp <output-path> <original-path>
- Run /wp-init to scaffold the project with the Tailwind template
```

When `--out` pointed at the input file, the conversion was in place: `<original-path>`
and `<output-path>` are the same file, so drop the "replace the original" line — there
is nothing left to copy.
