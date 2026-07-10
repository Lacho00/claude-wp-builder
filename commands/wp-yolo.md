---
description: Full-site builder — convert a complete multi-page HTML demo folder into a WordPress theme in one pass
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
argument-hint: "<demo-folder> [--yolo] [--careful]"
---

# WP YOLO — Full-Site Demo → WordPress Theme

Convert a complete multi-page HTML demo into a working theme in one orchestrated pass,
reusing the plugin's existing build pipeline end to end. Run this AFTER `/wp-create` +
`/wp-init` have scaffolded the project. This command does not reimplement any builder —
it dispatches the `wp-normalize` agent once, then drives the existing commands/agents in
dependency order.

## Step 1: Parse Arguments & Gate

Parse `$ARGUMENTS`:
- **First non-flag word** = path to the demo folder (required). Error and exit if missing,
  or if the path is not a directory:
  ```
  Error: A demo folder is required.
  Usage: /wp-yolo <path-to-demo-folder> [--yolo] [--careful]
  ```
- **`--yolo`** = no checkpoint at all (ingest → build → seed → finalize → report, hands-off).
- **`--careful`** = checkpoint after normalization AND a per-page confirm before each inner
  page's build in Phase 2.
- **default** (neither flag) = a single checkpoint after normalization, then hands-off.

Read `.claude/CLAUDE.md` at the project root. If it does not exist, refuse:
```
Error: No .claude/CLAUDE.md found. Run /wp-init first to scaffold the project.
```
Extract function prefix, theme slug, languages (primary + secondary), template
(basic|tailwind), and CF plugin (scf|acf) — needed by every downstream command.

## Step 2: Phase 1 — Normalize

Dispatch the **wp-normalize** agent against the demo folder from Step 1. It scans every
page, resolves shared header/footer, splits sections, classifies content types
(static-repeater vs custom-post-type), and writes:
- `demo/*.html` — canonical, delimited pages (the same `<!-- SECTION: X -->` format the
  existing builders consume)
- `demo/.yolo-manifest.json` — the orchestration source of truth (`pages[]`, `shared`,
  `contentTypes[]`, `review[]`)

Read `demo/.yolo-manifest.json` back once the agent completes.

## Step 3: Checkpoint (skipped under --yolo)

Unless `--yolo` is set, print the detected map from the manifest:
- Pages (slug, role: home / inner / cpt-archive / blog) and their sections (name, kind,
  confidence where < 1.0)
- Shared header/footer flags and any divergent pages
- Content-type classifications (`contentTypes[]`) with field lists
- The full `review[]` list of low-confidence decisions

Ask the user to **approve / edit / abort**:
- Edit = rename/merge/split a section, drop a page, flip a `kind` between `static` and
  `cpt-teaser`, etc. Apply edits directly to `demo/.yolo-manifest.json` before continuing.
- Abort = stop here, leave `demo/*.html` and the manifest in place for a later resumed run.

Under `--yolo`, skip this step and proceed straight to Phase 2 with the manifest as
emitted by `wp-normalize`.

## Step 4: Phase 2 — Build (dependency order)

Drive the existing commands/agents in this exact order, reading everything from the
(possibly edited) manifest. Do not reimplement any builder's logic — dispatch it.

1. **`/wp-settings`** — logo, contact info, social links, legal links, copyright, derived
   from the header/footer/contact content found by `wp-normalize`.
2. **CPTs first** — for every entry in `contentTypes[]`, run `/wp-cpt <name>` (using its
   `fields[]` and `seed[]` as the `--from-demo` hints). This must complete before any
   section queries that CPT.
3. **`/wp-header`** — the shared header → `header.php` + nav-walker + registered menus.
4. **`/wp-footer`** — the shared footer → `footer.php`.
5. **Home page sections** — for the `pages[role=home]` entry, walk its `sections[]` in
   order and run the `/wp-section` procedure per section:
   - `kind: "static"` → normal `/wp-section <name>` (three-agent parallel dispatch).
   - `kind: "cpt-teaser"` → `/wp-section <name>` scoped to query the section's `cpt` via
     `WP_Query` rather than holding repeater fields (per that CPT's teaser, already
     scaffolded by its `/wp-cpt` run in step 2 — do not duplicate fields).
   - `kind: "contact"` → `/wp-section <name> --cf7`.
6. **Inner pages** — for every `pages[role=inner]` entry: run `/wp-page custom <slug>`,
   then its `sections[]` through the same per-kind logic as step 5. Under `--careful`,
   confirm with the user before building each inner page.
7. **`cpt-archive` pages** — no WP Page is created for these (their archive URL is
   `has_archive`, already wired by `/wp-cpt` in step 2). Skip page creation; note them in
   the final report as "archive of `<cpt>`, built by /wp-cpt".
8. **Blog** — if any `pages[role=blog]` entry exists, run `/wp-page blog`.
9. **Mandatory system pages — always, regardless of demo content:**
   - `/wp-page 404`
   - `/wp-page search`
   These are never conditional on the demo containing a matching page; they are
   synthesized from the derived design (shared header/footer, design tokens, section
   styling) so they read as native to the site.

## Step 5: Phase 3 — Seed & Finish

Run, in order:
1. **`/wp-seed`** — create WP Pages with matching slugs (so `page-<slug>.php` auto-applies),
   populate ACF fields from extracted text in the **primary language only** (flag secondary-
   language strings as untranslated), sideload images into the media library and wire them
   to fields, build menus from the nav, and create CPT seed posts from each `contentTypes[]`
   entry's `seed[]`.
2. **`/wp-finalize`**
3. **`/wp-polish`**
4. **`/wp-responsive-check`**

## Step 6: Report

Print a summary:
```
=== WP YOLO Build Complete ===
Pages built:       <slug list, with section counts>
CPTs registered:   <name list, with archive/single status and seed count>
CF7 forms:         <count, if any contact sections were found>
Media imported:    <count>
Mandatory pages:   404, search (always built)

Review:
  - <every review[] entry from the manifest — low-confidence splits, CPT-vs-repeater
    verdicts, ambiguous fields>
  - <untranslated secondary-language strings, if any>
  - <anything skipped — e.g. JS-only interactivity not reproducible in static templates>
```

Note for the user: `--yolo` is best used **after** one checkpointed dry-run of the same
demo folder, once the manifest has been reviewed and edited at least once.
