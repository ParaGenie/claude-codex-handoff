# Review Prompt Template

> Read this file when entering Phase 3 of `codex-handoff` workflow. Use the template below to trigger an adversarial review of Codex's implementation.

## Before You Trigger Review (main session prep, ~1 min)

`/codex:adversarial-review --base <ref>` already injects the full branch diff, commit log, and diff-stat into Codex's prompt context (handled by the plugin's companion script, run in the **main Claude session** — not inside the Codex sandbox). You do **not** need to bundle a diff yourself.

But because Codex's sandbox cannot see `.venv` / `node_modules` / `.git`, Codex cannot independently run acceptance commands or `git diff` from within review. The reviewer can only judge what is **already in its prompt**. That makes spec Section 9 (DoD Evidence) load-bearing:

Before triggering review, the **main session** must:

1. Run every acceptance command from spec Section 5 in the host working tree and paste the tail output into spec Section 9.1 / 9.2 / 9.3.
2. Commit Section 9 alongside the implementation commit (or as a follow-up commit on the same `feat/<SLUG>` branch).
3. For UI changes, attach the screenshot + console + network triple (Section 9.2). Reviewer cannot infer these — if absent it must mark `NEEDS_CHANGES`.

If Section 9 is empty when you trigger review, the reviewer cannot verify acceptance criteria. That's a workflow bug, not a Codex bug.

---

## Standard Template

Substitute `<SLUG>`, `<SPEC_PATH>`, `<BASE_BRANCH>`, and `<FOCUS_AREAS>` then issue:

```
/codex:adversarial-review --base <BASE_BRANCH> --background

You are reviewing branch `feat/<SLUG>` against the spec at <SPEC_PATH>.

The branch diff, commit log, and diff-stat are already in your `<repository_context>` (injected by the plugin from the main session's git working tree). Use them as primary evidence.

Command-execution rules in the sandbox:
- Do NOT run git **write** commands: `commit`, `add`, `switch`, `branch`, `restore`, `stash`, `reset`, `checkout`. The sandbox blocks writes to `.git/`.
- Do NOT run build / test / lint commands (`pytest`, `npm run build`, `ruff`, etc.). The sandbox does not mount `.venv` / `node_modules`, so these resolve to `command not found`.
- Read-only `git diff / log / show` MAY be used **only when** your `<repository_context>` was delivered in "self-collect" mode (the plugin's collection guidance will explicitly tell you to inspect the diff yourself — this happens for large diffs that exceed the inline budget). For "inline-diff" mode (the default), the diff is already in your context and there is nothing for git to add.

Your job is to challenge this implementation, not approve it by default.

Required checks (all evidence-based, no command execution):

1. **Acceptance criteria coverage**: open <SPEC_PATH> Section 5 (acceptance criteria) and Section 9 (DoD Evidence already pasted by the main session). For each Section 5 item, mark PASS / FAIL / EVIDENCE_MISSING based solely on what is pasted in Section 9. EVIDENCE_MISSING is a blocker — do not pass it.
2. **Do-NOT violations**: identify any spec Section 4 item that the diff violates.
3. **Scope creep**: the changed-file list is in your `<repository_context>`. Cross-reference with spec Section 2 "Files to modify" / "Files to create". Anything outside the registered set (and not logged under Section 6 follow-ups) is out-of-scope.
4. **Focus areas for this change**: <FOCUS_AREAS>
5. **Compatibility-code drift**: grep your in-context diff for `legacy` / `fallback` / `deprecated` / `oldFormat` / `兼容` / `旧版` and semantic patterns like `if (version < ...)` or `try { ... } catch (Old...)`. Cross-reference with spec Section 8 — any pattern present that isn't registered = violation.
6. **Project-specific whitelist (if applicable)**: if the project has a whitelist spec (e.g. allowed UI components, allowed library calls, allowed API patterns) referenced from CLAUDE.md or project spec, grep the in-context diff for usage and cross-check.
7. **DoD evidence completeness**: spec Section 9.1 / 9.2 / 9.3 must contain real command tails pasted by the main session (not "I ran it" claims, not empty placeholders). 9.2 requires the screenshot + console + network triple for UI changes. Missing applicable subsection = NEEDS_CHANGES, not PASS.
8. **Spec compliance traceability**: every finding must cite `(<SPEC_PATH> §N)` or `(diff hunk @path/file.ext:line)`. Findings without traceable citation are not acceptable.

Additional pressure-test angles (apply to the diff text, not by running code):
- Hidden assumptions visible in the diff: timezones, encoding, null handling, integer overflow, currency precision
- Concurrency / race conditions if the code path is reachable from concurrent entry points
- Failure modes apparent from the diff: what happens when external dependencies fail mid-operation?
- Rollback feasibility: does spec Section 6 actually describe a working rollback, or hand-wave it?
- Security: any user input reaching SQL / shell / eval / file system without validation, visible in the diff?

Output format:
- First line: "VERDICT: PASS" or "VERDICT: NEEDS_CHANGES" or "VERDICT: FAIL"
- Section "Acceptance criteria check" — table of spec Section 5 items with PASS / FAIL / EVIDENCE_MISSING and one-line evidence reference (pointing into Section 9 paste or diff)
- Section "Blockers" — issues that must be fixed before merge. Each blocker: what, where (file:line from the diff), why it matters, suggested fix
- Section "Nice-to-haves" — non-blocking suggestions. Keep brief.
- Section "Out-of-scope changes" — anything in the changed-file list outside spec Section 2
- Section "Notes" — anything else worth knowing

Verdict rules:
- PASS = every Section 5 item has matching Section 9 evidence that demonstrably satisfies it, no Do-NOT violations, no out-of-scope changes (or only trivial ones), no security/correctness issues visible in the diff
- NEEDS_CHANGES = correctable issues exist (including EVIDENCE_MISSING) but the overall approach is sound
- FAIL = the implementation is structurally wrong, the spec is unimplementable as written, or the change creates unacceptable risk

Write the report to .agent/reviews/YYYY-MM-DD-<SLUG>.review.md.

This review is read-only — do not modify code, do not commit, do not switch branches, do not invoke build/test commands.
```

