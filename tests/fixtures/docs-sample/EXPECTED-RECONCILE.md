# Expected `/wp-yolo` Phase 1.5 Reconciliation Trace

## Assumed demo folder contents

- `demo/home.html` — present
- `demo/home-search.html` — present
- `demo/services.html` — present (NOT in the scope manifest)
- `demo/contact.html` — **missing**

For this trace we exercise the four outcomes against `EXPECTED-SCOPE-MANIFEST.json`
with the demo folder above: Home and Home Search have HTML, Contact (in scope,
`delivery: theme`) is missing its HTML, and `services.html` exists in the demo but has
no corresponding entry in `pages[]`. (`about`, also in scope with no demo/no design,
is out of scope for this trace — it would fire the same "needs demo" outcome as
Contact.)

## Reconciliation, page by page

### 1. Home — in-scope + demo HTML + `delivery: theme` → normal build

`home` is `inScope: true`, `approved: true`, `delivery: theme`, and `demo/home.html`
exists. Per `commands/wp-yolo.md` Step 2.5 rule 1: dispatched as a normal
`/wp-section` build (home role, sections walked in order per Step 4.5).

### 2. Home Search — in-scope + `delivery: idx` → styled embed shell

`home-search` is `inScope: true`, `delivery: idx`, `provider: "Showcase IDX"`. Per
rule 2, this is NOT a normal section build. It dispatches:

```
/wp-page embed home-search --provider "Showcase IDX"
```

(matches `commands/wp-yolo.md` Step 4.6's inner-page IDX/plugin branch, and the
home-page equivalent in Step 4.5 when the home page itself is IDX-delivered).

### 3. Contact — in-scope + NO demo HTML → Review: needs demo

`contact` is `inScope: true`, `delivery: theme`, `approved: true`, but no
`demo/contact.html` exists. Per rule 3: do NOT build. Add to Review:

> "Contact: approved/designed but no HTML — needs demo."

### 4. services.html — demo page NOT in scope → skip

`demo/services.html` has no matching entry (by slug/name) in `pages[]`. Per rule 4:
skip it, add to Review:

> "services: in demo but out of scope — skipped."

## Summary of outcomes fired

| Outcome                                   | Page          | Fired |
|--------------------------------------------|---------------|-------|
| theme → normal build                       | Home          | Yes   |
| idx → `/wp-page embed <slug> --provider …` | Home Search   | Yes   |
| in-scope, no HTML → Review "needs demo"    | Contact       | Yes   |
| demo page not in scope → skip              | services      | Yes   |

All four `commands/wp-yolo.md` Step 2.5 reconciliation outcomes are exercised by this
fixture + assumed demo folder.
