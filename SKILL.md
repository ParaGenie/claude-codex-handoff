---
name: codex-handoff
description: Three-phase collaboration workflow between Claude Code (planner/decision-maker) and Codex CLI (implementer/reviewer) via the codex-plugin-cc plugin. Use whenever a coding task involves multiple files, new modules, cross-cutting refactors, business logic changes, or anything that warrants a written spec and a review pass before merging. Trigger when the user asks to "plan and implement", "走交付流程", "write a spec", says "let Codex do it" / "让 Codex 实现", or starts any change touching > 1 file with real business logic. Skip for typo fixes, single-line tweaks, exploratory questions, and pure discussion. Coordinates spec authoring, /codex:rescue delegation, /codex:adversarial-review challenge passes, and the decision tree after review reports come back.
license: MIT
---

# Codex Handoff Workflow

Coordinate Claude Code (planner) + Codex CLI (implementer/reviewer) through the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin. All communication happens inside one Claude Code session via `/codex:*` slash commands.

**Default division of labor:**

| Role | Who | How | What |
|---|---|---|---|
| **Planner** | Claude (you) | Natural dialogue | Probe code, write spec, interpret reviews, make calls |
| **Implementer** | Codex | `/codex:rescue` | Read spec, change code, list acceptance commands in spec Section 9 |
| **Verifier + git driver** | Claude (main session) | direct shell + Edit | Pre-create `feat/<SLUG>` branch, run acceptance commands, paste output into Section 9, `git add` + `git commit` |
| **Reviewer** | Codex (fresh session) | `/codex:adversarial-review` | Evaluate diff + Section 9 evidence against spec, write report |

**Core principle:** Claude does not write implementation code directly unless the task is truly small (< 30 lines, single file, no business logic). Claude's value is in planning, interpretation, judgment, and bridging the Codex sandbox limits (see below).

**Codex sandbox limits (shape the division of labor above):**

1. `.git/` is read-only — Codex cannot `switch / branch / add / commit`. The main session creates `feat/<SLUG>` before `/codex:rescue` and commits after.
2. `.venv` / `node_modules` are not mounted into the sandbox — Codex cannot run `pytest`, `npm run build`, `ruff`, etc. The main session executes acceptance commands in the host working tree and pastes output into spec Section 9.

These limits are unconfigurable in the current Codex CLI. The workflow is designed around them rather than against them.

---

## When to Use This Workflow

Use **full three-phase flow** for:

- Multi-file changes with real business logic
- New modules or features (even small ones)
- Cross-cutting refactors
- Anything touching: money / billing / commission, user data, production DB migrations, supplier integrations, auth
- Anything the user explicitly says "go through the process" / "走流程" for

**Skip the workflow** for:

- Typo fixes, single-line tweaks, comment edits
- Pure exploration ("show me how X works")
- Discussion-only turns (no code change at the end)
- Trivial scripts the user wants you to write inline as a one-off

**Middle ground** (small but non-trivial, e.g. < 30 lines single-file change):

- Claude implements directly
- Skip Phase 2 (`/codex:rescue`)
- Still run `/codex:review` (lighter than adversarial) as a sanity check before commit

---

## The Three-Phase Loop

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 1: PLAN  (Claude)                                    │
│  Probe → clarify → write .agent/specs/<slug>.md → STOP      │
└──────────────────────────┬──────────────────────────────────┘
                           │ User explicitly confirms spec
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 2: IMPLEMENT  (split between Codex and main session) │
│  2a. Main:  git switch -c feat/<slug> <base>                │
│  2b. Codex: read spec → edit files → list cmds in §9 → done │
│             (no git, no shell execution)                    │
│  2c. Main:  run §9 commands → paste tails → git commit      │
└──────────────────────────┬──────────────────────────────────┘
                           │ Section 9 filled, commit on branch
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 3: REVIEW  (Codex via /codex:adversarial-review)     │
│  Plugin auto-injects diff + commit log → Codex evaluates    │
│  against spec + §9 evidence → .agent/reviews/<slug>.md      │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       PASS → recommend merge    NEEDS_CHANGES → triage with user
                                 FAIL → likely re-plan
