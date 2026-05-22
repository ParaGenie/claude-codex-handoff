# Spec Template

> Read this file when entering Phase 1 of `codex-handoff` workflow. Fill out the template below and write to `.agent/specs/YYYY-MM-DD-<slug>.md`.

## Template

```markdown
# <Task Title>

- **Date**: YYYY-MM-DD
- **Type**: bugfix | feature | refactor | migration
- **Risk**: low | medium | high
- **Related docs**: <optional link to docs/ design docs>

## 1. Background & Goal (WHY)

<2-4 sentences: current state, why change, end state.>

## 2. Scope (WHERE)

### Files to modify

- `path/to/file1.ext` — <what changes, why>
- `path/to/file2.ext` — <what changes, why>

### Files to create

- `path/to/new-file.ext` — <purpose>

### Files NOT to touch (explicit boundary)

- `path/to/related.ext` — <why hands-off>

### Database changes

- New tables / altered tables: paste DDL
- Data migrations: describe approach (Implementer writes actual SQL)
- If none: write "None"

## 3. Implementation Notes (HOW, coarse)

<Bullet list, 1-3 sentences each. No code blocks. Codex will fill in the actual code.>

- Point 1: ...
- Point 2: ...
- Point 3: ...

## 4. Do NOT (NEGATIVE SPACE)

<Explicit boundaries to prevent Codex from improvising.>

- Do not modify X
- Do not refactor Y in passing
- Do not introduce new dependencies
- Do not change Z's existing API signature

## 5. Acceptance Criteria (DONE)

<Must be executable / verifiable. No "code quality is good" garbage.>

- [ ] `<test command>` passes
- [ ] `<typecheck command>` clean (skip if language has no separate typecheck step)
- [ ] `<lint command>` clean
- [ ] Manual scenario: <concrete steps>
- [ ] API contract: `curl -X POST ... | jq '.field'` returns "expected"

## 6. Rollback Plan (required for medium/high risk only)

<How to revert if something goes wrong post-merge.>

## 7. Extra Notes for Implementer

<Optional. Stack quirks, preferred patterns, files to reference.>
```

---

## Filling Guide

### Slug naming

Kebab-case, short, specific.

- Good: `stale-items-indicator`, `order-refund-rounding-fix`, `webhook-signature-verify`
- Bad: `fix-bug`, `feat-1`, `changes`, `update`

### Section 1 (Background & Goal)

Two test questions:

- Can a colleague who's never seen the codebase understand WHY from this section alone?
- Is the "end state" measurable, or just vibes?

If either fails, rewrite.

### Section 2 (Scope)

- **List actual file paths.** Not "the list components" — `src/components/items/ItemCard.ext`.
- **"Files NOT to touch" matters.** Codex will improvise without explicit boundaries. Examples worth blocking:
  - Shared components or modules with multiple callers (don't change exported signatures)
  - Third-party integration / adapter code that needs human validation against the upstream
  - Production config (`.env.production`, prod-only profile files, prod manifests)
  - Any file whose change would require a coordinated deploy

### Section 3 (Implementation Notes)

**Coarse, not fine.** Rule: if you're tempted to write a code block, you're too detailed.

- Right: "Add `isStale(item, thresholdMs)` to `src/lib/item-status.ext`, compare in UTC"
- Wrong: 15 lines of code implementing the function

The goal is **enough specificity for Codex not to invent business logic**, but **not so much you're just writing the code yourself**.

### Section 4 (Do NOT)

This is where you prevent Codex from "helpfully" refactoring adjacent code. Common bullets worth including:

- "Do not introduce new dependencies"
- "Do not refactor unrelated code in passing"
- "Do not change [shared file]'s exported signature"
- "Do not modify the backend (frontend-only task)" / "Do not modify the frontend (backend-only task)"
- "Do not enable any feature flags or toggle production config"

### Section 5 (Acceptance Criteria)

**Every item must be runnable or observable.** If you can't write a command or describe a click-through that verifies it, it's not an acceptance criterion — it's a wish.

Bad criteria (banned):

- "Code looks clean"
- "Performance is acceptable"
- "No regressions"
- "Tests pass" (which tests? what command?)

Good criteria:

- `<typecheck command>` exits 0
- `curl http://localhost:8080/api/v1/items?stale=true | jq 'length'` returns > 0 after setting a test row's `updated_at` to `NOW() - INTERVAL 25 HOUR`
- New unit test in `src/lib/item-status.spec.ext` covers 4 cases: fresh, just-stale, long-stale, future-dated
- Manual: log in as test user, visit `/items`, observe warning badge on the row with `updated_at` set above

### Section 6 (Rollback)

**Mandatory** if Risk is medium or high. Even one sentence is fine:

- "Pure frontend change — revert commit, run `<build command>` and restart. No data risk."
- "DB migration — revert script in `migrations/rollback/2026-05-21-<slug>.sql`. Run before reverting code."

Low-risk tasks can skip this, but for anything touching money / DB / user data, write it.

### Section 7 (Extra Notes)

Use sparingly. Good uses:

- "Follow the error-handling pattern in `<reference file>`"
- "i18n keys go in `i18n/en.json` under the relevant namespace"

Bad uses:

- Repeating things already in `CLAUDE.md` or `karpathy-guidelines`
- Writing pseudocode
- Vague "be careful" warnings

---

## Example: Filled-Out Spec

See a worked example in the project's `.agent/specs/` directory after running through the workflow once, or refer to:

```markdown
# Items list "stale" indicator

- **Date**: 2026-05-21
- **Type**: feature
- **Risk**: low
- **Related docs**: (none; see CLAUDE.md "Key Docs")

## 1. Background & Goal

The current items list renders every row identically. Users miss items that haven't been updated in over 24 hours and lose track of what's actionable. Add a visual indicator (badge + top-of-page banner) for items whose `updated_at` is older than 24h.

## 2. Scope

### Files to modify
- `src/views/items-list.ext` — list rendering, add banner placement
- `src/composables/use-items.ext` — add `staleCount` computed
- `src/lib/item-status.ext` — add `isStale(item, thresholdMs)` helper

### Files to create
- `src/components/StaleBanner.ext`
- `src/lib/item-status.spec.ext`

### Files NOT to touch
- `src/server/items.handler.ext` — frontend-only task, no API change
- `src/components/ItemCard.ext` props signature (shared by other views)

### Database changes
None.

## 3. Implementation Notes
- `isStale(item, thresholdMs = 86_400_000)` returns boolean. `updated_at` is UTC; compare with `Date.now()` UTC.
- Badge inside `ItemCard.ext` reuses the existing warning style — do not introduce a new color token.
- `use-items.ext` exposes `staleCount` — count only items with `status === 'active'`.
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
- [ ] Manual: SQL-set an item's `updated_at` to `NOW() - INTERVAL 25 HOUR`, refresh, badge + banner appear
- [ ] Manual: set to `NOW() - INTERVAL 12 HOUR`, no badge/banner
- [ ] Manual: set to `NOW() + INTERVAL 1 HOUR` (future-dated), no badge (future ≠ stale)

## 6. Rollback Plan
Frontend-only. Revert commit, run `<build command>` and restart.

## 7. Extra Notes
- English text only this round; banner copy keyed under the existing i18n namespace
- Reuse the existing warning color token rather than hex
```
