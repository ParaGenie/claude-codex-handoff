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
| **Implementer** | Codex | `/codex:rescue` | Read spec, change code, run tests, commit to branch |
| **Reviewer** | Codex (fresh session) | `/codex:adversarial-review` | Challenge implementation against spec, write report |

**Core principle:** Claude does not write implementation code directly unless the task is truly small (< 30 lines, single file, no business logic). Claude's value is in planning, interpretation, and judgment — let Codex execute.

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
│  PHASE 2: IMPLEMENT  (Codex via /codex:rescue --background) │
│  Codex reads spec → branch → code → tests → commit → done   │
└──────────────────────────┬──────────────────────────────────┘
                           │ Codex finishes
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 3: REVIEW  (Codex via /codex:adversarial-review)     │
│  Fresh session → challenge against spec → .agent/reviews/   │
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

### Claude's standard handoff prompt

Read `rescue-prompt.md` for the template. The short version:

```
/codex:rescue --background <full prompt from rescue-prompt.md with spec path substituted>
```

**Always use `--background`** for non-trivial tasks — implementation often takes 10-30 minutes and front-running blocks the Claude Code session for nothing.

### While Codex works

- **Do not read the diff.** Reading creates implementation bias that pollutes Phase 3 interpretation.
- Continue discussing other topics with the user if they want.
- On request, run `/codex:status` to check progress.
- On request, run `/codex:cancel` to abort.

### When Codex finishes

Run `/codex:result` to fetch the output. Then:

1. **Do not critique code quality.** That's the Reviewer's job in Phase 3.
2. Confirm only: branch created, commits present, acceptance commands executed.
3. Proceed directly to Phase 3 unless something is structurally broken (e.g. no branch was created, no commits exist — these warrant going back to Phase 2 with corrective instructions rather than running a review on nothing).

---

## PHASE 3: Review

### Why adversarial, not regular review

| Command | When |
|---|---|
| `/codex:review` | Generic PR-quality review. Not steerable. Use for tiny tasks or as a final sanity check. |
| `/codex:adversarial-review` | **Default for this workflow.** Challenges design choices, hidden assumptions, failure modes. Steerable via focus text. |

### Claude's standard review prompt

Read `review-prompt.md` for the full template. It accepts `--base <ref>` for branch review and supports `--background`.

### Decision tree on review report

```
Read .agent/reviews/<slug>.review.md
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