```

---

## PHASE 1: Plan

### What Claude must do

1. **Probe first, don't assume.** Use `view` / `grep` / read relevant `docs/`. Read whichever project-specific design docs are pinned in `CLAUDE.md` under "Key Docs". For DB work read `docs/db-schema.md` if it exists.

2. **Ask clarifying questions when uncertain.** Don't guess. Things worth asking:
   - Edge cases (concurrency, failure modes, partial states)
   - Whether existing users / data are affected
   - Backward compatibility needs
   - Acceptance criteria ("how do we know it's done right?")

3. **Write the spec to `.agent/specs/YYYY-MM-DD-<slug>.md`** using the template in `spec-template.md` (read that file when ready to write a spec).

4. **After writing, do not summarize the spec in chat.** Just say:

   > Spec written: `.agent/specs/2026-05-21-<slug>.md`. Please review and reply "approved" to hand off to Codex.

5. **Wait for explicit user approval** before Phase 2. Do not auto-advance.

### Slug naming

Use kebab-case, short, descriptive. Good: `stale-items-indicator`, `order-refund-rounding-fix`, `webhook-signature-verify`. Bad: `fix-bug`, `changes`, `feature-1`.

---

## PHASE 2: Implement

### 2a. Main session: pre-flight (~30s)

Before `/codex:rescue`:

```bash
git switch -c feat/<SLUG> <BASE_BRANCH>
```

Codex will see this branch as the current HEAD. Confirm `.venv` / `node_modules` are installed in the host working tree (you will run verify against them later).

### 2b. Claude's standard handoff prompt

Read `rescue-prompt.md` for the template. The short version:

```
/codex:rescue --background <full prompt from rescue-prompt.md with spec path substituted>
```

**Always use `--background`** for non-trivial tasks — implementation often takes 10-30 minutes and front-running blocks the Claude Code session for nothing.

Critical: the rescue prompt must include the "no git, no shell execution" rules from `rescue-prompt.md` Rules 1 and 4. The plugin sandbox enforces them; the prompt makes it explicit so Codex doesn't waste retries.

### While Codex works

- **Do not read the diff.** Reading creates implementation bias that pollutes Phase 3 interpretation.
- Continue discussing other topics with the user if they want.
- **Actively poll `/codex:status` every 120 seconds** without waiting for the user to ask. After each poll, surface a one-liner to the user: `[poll T+Nmin] codex <task-id> state=<running|completed|error> last=<short summary>`. This is status metadata only — it does NOT read the diff and does not conflict with the rule above.
- **Stall detection (Phase 3 self-heal trigger).** Track `state` + `last-message` hash across polls. "No progress" = `elapsed` advances but `state` and `last-message` hash stay identical across two consecutive polls (~4 min). Combined with an explicit `error / timeout / failed` state, this is the stuck signal. For Phase 2 (rescue) stalls, hand the call back to the user (see `rescue-prompt.md` § "If Codex rescue stalls"). For Phase 3 (review) stalls, follow the self-heal decision tree in `review-prompt.md` § "If Review Stalls".
- On request, run `/codex:cancel` to abort.

### 2c. Main session: post-Codex verify + commit

Run `/codex:result` to fetch the output. Then, **before** advancing to Phase 3:

1. **Do not critique code quality.** That's the Reviewer's job in Phase 3.
2. Read Codex's report: file list + command lines pasted into spec Section 9.1 / 9.2 / 9.3.
3. Run each Section 9 command in the host working tree. Paste actual tails (~30 lines per command) under each `$ <command>` line in the spec.
4. For UI tasks (Section 9.2 screenshot + console + network): hand off to the user — background sessions cannot drive a browser.
5. `git add <Section-2-files>` + `git commit -m "<task>: implement per spec"` on `feat/<SLUG>`.
6. If any acceptance command failed, do not advance to Phase 3 — go back to Codex via `/codex:rescue --resume` with the failure paste. See `rescue-prompt.md` "If acceptance commands fail" section.

Only when Section 9 is complete and commit is on the branch, proceed to Phase 3.

---

## PHASE 3: Review

### What the plugin already does for you

`/codex:adversarial-review --base <ref>` runs the plugin's companion script **in the main Claude session** (not inside Codex's sandbox), which auto-collects the branch diff, commit log, and diff-stat from the host working tree and inlines them into Codex's prompt under `<repository_context>`. The reviewer reads the full diff as primary evidence — you do NOT need to bundle anything yourself.

What the reviewer **cannot** do (sandbox-limited):

- Run `git diff` against `.git/` (lock files are blocked)
- Run `pytest` / `npm run build` / lint commands (`.venv` / `node_modules` invisible)
- Re-verify acceptance criteria by execution

So the reviewer's only source of acceptance-criterion truth is **spec Section 9 evidence the main session pasted in Phase 2c**. If Section 9 is empty when you trigger review, the verdict will be unreliable.

### Why adversarial, not regular review

| Command | When |
|---|---|
| `/codex:review` | Generic PR-quality review. Not steerable. Use for tiny tasks or as a final sanity check. |
| `/codex:adversarial-review` | **Default for this workflow.** Challenges design choices, hidden assumptions, failure modes. Steerable via focus text. |

### Claude's standard review prompt

Read `review-prompt.md` for the full template. It accepts `--base <ref>` for branch review and supports `--background`.

### Decision tree on review report

```
While review runs: poll /codex:status every 120s, report [poll T+Nmin] one-liner.
    │
    ├─ STUCK             → Review never produces a report.
    │                       Trigger: explicit error/timeout state OR two consecutive
    │                       polls with no progress (state + last-message hash stable
    │                       while elapsed advances).
    │                       1st stall in this review cycle → /codex:cancel, then
    │                         re-issue /codex:adversarial-review with the same args
    │                         (treat as transient flake).
    │                       2nd stall in the same review cycle → /codex:cancel, then
    │                         spawn general-purpose subagent to take over the review
    │                         (no further codex retries this cycle).
    │                       Full decision tree + fallback subagent prompt template:
    │                         see review-prompt.md § "If Review Stalls".
    │                       Once a report (codex or .review.fallback.md) lands, fall
    │                       through to PASS / NEEDS_CHANGES / FAIL below.
    │
    └─ Read .agent/reviews/<slug>.review.md (or .review.fallback.md)
        │
        ├─ PASS              → Tell user: "Review passed, safe to merge."
        │                       Optionally summarize 0-2 nits if any worth knowing.
        │
        ├─ NEEDS_CHANGES     → For each blocker, form own judgment:
        │                       "Reviewer says X. I think [valid / false positive] because Y.
        │                        Recommend [accept / push back / ask user]."
        │                       Then ask user how to proceed:
        │                       a) /codex:rescue --resume <fix instructions>
        │                       b) Claude fixes directly (if small)
        │                       c) Override the blocker
        │
        └─ FAIL              → Likely the spec itself is flawed.
                               Tell user: "Review failed because <reasons>. Recommend
                                going back to Phase 1 to refine the spec." Get user agreement
                                before re-planning.