---

## Why "evidence-based, not re-run"

Earlier versions of this template instructed Codex to "actually run the commands yourself, do not trust commit messages." That worked when Codex had unrestricted shell access, but the current Codex CLI sandbox:

1. Hides `.venv` and `node_modules` from the filtered working tree (so `pytest`, `ruff`, `npm run build`, `node_modules/.bin/*` all `command not found`)
2. Blocks writes to `.git/` (so `git commit / add / switch / branch / reset` fail on `index.lock`). Read-only `git diff / log / show` are not blocked.

Asking Codex to run build/test commands inside review produces noise: it tries, fails, falls back to guessing, and the verdict becomes less reliable than if it had simply read the evidence the main session already gathered.

The fix: the **main session** runs verify in the host working tree (full `.venv` / `node_modules` access) and pastes the tails into spec Section 9. Codex review then evaluates *whether the pasted evidence demonstrates the acceptance criterion*, which is a stronger consistency check than "I ran it and it passed."

### Large-diff caveat

The plugin truncates inline diff at ~`maxInlineFiles` / `maxInlineDiffBytes`. When the change is bigger than that, the plugin switches to "self-collect" mode — `<repository_context>` contains only the changed-file list, and the plugin's own collection guidance tells the reviewer to inspect the diff with read-only `git diff` itself (which the sandbox permits). The review prompt above honors that: git **reads** are allowed; git **writes** and build/test commands remain off-limits.

If you're shipping a very large change and worried about reviewer reliability, prefer splitting it into smaller logical commits — the inline-diff path produces a more grounded review than self-collect.

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
- Section 9.2 triple present? Page screenshot + console clean + network 2xx — all three required for UI tasks.
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

Note: `/codex:review` is not steerable and does not take focus text. Use only for low-risk sanity checks. Same sandbox limits apply — main session should still have filled Section 9 before triggering.

### Variation: review without a base branch (uncommitted changes)

If implementation hasn't been pushed to a branch yet (rare in this workflow, but happens for hotfixes), the plugin's working-tree mode inlines staged + unstaged + untracked diff into the prompt:

```
/codex:adversarial-review --background

[... rest of standard template, but mention "current uncommitted changes" instead of branch ...]
```

---

## What Claude Should Do While Review Runs

- **Poll `/codex:status` every 120 seconds proactively** — do not wait for the user to ask. After each poll, surface a one-liner to the user: `[poll T+Nmin] codex <task-id> state=<running|completed|error> last=<short summary>`.
- Track `state` + `last-message` hash across polls — needed for stall detection (next section).
- Do NOT read the in-progress review report; it pollutes your own triage in Step 1 of "Interpreting the Report".
- Continue conversation with the user on other topics — the poll cadence runs alongside.

---

## If Review Stalls

Unlike Phase 2 (rescue), Phase 3 (review) has a built-in self-heal path because the deliverable is a *judgment report*, not source-file edits — and a general-purpose Claude subagent with full shell + git access can produce that judgment without breaking the double-model implementation split.

### Stuck signal (either is sufficient)

1. `/codex:status` returns `error / timeout / failed` explicitly.
2. Two consecutive polls (≈4 min) show no progress: `elapsed` advances, but `state` and `last-message` hash stay identical.

### Self-heal decision tree

```
Stuck signal triggered in this review cycle
    │
    ├─ 1st stall this cycle
    │     → /codex:cancel
    │     → re-issue /codex:adversarial-review --background with the same args
    │     → treat as transient flake (network blip, sandbox hiccup, CoT loop)
    │     → resume 120s polling
    │
    └─ 2nd stall this cycle
          → /codex:cancel
          → spawn general-purpose subagent to take over the review (template below)
          → do NOT retry codex again in this cycle
          → wait for subagent's report, then drop back into "Interpreting the Report"
```

