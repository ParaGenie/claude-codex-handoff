# Review Prompt Template

> Load in Phase 3 of `codex-handoff`. The reviewer is always Codex — Claude wrote the code, so a Claude reviewer would be the same model grading its own homework. If Codex is unavailable, the task waits (stall rules in `SKILL.md` Phase 3).

## Before triggering (main agent)

- [ ] Every §5 acceptance command was run by the verify subagent and its tail is recorded in §9.1 / 9.2 / 9.3
- [ ] UI changes: §9.2 screenshot + console + network triple attached
- [ ] §9 is committed on `feat/<SLUG>` (`git log <BASE_BRANCH>..HEAD` non-empty — the plugin injects the *committed* branch diff)
- [ ] 3–5 task-specific focus bullets prepared (below)

The plugin injects the branch diff, commit log, and diff-stat into Codex's `<repository_context>`; you bundle nothing. Empty §9 = a workflow bug, not a Codex bug.

## Standard template

Substitute `<SLUG>`, `<SPEC_PATH>`, `<BASE_BRANCH>`, `<FOCUS_AREAS>`, then issue:

```
/codex:adversarial-review --base <BASE_BRANCH> --background

You are reviewing branch `feat/<SLUG>` against the spec at <SPEC_PATH>.

The branch diff, commit log, and diff-stat are already in your `<repository_context>`. Use them as primary evidence.

Sandbox rules:
- Do NOT run git write commands (commit, add, switch, branch, restore, stash, reset, checkout) — `.git/` is read-only here.
- Do NOT run build / test / lint commands (pytest, npm run build, ruff, ...) — `.venv` / `node_modules` are not mounted and they resolve to "command not found".
- Read-only `git diff / log / show` only when your `<repository_context>` says "self-collect" mode (large diffs). In the default inline-diff mode the diff is already in context.

Your job is to challenge this implementation, not approve it by default.

Required checks (evidence-based, no command execution):

1. **Acceptance criteria coverage**: for each <SPEC_PATH> Section 5 item, mark PASS / FAIL / EVIDENCE_MISSING based solely on what is recorded in Section 9. EVIDENCE_MISSING is a blocker.
2. **Do-NOT violations**: any Section 4 item the diff violates.
3. **Scope creep**: cross-reference the changed-file list with Section 2. Anything outside it (and not logged under Section 6 follow-ups) is out of scope.
4. **Focus areas for this change**: <FOCUS_AREAS>
5. **Compatibility-code drift**: grep the diff for `legacy` / `fallback` / `deprecated` / `oldFormat` / `兼容` / `旧版` and patterns like `if (version < ...)` or `catch (Old...)`. Any hit not registered in Section 8 is a violation.
6. **Project whitelist (if any)**: if CLAUDE.md or a project spec restricts allowed components / libraries / API patterns, check the diff against it.
7. **DoD evidence completeness**: Section 9.1 / 9.2 / 9.3 must contain real command tails, not "I ran it" claims or empty placeholders. 9.2 needs the screenshot + console + network triple for UI changes. Missing applicable subsection = NEEDS_CHANGES.
8. **Traceability**: every finding cites `(<SPEC_PATH> §N)` or `(diff hunk @path/file.ext:line)`.
9. **Contract drift**: compare units, scales, field names, enum values, and precision in the diff against the spec (minor vs. major currency units, seconds vs. milliseconds, snake_case vs. camelCase on the wire). Any silent conversion the spec did not ask for is a blocker — the implementer was told to report conflicts, so a bridge in the diff means that rule was broken.

Pressure-test angles (on the diff text): hidden assumptions (timezones, encoding, null handling, overflow, currency precision); races if the path is reachable concurrently; behaviour when an external dependency fails mid-operation; whether Section 6 rollback actually works; user input reaching SQL / shell / eval / filesystem unvalidated.

Output format:
- First line: "VERDICT: PASS" | "VERDICT: NEEDS_CHANGES" | "VERDICT: FAIL"
- "Acceptance criteria check" — table of Section 5 items with PASS / FAIL / EVIDENCE_MISSING and a one-line evidence reference
- "Blockers" — must fix before merge: what, where (file:line), why it matters, suggested fix
- "Nice-to-haves" — brief, non-blocking
- "Out-of-scope changes" — files outside Section 2
- "Notes"

Verdict rules:
- PASS = every Section 5 item has Section 9 evidence that demonstrably satisfies it, no Do-NOT violations, no non-trivial out-of-scope changes, no security/correctness issues visible in the diff
- NEEDS_CHANGES = correctable issues (including EVIDENCE_MISSING) but the approach is sound
- FAIL = structurally wrong, spec unimplementable as written, or unacceptable risk

Write the report to .agent/reviews/YYYY-MM-DD-<SLUG>.review.md.

This review is read-only — do not modify code, commit, switch branches, or run build/test commands.
```

