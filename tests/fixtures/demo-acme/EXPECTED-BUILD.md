# Expected `/wp-yolo` Phase 2 Build Trace — demo-acme

Hand-traced build order for `/wp-yolo tests/fixtures/demo-acme` over
`EXPECTED-MANIFEST.json`, per `commands/wp-yolo.md` Step 4 ("Phase 2 — Build").
No agents were run; this is the order the orchestrator's documented steps
produce when read against this specific manifest.

## Phase 1 + checkpoint (for context, not build order)

1. `wp-normalize` dispatched against `tests/fixtures/demo-acme` → emits
   `demo/*.html` + `demo/.yolo-manifest.json` (== `EXPECTED-MANIFEST.json`).
2. Checkpoint (default mode, no `--yolo`): prints pages/sections/confidence,
   shared header/footer flags, `contentTypes[]`, and the `review[]` list above.
   User approves as-is (no edits needed for this trace).

## Phase 2 — Build, in the exact order `wp-yolo.md` Step 4 specifies

1. **`/wp-settings`** — logo "Acme Co", nav links, footer copyright text,
   contact email/message labels — derived from header/footer/contact content.

2. **CPTs first — `contentTypes[]` loop:**
   - `/wp-cpt team --from-demo team-teaser` — registers the `team` CPT
     (`has_archive: true`), fields (`photo`, `role`, `bio`; title = person name),
     `archive-team.php`, `single-team.php`, `template-parts/team/card.php`,
     the `team` teaser query-section (`template-parts/section-team.php` +
     `fields/section-team.php`), and the seed helper for the 6 `seed[]` entries.
   - **This step MUST complete before any section that queries `team`.**
     It runs before the home page's `team-teaser` section (step 5 below) and
     before `archive-team.php` is treated as "already built" in step 7 — both
     of which depend on the CPT being registered and its teaser/card templates
     existing first. Confirmed: CPT loop is step 2, home sections are step 5.

3. **`/wp-header`** — shared header (identical across all 5 pages, per
   `shared.header: true`, `headerDivergentPages: []`) → `header.php` +
   nav-walker + registered "primary" menu (Home/About/Team/Services/Contact).

4. **`/wp-footer`** — shared footer (identical across all pages,
   `shared.footer: true`, `footerDivergentPages: []`) → `footer.php`.

5. **Home page sections** (`pages[slug=index, role=home].sections[]`, in order):
   1. `hero` → `kind: static` → normal `/wp-section hero`.
   2. `about-teaser` → `kind: static` → normal `/wp-section about-teaser`.
   3. `team-teaser` → `kind: cpt-teaser`, `cpt: team` → `/wp-section team-teaser`
      scoped to `WP_Query(post_type=team)`, reusing `template-parts/team/card.php`
      and the `section-team` chrome fields already scaffolded by `/wp-cpt team`
      in step 2 — no new repeater fields duplicated here.
   4. `services` → `kind: static` → normal `/wp-section services` (3 static cards).

6. **Inner pages** (`pages[role=inner]`: `about`, `services`, `contact`):
   - `/wp-page custom about` → sections `about-story`, `about-values`
     (both `kind: static` → normal `/wp-section`).
   - `/wp-page custom services` → sections `services-detail`, `services-process`
     (both `kind: static` → normal `/wp-section`).
   - `/wp-page custom contact` → section `contact` → `kind: contact` →
     **`/wp-section contact --cf7`** — routes through the CF7 form path
     (`<input type="email">` + `<textarea>` detected by `wp-normalize` as a
     contact form), not a static section build.

7. **`cpt-archive` pages** (`pages[slug=team, role=cpt-archive]`):
   - `team.html` → **no `/wp-page custom team` run, no `page-team.php`, no WP
     Page created.** Its archive URL is `archive-team.php` with `has_archive`,
     already built by `/wp-cpt team` in step 2. Noted in the final report as
     "archive of `team`, built by /wp-cpt".

8. **Blog** — no `pages[role=blog]` entry in this manifest → step skipped.

9. **Mandatory system pages — always, regardless of demo content:**
   - `/wp-page 404` — the fixture has no 404 page; built anyway, synthesized
     from the shared header/footer/design tokens.
   - `/wp-page search` — the fixture has no search-results page; built anyway,
     same synthesis path.
   These run unconditionally per `wp-yolo.md` Step 4.9 — presence in the demo
   is irrelevant.

## Phase 3 — Seed & Finish (in order)

1. `/wp-seed` — creates WP Pages for `about`, `services`, `contact` (matching
   `page-<slug>.php` templates) — **NOT** for `team` (cpt-archive, no page
   created, confirmed above) — populates ACF fields, sideloads team member
   photos (`assets/team/*.jpg`) into media, creates the 6 `team` CPT seed
   posts from `contentTypes[0].seed[]`, and builds the primary nav menu.
2. `/wp-finalize`
3. `/wp-polish`
4. `/wp-responsive-check`

## Assertions checked by this trace

- [x] `/wp-cpt team` runs before the home `team-teaser` section AND before
      `archive-team.php` is available (both step 2, ahead of steps 5 and 7).
- [x] `team.html` produces no `page-team.php` and no WP Page (step 7).
- [x] The `contact` section routes through `--cf7` (step 6, contact page).
- [x] `/wp-page 404` and `/wp-page search` both run despite neither existing
      in the fixture (step 9, unconditional).