### Fallback subagent template

When the 2nd stall fires, invoke:

```
Agent(
  subagent_type="general-purpose",
  description="Fallback adversarial review after codex stalled",
  prompt=<the template below>
)
```

Template body (substitute `<SLUG>`, `<SPEC_PATH>`, `<BASE_BRANCH>`, `<FOCUS_AREAS>`):

```
You are reviewing branch `feat/<SLUG>` against the spec at <SPEC_PATH>. The
previous Codex review attempt stalled twice; you are the fallback reviewer.

You have full shell + git access. Use it:
- Run `git diff <BASE_BRANCH>...HEAD` to read the full branch diff yourself.
- Re-run spec Section 9.1 / 9.2 / 9.3 acceptance commands in the host working
  tree. Cross-check the pasted §9 evidence against what you actually observe.
  If the pasted evidence and your re-run disagree (different command tail,
  different exit code, different screenshot state), that disagreement IS a
  blocker — call it out explicitly with both observations side-by-side.

[... paste the body of the Standard Template here, minus the sandbox-rule
paragraph that starts with "Command-execution rules in the sandbox:" — those
restrictions are Codex-specific and do not apply to you. Keep the Required
checks (1-8), Additional pressure-test angles, Output format, and Verdict
rules verbatim. <FOCUS_AREAS> still applies. ...]

Write the report to .agent/reviews/YYYY-MM-DD-<SLUG>.review.fallback.md (note
the `.fallback` suffix — it distinguishes a Claude-side fallback review from
a codex-produced review on disk and in commit history).

This review is read-only — do not modify source code, do not commit, do not
switch branches. (You may run build/test/lint commands for verification, which
codex couldn't — that's the whole reason you're the fallback.)
```

### After the fallback report lands

Read `.agent/reviews/<slug>.review.fallback.md` and drop straight into the "Interpreting the Report" section below — the PASS / NEEDS_CHANGES / FAIL triage rules are identical. When relaying to the user, mention the fallback path in one line: "Codex review stalled twice; fallback review by general-purpose subagent. Verdict still actionable, but the model independence is weaker than a fresh-Codex review (Claude reviewed Claude-orchestrated work)."

### Trade-off note

Fallback review loses the "fresh second model" property that makes the standard Phase 3 valuable. If the change is high-stakes (money/billing/auth/migrations) and both codex attempts stalled, consider asking the user whether to ship on the fallback verdict or wait and retry codex from a clean state — explicitly surface the choice rather than auto-shipping.

---

## Interpreting the Report

When the review report arrives (read it from `.agent/reviews/<slug>.review.md`):

### Step 1: Apply Claude's own judgment

**Reviewers over-produce.** LLM reviewers feel pressure to "find something" — many blockers are false positives. For each blocker:

1. Read it
2. Form an independent opinion: is this actually a problem in this context?
3. Categorize: **valid** / **false positive** / **uncertain — need user input**

Pay special attention to `EVIDENCE_MISSING` items — they often mean "main session forgot to fill Section 9.x", not "the implementation is broken." If so, fix by filling Section 9 + re-trigger review, not by sending Codex back to fix code.

### Step 2: Filter, then present to user

**Never paste the raw report.** Distill into this structure:

```
Review verdict: <PASS / NEEDS_CHANGES / FAIL>

[If PASS]
All acceptance criteria verified against Section 9 evidence. Safe to merge.
[Optional: 1-2 nice-to-haves worth knowing about, if any]

[If NEEDS_CHANGES]
Reviewer flagged N blockers. My assessment:

1. <Blocker 1 summary>
   → My take: valid / false positive / evidence-gap (Section 9.x missing) / need your call
   → If valid code issue: recommend fix via /codex:rescue --resume OR Claude fixes directly
   → If evidence gap: main session fills Section 9.x, re-trigger review (no Codex re-run needed)
   → If false positive: reasoning is <why>

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

### ❌ Triggering review with empty Section 9

Section 9 evidence is the **only** ground truth the reviewer has for acceptance criteria — the sandbox cannot re-run commands. Main session must fill it before triggering. Otherwise the verdict is unreliable and you'll just get back `EVIDENCE_MISSING` blockers across the board.

### ❌ Asking Codex to re-run build/test commands inside review

The current Codex sandbox cannot run `pytest`, `npm run build`, `node_modules/.bin/*`, etc. — they resolve to `command not found`. Instructing the reviewer to "run the test yourself" wastes a turn and produces a less reliable verdict than evidence-based review. (Read-only `git diff` is permitted but only useful in self-collect mode for large diffs.)

### ❌ Asking Codex to fix as part of the review prompt

`/codex:adversarial-review` is read-only by design. Don't try to make it both reviewer and fixer in the same call — you lose the separation that makes this workflow valuable. Fixes happen via `/codex:rescue --resume` in a separate step.