Large diffs: the plugin truncates the inline diff at its `maxInlineFiles` / `maxInlineDiffBytes` budget and switches to self-collect mode, where Codex reads the diff with read-only `git diff`. Inline mode produces a more grounded review — split very large changes into smaller commits when you can.

### Variations

- **Fast path**: `/codex:review --base <BASE_BRANCH> --background` — not steerable, no focus text. §9 should still be filled.
- **Uncommitted changes** (rare, hotfixes): drop `--base`; the plugin inlines staged + unstaged + untracked diff. Say "current uncommitted changes" instead of the branch in the prompt.

## Filling `<FOCUS_AREAS>`

Always 3–5 bullets specific to the change. Without them adversarial review turns generic and noisy. Starting points:

**Money / billing / commission**
- Amounts as integers in minor units, never floats; rounding happens once, consistently across calculation and storage
- Concurrent updates: can two purchases double-spend the same balance?
- Refund path mirrors the charge path (same currency, same precision)

**Database migrations**
- Old application code can still read/write the new schema during deploy
- FK / unique constraints that could fail mid-migration on production-sized data
- The spec's rollback plan is not data-destructive; new indexes do not require extended downtime

**External API / third-party integration**
- Every outbound call expects timeout, malformed response, and rate limit
- Retries are idempotent — no duplicate resource or duplicate charge
- Webhook signature verification present and correct; credentials only from config, never hardcoded or logged

**Frontend / UI**
- No unguarded browser globals in SSR paths; no hardcoded user-facing strings outside i18n
- Labels on form fields, keyboard handlers on interactive elements
- Built from the project's existing component primitives; §9.2 triple present

**Auth / secrets**
- Secret material never logged, returned, or embedded in error messages; never plain text on disk
- Every endpoint enforces auth before doing work; change tolerates key rotation in flight

**General correctness**
- Empty / single / max-size / malformed input; off-by-one in loops and ranges; null handling
- Failure leaves the system in a consistent state

## Interpreting the report

Read `.agent/reviews/<date>-<slug>.review.md`. Reviewers feel pressure to "find something" — many blockers are false positives. For each one, form an independent opinion and categorize: **valid** / **false positive** / **evidence gap** / **need user input**. `EVIDENCE_MISSING` usually means "§9.x was not filled", not "the code is broken" — fix by filling §9 and re-triggering, not by sending the implementer back.

**Never paste the raw report.** Present:

```
Review verdict: <PASS / NEEDS_CHANGES / FAIL>

[PASS]      All acceptance criteria verified against §9 evidence. Safe to merge.
            <optional 1–2 nice-to-haves worth knowing>

[NEEDS_CHANGES]
Reviewer flagged N blockers. My assessment:
1. <blocker summary>
   → My take: valid / false positive / evidence gap (§9.x) / need your call
   → valid → re-dispatch the implementer via SendMessage (main agent does not fix by hand)
   → evidence gap → fill §9.x, re-trigger review
   → false positive → <why>
2. ...
Recommended next step: <specific action>

[FAIL]      Fundamental issues: <list>. This usually means the spec has gaps.
            Recommend returning to Phase 1 — want me to start that?
```

Then wait for the user. Accepted blockers → implementer fixes (`implement-prompt.md` § "If a check fails") → re-verify → commit → `/codex:adversarial-review` again, Codex every time.

## Don'ts

- Asking Codex to fix in the review call — it is read-only by design; fixes go to the implementer in a separate step.
- Running review on an empty branch or with empty §9.
- Forwarding every reviewer "blocker" unfiltered — that turns the review into busywork.
- Substituting a Claude reviewer because Codex is slow or rate-limited.
