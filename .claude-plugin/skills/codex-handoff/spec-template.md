# Spec Template

> Load in Phase 1 of `codex-handoff`. Fill the template and write it to `.agent/specs/YYYY-MM-DD-<slug>.md`. Slug: short kebab-case (`order-refund-rounding-fix`, not `fix-bug`).

## Template

```markdown
# <Task Title>

- **Date**: YYYY-MM-DD
- **Type**: bugfix | feature | refactor | migration
- **Risk**: low | medium | high
- **Related docs**: <optional link to docs/ design docs>

## 1. Background & Goal (WHY)

<2-4 sentences: current state, why change, measurable end state.>

## 2. Scope (WHERE)

### Files to modify
- `path/to/file1.ext` — <what changes, why>

### Files to create
- `path/to/new-file.ext` — <purpose>

### Files NOT to touch (explicit boundary)
- `path/to/related.ext` — <why hands-off>

### Database changes
<DDL for new / altered tables; migration approach (implementer writes the SQL); or "None">

## 3. Implementation Notes (HOW, coarse)

<Bullets, 1-3 sentences each. No code blocks — the implementer writes the code.>

## 4. Do NOT (NEGATIVE SPACE)

- Do not modify X
- Do not refactor Y in passing
- Do not introduce new dependencies
- Do not change Z's existing API signature

## 5. Acceptance Criteria (DONE)

<Every item runnable or observable. No "code quality is good".>

- [ ] `<test command>` passes
- [ ] `<typecheck command>` clean (skip if the language has none)
- [ ] `<lint command>` clean
- [ ] Manual scenario: <concrete steps>
- [ ] API contract: `curl -X POST ... | jq '.field'` returns "expected"

## 6. Rollback Plan (required for medium/high risk)

<How to revert post-merge.>

## 7. Extra Notes for Implementer

<Optional: stack quirks, reference files, preferred patterns.>

## 8. Compatibility Exemption Registry (default: empty)

| What's being compatible-with | Why permanent, not a temporary bridge | Cleanup timeline | Owner |
|---|---|---|---|
| (default: none) | | | |

Empty = this task introduces no compatibility code. If it stays empty and the diff contains `if (legacy*)` / `if (version < ...)`, comments mentioning legacy / fallback / deprecated / backwards-compat, `catch (OldFormat...)` fallbacks, or branches keyed off historical state, the reviewer flags a violation.

## 9. Definition of Done Evidence (filled in Phase 2)

Implementer writes the command lines; a separate verify subagent runs them; the main agent records the tails (~30 lines each).

### 9.1 Static build evidence

\`\`\`
$ <dependency install / build / verify command>
<tail>

$ <typecheck / lint command, if separate>
<tail>
\`\`\`

### 9.2 Runtime verification evidence (when changes touch a running service or UI)

\`\`\`
$ <dev / serve command>
<startup log including the ready marker>

$ <health check, e.g. curl /health>
<status + body>
\`\`\`

UI changes — all three required, captured by the user:
- **Page screenshot**: path or link
- **Console screenshot**: no errors in DevTools console
- **Network request list**: method + status per relevant request (all 2xx)

### 9.3 Unit test evidence (when changes touch business-critical paths)

\`\`\`
$ <test command>
<tail showing count and pass/fail summary>
\`\`\`

New or modified tests:
- `path/to/Test#methodA` — happy path
- `path/to/Test#methodB` — edge case

