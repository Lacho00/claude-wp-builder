---
description: Responsive validation — screenshots at 6 viewports, checks for layout issues
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
argument-hint: "<url-or-file-path>"
---

# WP Responsive Check — Responsive Validation

Responsive validation now lives in `/wp-demo-verify`. Dispatch to it with the same
argument:

```bash
/wp-demo-verify $ARGUMENTS
```

It walks the five viewports this command used to cover (375, 576, 768, 1024, 1440)
plus 1280, and adds the per-section scroll walk at 1440x900 and 390x844 that a
single static screenshot per breakpoint cannot show. 1280 is sampled because a
layout can be correct at 1024 and at 1440 and still be wrong in between, where
`lg:` utilities apply with no `xl:` override yet.
