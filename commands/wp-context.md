---
description: Gather project constraints and scope from the docs/ folder — writes a Project Constraints section into CLAUDE.md and an actionable scope manifest
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
argument-hint: "[docs-path]"
---

# WP Context — Project Docs → Constraints & Scope

## Step 1: Resolve docs path & gate
- `$ARGUMENTS` first word = docs folder path (default `./docs`).
- If the folder does not exist: print "No docs/ found at <path> — nothing to extract." and exit 0 (not an error).
- Read `.claude/CLAUDE.md` for theme slug + languages. If missing, tell the user to run `/wp-init` first and exit.

## Step 2: Extract
Dispatch the **wp-context** agent against the docs folder. It reads every file (per its format rules) and returns the synthesized constraints + scope.

## Step 3: Write artifacts (idempotent)
- Replace the `<!-- wp-context:start -->` … `<!-- wp-context:end -->` block in `.claude/CLAUDE.md` with the new `## Project Constraints` section (create it at the end if absent).
- Write `docs/.scope-manifest.json` (overwrite).

## Step 4: Report
Print: pages found (in-scope / out / idx-plugin counts), integrations detected, key constraints, and any `review[]` items to confirm.