If not applicable, write: "Section 9.3 not applicable — task does not touch business-critical paths."
```

---

## Filling guide

**§1 Background** — A colleague who has never seen the codebase should understand WHY from this section alone, and the end state must be measurable, not vibes.

**§2 Scope** — Real file paths, not "the list components". "Files NOT to touch" is what stops the implementer from improvising; worth blocking: shared modules with multiple callers, third-party adapter code that needs human validation, production config, anything requiring a coordinated deploy.

**§3 Implementation notes** — Coarse. If you are tempted to write a code block, you are too detailed. Right: "Add `isStale(item, thresholdMs)` to `src/lib/item-status.ext`, compare in UTC." Enough that the implementer does not invent business logic, not so much that you are writing the code.

**§4 Do NOT** — Prevents "helpful" adjacent refactors. Usual bullets: no new dependencies, no unrelated refactors, do not change `<shared file>`'s exported signature, backend-only / frontend-only, no feature flags or production config.

**§5 Acceptance** — If you cannot write a command or a click-through that verifies it, it is a wish, not a criterion. Banned: "code looks clean", "performance acceptable", "no regressions", "tests pass" (which? what command?). Good: `<typecheck command>` exits 0; `curl .../items?stale=true | jq 'length'` > 0 after setting a row's `updated_at` to `NOW() - INTERVAL 25 HOUR`; new test covers fresh / just-stale / long-stale / future-dated.

**§6 Rollback** — Mandatory for medium/high risk; one sentence is fine ("frontend-only: revert commit, rebuild, restart" / "DB: run `migrations/rollback/<date>-<slug>.sql` before reverting code"). Always write it for money / DB / user data.

**§7 Extra notes** — Sparingly: "follow the error-handling pattern in `<file>`", "i18n keys under namespace X". Not: things already in `CLAUDE.md`, pseudocode, vague "be careful".

**§8 Compatibility registry** — Legal entries name a concrete permanent constraint ("webhook secrets issued before the prefix format — provider documents them as valid forever"). Illegal: "compat for old frontend" when it lives in the same repo, "defensive fallback" without a concrete legacy version, "just in case". An implementer tempted to write compat code against an empty table stops and asks.

**§9 Evidence** — Filled at the end of Phase 2. Docs-only changes: build / link-check / grep self-checks, not forced test runs that do not exist. Missing any applicable subsection = reviewer marks NEEDS_CHANGES; the sandbox cannot re-run commands, so the recorded tails are the reviewer's only ground truth.

---

## Example

```markdown
# Items list "stale" indicator

- **Date**: 2026-05-21
- **Type**: feature
- **Risk**: low
- **Related docs**: (none; see CLAUDE.md "Key Docs")

## 1. Background & Goal
The items list renders every row identically, so users miss items untouched for over 24 hours. Add a badge on each such row and a top-of-page banner counting them.

## 2. Scope
### Files to modify
- `src/views/items-list.ext` — list rendering, banner placement
- `src/composables/use-items.ext` — add `staleCount` computed
- `src/lib/item-status.ext` — add `isStale(item, thresholdMs)` helper
### Files to create
- `src/components/StaleBanner.ext`
- `src/lib/item-status.spec.ext`
### Files NOT to touch
- `src/server/items.handler.ext` — frontend-only task
- `src/components/ItemCard.ext` props signature (shared by other views)
### Database changes
None.

## 3. Implementation Notes
- `isStale(item, thresholdMs = 86_400_000)` returns boolean; `updated_at` is UTC, compare with `Date.now()`.
- Badge reuses the existing warning style — no new color token.
- `staleCount` counts only items with `status === 'active'`.
- Banner copy: "You have {count} item(s) older than 24 hours. Review them now."

## 4. Do NOT
- No new dependencies (no date library)
- Do not change `ItemCard.ext` props signature
- Do not auto-archive stale items (visual hint only)
- Do not modify the backend

## 5. Acceptance Criteria
- [ ] `<typecheck command>` clean
- [ ] `<lint command>` clean
- [ ] `<test command>` passes, including new cases in `item-status.spec.ext`
- [ ] Manual: set an item's `updated_at` to `NOW() - INTERVAL 25 HOUR`, refresh → badge + banner
- [ ] Manual: `NOW() - INTERVAL 12 HOUR` → no badge/banner
- [ ] Manual: `NOW() + INTERVAL 1 HOUR` → no badge (future ≠ stale)

## 6. Rollback Plan
Frontend-only. Revert commit, run `<build command>`, restart.

## 7. Extra Notes
- Banner copy keyed under the existing i18n namespace; reuse the warning color token, not hex
```
