# Review Prompt Template

> Read this file when entering Phase 3 of `codex-handoff` workflow. Use the template below to trigger an adversarial review of Codex's implementation.

## Standard Template

Substitute `<SLUG>`, `<SPEC_PATH>`, `<BASE_BRANCH>`, and `<FOCUS_AREAS>` then issue:

```
/codex:adversarial-review --base <BASE_BRANCH> --background

You are reviewing branch `feat/<SLUG>` against the spec at <SPEC_PATH>.

Your job is to challenge this implementation, not approve it by default.

Required checks:
1. Verify each acceptance criterion in spec section 5 — actually run the commands yourself, do not trust commit messages. Mark each criterion PASS / FAIL / UNVERIFIABLE.
2. Identify any "Do NOT" item (spec section 4) that was violated.
3. Identify any change outside spec section 2's scope (unauthorized edits, even if they look harmless).
4. Focus areas for this specific change: <FOCUS_AREAS>
5. **Compatibility-code drift**: grep the diff for `legacy` / `fallback` / `deprecated` / `oldFormat` / `兼容` / `旧版` plus semantic patterns like `if (versionLT...)` or `try { ... } catch (Old...)`. Cross-reference with spec Section 8 — any pattern present that isn't registered = violation.
6. **Scope creep**: run `git diff --name-only <base>...HEAD` and compare against spec Section 2 "Files to modify" / "Files to create" lists. Anything outside the registered set is out-of-scope (unless it was logged under Section 6 follow-ups).
7. **Project-specific whitelist (if applicable)**: if the project has a whitelist spec (e.g. allowed UI components, allowed library calls, allowed API patterns) referenced from CLAUDE.md or project spec, grep the diff for usage and cross-check.
8. **DoD evidence completeness**: verify spec Section 9.1 / 9.2 / 9.3 have actual command tails pasted (not "I ran it" claims). 9.2 requires the screenshot + console + network triple for UI changes. Missing applicable subsection = NEEDS_CHANGES, not PASS.
9. **Spec compliance traceability**: every finding in your review must cite `(§N line N)` or equivalent project-specific reference. Findings without traceable citation are not acceptable.

Additional pressure-test angles:
- Hidden assumptions (timezones, encoding, null handling, integer overflow, currency precision)
- Concurrency / race conditions if the code path runs concurrently
- Failure modes (what happens when external dependencies fail mid-operation?)
- Rollback feasibility (can this actually be reverted if it goes wrong?)
- Security: any user input reaching SQL / shell / eval / file system without validation?

Output format:
- First line: "VERDICT: PASS" or "VERDICT: NEEDS_CHANGES" or "VERDICT: FAIL"
- Section "Acceptance criteria check" — table of spec section 5 items with PASS/FAIL/UNVERIFIABLE and one-line evidence
- Section "Blockers" — issues that must be fixed before merge. Each blocker: what, where (file:line), why it matters, suggested fix
- Section "Nice-to-haves" — non-blocking suggestions. Keep brief.
- Section "Out-of-scope changes" — anything touched outside spec section 2
- Section "Notes" — anything else worth knowing

Verdict rules:
- PASS = all acceptance criteria verified, no Do-NOT violations, no out-of-scope changes (or only trivial ones), no security/correctness issues
- NEEDS_CHANGES = correctable issues exist but the overall approach is sound
- FAIL = the implementation is structurally wrong, the spec is unimplementable as written, or the change creates unacceptable risk

Write the report to .agent/reviews/YYYY-MM-DD-<SLUG>.review.md.

This review is read-only — do not modify code, do not commit, do not switch branches.
```

---

## Filling `<FOCUS_AREAS>`

Tailor to the actual task. Common focus area phrasings:

### Money / billing / commission

```
- Currency precision: are amounts handled as integers (cents/minor units) or floats? Floats are a bug.
- Rounding: where does rounding happen, and is it consistent across calculation and storage?
- Concurrent order updates: can two simultaneous purchases double-spend the same balance?
- Refund symmetry: does the refund path mirror the charge path (same currency, same precision)?
```

### Database migrations

```
- Backward compatibility: can old application code still read/write the new schema during deploy?
- Data integrity: any FK / unique constraint that could fail mid-migration on production-sized data?
- Rollback feasibility: does the spec's rollback plan actually work, or is it data-destructive?
- Performance: any new index that requires extended downtime on large tables?
```