```

### Critical: filter reviewer noise

LLM reviewers over-produce. **Never paste the raw review report to the user.** Read it, distill it, present:

- 1-line verdict
- Numbered list of blockers (with Claude's own judgment on each)
- "Nice-to-haves" mentioned in passing if any matter
- A clear next-action question

---

## Slash Command Cheatsheet

```bash
# Setup (once per project / machine)
/codex:setup                              # Check Codex availability
!codex login                              # Auth if needed

# Implement
/codex:rescue --background <prompt>       # Delegate, run in background (default)
/codex:rescue --resume <prompt>           # Continue last rescue task
/codex:rescue --model gpt-5.5 --effort medium <prompt>       # Explicit model pin (default if .codex/config.toml set)

# Review
/codex:adversarial-review --base develop --background <focus>  # Default
/codex:review --background                # Lighter, non-steerable

# Background job management
/codex:status                             # All running/recent jobs
/codex:status <task-id>                   # Specific job
/codex:result                             # Latest completed result
/codex:cancel                             # Abort current background job
```

---

## Anti-Patterns (Do Not Do)

### ❌ Mixing plan and implement

Wrong: Claude starts editing files while discussing the approach.
Right: Finish spec, wait for approval, then `/codex:rescue`.

### ❌ Same Codex session for implement + review

Wrong: Implement, then ask the same Codex "did you do it right?"
Right: `/codex:adversarial-review` starts a fresh session with clean context.

### ❌ Spec written like pseudocode

Wrong: Spec contains 50 lines of implementation code.
Right: Spec says "add Y validation in function X, handle edge case Z" and lets Codex write the actual code.

### ❌ Vague acceptance criteria

Wrong: "Code quality good, performance OK"
Right: "`<test command>` passes; manual test: set `updated_at` to now-25h via SQL, refresh page, stale badge appears on the affected row."

### ❌ Pasting review reports verbatim

Wrong: Copy the whole `.review.md` into chat.
Right: Distill to 3-5 bullets with Claude's own take.

### ❌ Auto-advancing without user approval

Wrong: Write spec → immediately `/codex:rescue` because it "looked fine".
Right: Always wait for explicit user "approved" / "通过" between phases.

### ❌ Enabling the review gate

Wrong: `/codex:setup --enable-review-gate` — official README warns this creates long agent loops and drains usage quotas. This workflow is already gate-equivalent through Phase 3, no need.

### ❌ Expecting Codex sandbox to run git or verify commands

Wrong: rescue prompt says "create branch", "run pytest", "commit when done" — Codex tries, sandbox blocks, you lose 5 minutes of compute on failed attempts.
Right: main session creates branch before `/codex:rescue`, Codex only edits files + lists commands in Section 9, main session runs verify + commits afterward. See `rescue-prompt.md` Sandbox Reality Check.

### ❌ Triggering Phase 3 review with empty Section 9

Wrong: skip the verify step in Phase 2c, hand straight to review — reviewer cannot execute commands, so it returns `EVIDENCE_MISSING` blockers across the board, wasted review run.
Right: main session fills Section 9.1 / 9.2 / 9.3 before `/codex:adversarial-review`. The reviewer's verdict quality is bounded by the evidence you give it.

### ❌ Silently waiting while background Codex runs

Wrong: kick off `/codex:rescue --background` or `/codex:adversarial-review --background`, then go quiet until the user asks "is it done yet?". The main session looks dead and silent stalls go undetected for 20+ minutes.
Right: main session polls `/codex:status` every 120s without prompting, reports `[poll T+Nmin] state=...` each tick. If two consecutive polls show no progress (state + last-message hash stable) OR status returns `error / timeout / failed`: Phase 3 (review) takes the self-heal branch in `review-prompt.md` § "If Review Stalls"; Phase 2 (rescue) hands the call back to the user per `rescue-prompt.md` § "If Codex rescue stalls" (rescue does NOT auto-fall-back to a subagent — that would break the double-model implementation split).

---

## Repository Layout

```
项目根/
├── CLAUDE.md                    # Project identity card (10-15 lines, see CLAUDE.md template)
├── .codex/
│   └── config.toml              # Optional: pin model/effort for this project
└── .agent/
    ├── specs/
    │   └── YYYY-MM-DD-<slug>.md       # Specs (commit to git)
    └── reviews/
        └── YYYY-MM-DD-<slug>.review.md  # Review reports (commit to git)
```

**Commit `.agent/` to git.** Specs and reviews are design history — valuable to future-you and future agents.

---

## Project-Specific Notes

Stack-specific rules, project glossaries, third-party integration names, hand-off lists, and "who must personally validate this" conventions all belong in the project's own `CLAUDE.md` (see `CLAUDE.md.template`), not here. This skill stays language- and project-agnostic by design.

For code-level conduct (assumptions, simplicity, surgical changes), the `karpathy-guidelines` skill complements this one — this skill defines the workflow, karpathy defines the code conduct.

---

## Files in This Skill

- **`SKILL.md`** (this file) — workflow definition, decision rules, command reference
- **`spec-template.md`** — load when writing a spec in Phase 1
- **`rescue-prompt.md`** — load when delegating to Codex in Phase 2
- **`review-prompt.md`** — load when triggering review in Phase 3
- **`CLAUDE.md.template`** — minimal per-project CLAUDE.md to copy into new projects