### External API / third-party integration

```
- Error handling: every outbound call should expect timeout, malformed response, and rate limit
- Retry behavior: is retry idempotent? Could a retry create a duplicate resource or duplicate charge?
- Webhook / callback signature verification: present and correct?
- Polling intervals: any change that could DoS or rate-limit the upstream service?
- Credentials: are API keys, tokens, or secrets only read from config — never hardcoded, never logged?
```

### Frontend / UI

```
- SSR / CSR consistency: does any code assume browser globals (`window`, `document`) exist without guards?
- i18n: any hardcoded user-facing strings outside i18n files?
- Accessibility: form fields have labels, interactive elements have keyboard handlers?
- Component reuse: are new UI elements built with the project's existing component primitives rather than raw markup?
```

### Auth / secret handling

```
- Secret material: does any code log, return in responses, or include in error messages?
- Storage: are secrets encrypted at rest, or only in memory / KMS — never plain text on disk?
- Permission checks: every endpoint enforces auth before doing work?
- Token / key rotation: is the change compatible with rotation in flight (no implicit lifetime assumptions)?
```

### General correctness (when nothing more specific applies)

```
- Edge cases: empty input, single-element input, max-size input, malformed input
- Off-by-one errors in any loop or range
- Null / undefined handling
- Error path: does failure leave the system in a consistent state?
```

---

## Variations

### Variation: small task, lighter review

For tasks that don't warrant a full adversarial pass (e.g. Claude implemented directly, < 30 lines):

```
/codex:review --base <BASE_BRANCH> --background
```

Note: `/codex:review` is not steerable and does not take focus text. Use only for low-risk sanity checks.

### Variation: review without a base branch (uncommitted changes)

If implementation hasn't been pushed to a branch yet (rare in this workflow, but happens for hotfixes):

```
/codex:adversarial-review --background

[... rest of standard template, but mention "current uncommitted changes" instead of branch ...]
```

---

## Interpreting the Report

When the review report arrives (read it from `.agent/reviews/<slug>.review.md`):

### Step 1: Apply Claude's own judgment

**Reviewers over-produce.** LLM reviewers feel pressure to "find something" — many blockers are false positives. For each blocker:

1. Read it
2. Form an independent opinion: is this actually a problem in this context?
3. Categorize: **valid** / **false positive** / **uncertain — need user input**

### Step 2: Filter, then present to user

**Never paste the raw report.** Distill into this structure:

```
Review verdict: <PASS / NEEDS_CHANGES / FAIL>

[If PASS]
All acceptance criteria verified. Safe to merge.
[Optional: 1-2 nice-to-haves worth knowing about, if any]

[If NEEDS_CHANGES]
Reviewer flagged N blockers. My assessment:

1. <Blocker 1 summary>
   → My take: valid / false positive / need your call
   → If valid: recommend fix via /codex:rescue --resume OR I can fix directly
   → If false positive: my reasoning is <why>

2. <Blocker 2 summary>
   → My take: ...

Recommended next step: <specific action>

[If FAIL]
The implementation has fundamental issues:
- <issue 1>
- <issue 2>

This usually means the spec itself has gaps. Recommend going back to Phase 1
to refine. Want me to start that?
```

### Step 3: Wait for user decision

Do not auto-advance. The user decides:

- Accept reviewer's blockers as-is → `/codex:rescue --resume` with fix instructions
- Override certain blockers → note in handoff, proceed with selective fixes
- Re-plan → return to Phase 1

---

## Anti-Patterns

### ❌ Skipping focus areas

Without `<FOCUS_AREAS>`, adversarial review becomes generic and produces noise. Always include 3-5 specific focus bullets relevant to the actual change.

### ❌ Accepting the report uncritically

If you forward every "blocker" to the user as if it's real, you've added a slow, expensive step that produces busywork. Filter first.

### ❌ Running review when nothing was implemented

If Phase 2 didn't produce a commit (Codex failed, was cancelled, etc.), there's nothing to review. Go back to Phase 2, do not run review on an empty branch.

### ❌ Asking Codex to fix as part of the review prompt

`/codex:adversarial-review` is read-only by design. Don't try to make it both reviewer and fixer in the same call — you lose the separation that makes this workflow valuable. Fixes happen via `/codex:rescue --resume` in a separate step.
