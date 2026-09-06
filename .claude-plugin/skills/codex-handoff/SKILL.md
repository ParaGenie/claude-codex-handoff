---
name: codex-handoff
description: Three-phase collaboration workflow between Claude Code (planner / implementer via subagent) and Codex CLI (adversarial reviewer) via the codex-plugin-cc plugin. Use whenever a coding task involves multiple files, new modules, cross-cutting refactors, business logic changes, or anything that warrants a written spec and a cross-model review pass before merging. Trigger when the user asks to "plan and implement", "走交付流程", "write a spec", or starts any change touching > 1 file with real business logic. Skip for typo fixes, single-line tweaks, exploratory questions, and pure discussion. Coordinates spec authoring, implementer-subagent delegation, host verification, /codex:adversarial-review challenge passes, and the decision tree after review reports come back.
license: MIT
---

# Codex Handoff Workflow

Coordinate Claude Code (planner + implementer-by-subagent) and Codex CLI (reviewer) through the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin. Implementation is done by a Claude subagent spawned from the main session; review is done by Codex via `/codex:*` slash commands in the same session.

**Default division of labor:**

| Role | Who | How | What |
|---|---|---|---|
| **Planner / orchestrator** | Claude (main agent, you) | Natural dialogue + spawn subagents + `/codex:*` | Probe code, write spec, dispatch work, record results, interpret reviews, drive git (branch + commit) |
| **Implementer** | Claude subagent (host) | `Agent(subagent_type="general-purpose")` | Read spec, change code in the host working tree, list acceptance commands in spec Section 9 |
| **Verifier** | Claude subagent (host, fresh) | spawned subagent, separate from the implementer | Run Section 9 acceptance commands in the host working tree, report output tails back to the main agent |
| **Reviewer** | Codex (fresh session) | `/codex:adversarial-review` | Evaluate diff + Section 9 evidence against spec, write report |

**Core principle: the main agent only dispatches and coordinates — it never touches the target codebase or runs verify with its own hands.** Every implementation-file edit goes to the implementer subagent; every verify-command execution goes to a separate host subagent. This holds even for a one-line fix — there is no "small enough to just do it myself" exception. The main agent's hands stay on: planning, interpretation, judgment, authoring the spec/review artifacts (recording the verifier's output into Section 9 is artifact-authoring, not a code edit), and driving git (branch + commit — git is the orchestration glue).

**Cross-model rule (the one that makes Phase 3 worth anything): implementation and review must never be the same model.** Claude implements (main agent orchestrating, subagent editing), Codex reviews. Two Claude subagents are "different agents" on paper but the same model in practice — that does not count as independent review. Consequently:

- The reviewer is **always Codex**. There is no Claude-subagent fallback for review — not on stall, not on quota exhaustion, not "just this once". If Codex cannot review right now, the task waits (see `review-prompt.md` § "If Review Stalls").
- Implementation never goes to Codex in this workflow. `/codex:rescue` is not part of the loop any more; the only `/codex:*` commands used are `review`, `adversarial-review`, `status`, `result`, `cancel`.

### Why the implementer is a subagent, not Codex

Earlier versions of this workflow delegated implementation to Codex via `/codex:rescue`. That split cost more than it returned: the Codex sandbox cannot run git or the project's build/test tools, hits usage quotas mid-task, occasionally cannot write outside the repo and needs a manual patch, and every dispatch needed a hand-written English prompt plus polling. A Claude subagent running in the host working tree has full shell + git visibility, no quota wall, and needs no prompt translation. Speed is roughly equal — the bottleneck is host verification either way. What is lost is one layer of independent perspective during implementation; that is why the Codex review in Phase 3 is now non-negotiable.

### Codex sandbox constraints (review only)

These still apply to the Codex **reviewer**:

1. `.git/` is read-only — Codex cannot write to git. It reads the diff the plugin injects; it does not switch branches or commit.
2. `.venv` / `node_modules` are not mounted into the sandbox — Codex cannot run `pytest`, `npm run build`, `ruff`, etc. Its only source of acceptance truth is the Section 9 evidence recorded in Phase 2c.

They no longer constrain implementation, because the implementer subagent runs on the host.

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

- The main agent still does **not** edit files itself — spawn a general-purpose subagent to make the edit (fast path: skip the spec, hand the subagent a precise instruction instead)
- A separate host subagent runs the acceptance command(s) and reports the tails
- Still run `/codex:review` (lighter than adversarial) as a sanity check before the main agent commits — the cross-model rule holds even on the fast path

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
│  PHASE 2: IMPLEMENT  (Claude subagent edits, another        │
│                        subagent verifies)                   │
│  2a. Main:       git switch -c feat/<slug> <base>           │
│  2b. Implementer: read spec → edit files → list cmds in §9  │
│                   → report (no git commit)                  │
│  2c. Verifier:   run §9 cmds on host → report tails         │
│      Main:       record tails into §9 → git commit          │
└──────────────────────────┬──────────────────────────────────┘
                           │ Section 9 filled, commit on branch
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 3: REVIEW  (Codex via /codex:adversarial-review)     │
│  Plugin auto-injects diff + commit log → Codex evaluates    │
│  against spec + §9 evidence → .agent/reviews/<slug>.md      │
│  Reviewer is ALWAYS Codex — never a Claude subagent         │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       PASS → recommend merge    NEEDS_CHANGES → triage with user
                                 FAIL → likely re-plan
```

---

## Cross-Session Resume Anchor

Only when the workflow must cross a session boundary (context compaction, a background job wrapping up, or the user stepping away mid-phase), write `.agent/handoff.md` (gitignored). It contains transient resume state only: current phase, active slug, spec path (reference; do not copy spec content), branch + base branch, implementer subagent name / Codex review task-id if any, pending blockers / failed acceptance / next action, and a `Suggested skills:` line for the next session (for example `codex-handoff` plus any project skill). Redact secrets, keys, and PII. Durable design lives in the committed spec; this file is only a resume pointer. The next session deletes or overwrites `.agent/handoff.md` once it has resumed, so a stale pointer never lingers. (source: `handoff` skill)

---

## PHASE 1: Plan

### What Claude must do

1. **Probe first, don't assume.** Use `view` / `grep` / read relevant `docs/`. Read whichever project-specific design docs are pinned in `CLAUDE.md` under "Key Docs". For DB work read `docs/db-schema.md` if it exists.

2. **Grill uncertain plans before writing the spec** (source: `grill-me` skill):
   - Walk the task's decision tree one branch at a time; resolve prerequisites before dependent choices.
   - If code/docs can answer the question, read them instead of asking.
   - Ask **one** question at a time, each with your recommended answer; make it a confirm/reject choice.
   - Continue until edge cases, user/data impact, backward compatibility, and acceptance criteria are resolved.
   - Feed those answers into spec §1 (WHY), §4 (Do NOT), and §5 (acceptance).
   - Scale to risk: skip when already unambiguous; grill hard for money/auth/data/migrations.

3. **Write the spec to `.agent/specs/YYYY-MM-DD-<slug>.md`** using the template in `spec-template.md` (read that file when ready to write a spec).

4. **After writing, do not summarize the spec in chat.** Just say:

   > Spec written: `.agent/specs/2026-05-21-<slug>.md`. Please review and reply "approved" to start implementation.

5. **Wait for explicit user approval** before Phase 2. Do not auto-advance.

### Slug naming

Use kebab-case, short, descriptive. Good: `stale-items-indicator`, `order-refund-rounding-fix`, `webhook-signature-verify`. Bad: `fix-bug`, `changes`, `feature-1`.

---

## PHASE 2: Implement

### 2a. Main agent: pre-flight (~30s)

Before spawning the implementer:

```bash
git switch -c feat/<SLUG> <BASE_BRANCH>
```

The implementer subagent will see this branch as the current HEAD. Confirm `.venv` / `node_modules` are installed in the host working tree (both the implementer and the verifier run against them). If the session is in a worktree, hand the subagent the **worktree path**, not the main checkout — a subagent given the main-repo path edits a stale copy.

### 2b. Spawn the implementer subagent

Read `implement-prompt.md` for the template. The short version:

```
Agent(
  subagent_type="general-purpose",
  description="Implement <SLUG> per spec",
  prompt=<full prompt from implement-prompt.md with spec path / branch / working-tree path substituted>
)
```

The subagent runs in the background; the harness notifies the main agent when it finishes. Critical: the prompt must carry the "no git commit, only Section 2 files, Section 9 command lines" rules from `implement-prompt.md` — the subagent has full host access, so the discipline comes from the prompt, not from a sandbox.

### While the implementer works

- **Do not read the diff.** Reading creates implementation bias that pollutes Phase 3 interpretation — and now that the implementer is the same model as the orchestrator, the main agent's "self-review" of the diff is worth even less than before. Save your judgment for triaging the Codex report.
- Continue discussing other topics with the user if they want.
- **Stall check every 300 seconds**, not more often: look only at `git status --short` (file list, not content) and the subagent's task state. Two consecutive checks with no new/changed files and no state change = stuck. Do **not** poll on a shorter loop — completion is delivered by notification.
- **Trust files, not notifications.** A completion notification can arrive with a fabricated summary. Before advancing, confirm with `git status --short` that the files the subagent claims to have edited actually changed.
- If the subagent stalls or the user wants to abort: stop it, then re-dispatch with a sharper prompt (see `implement-prompt.md` § "If the implementer stalls"). Never take over the edit yourself.

### 2c. Main agent: post-implementation verify (via subagent) + commit

When the implementer reports back, **before** advancing to Phase 3:

1. **Do not critique code quality.** That's the Reviewer's job in Phase 3.
2. Read the implementer's report: file list + command lines pasted into spec Section 9.1 / 9.2 / 9.3. Cross-check the file list against `git status --short`.
3. **Spawn a separate host subagent to run verify** — not the implementer, and not yourself. Hand it the Section 9 command lines; it executes them in the host working tree and reports the tails (~30 lines per command). The main agent then records each tail under the matching `$ <command>` line in the spec (recording into the spec artifact is orchestration, not a code edit). Keeping implementer and verifier separate means the evidence Codex reads was not produced by the hands that wrote the code.
4. For UI tasks (Section 9.2 screenshot + console + network): hand off to the user — background sessions cannot drive a browser.
5. `git add <Section-2-files>` + `git commit -m "<task>: implement per spec"` on `feat/<SLUG>` (git stays with the main agent).
6. If any acceptance command failed, do not advance to Phase 3 — send the failure paste back to the implementer subagent (`SendMessage` to the same subagent keeps its context; a fresh `Agent` call if it has been torn down). See `implement-prompt.md` "If acceptance commands fail".

Only when Section 9 is complete and commit is on the branch, proceed to Phase 3.

---

## PHASE 3: Review

### What the plugin already does for you

`/codex:adversarial-review --base <ref>` runs the plugin's companion script **in the main Claude session** (not inside Codex's sandbox), which auto-collects the branch diff, commit log, and diff-stat from the host working tree and inlines them into Codex's prompt under `<repository_context>`. The reviewer reads the full diff as primary evidence — you do NOT need to bundle anything yourself.

What the reviewer **cannot** do (sandbox-limited):

- Run `git diff` against `.git/` (lock files are blocked)
- Run `pytest` / `npm run build` / lint commands (`.venv` / `node_modules` invisible)
- Re-verify acceptance criteria by execution

So the reviewer's only source of acceptance-criterion truth is **the Section 9 evidence the main agent recorded in Phase 2c** (run by the host verify subagent, recorded by the main agent). If Section 9 is empty when you trigger review, the verdict will be unreliable.

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
    ├─ STUCK / QUOTA    → Review never produces a report.
    │                       Trigger: explicit error/timeout/quota state OR two consecutive
    │                       polls with no progress (state + last-message hash stable
    │                       while elapsed advances).
    │                       1st stall in this review cycle → /codex:cancel, then
    │                         re-issue /codex:adversarial-review with the same args
    │                         (treat as transient flake).
    │                       2nd stall, or an explicit usage-limit message → /codex:cancel,
    │                         STOP and report to the user. Options are: retry later,
    │                         `--fresh`, or pin a different Codex model. A Claude
    │                         subagent is NOT an option — same model as the implementer.
    │                       Full decision tree: see review-prompt.md § "If Review Stalls".
    │
    └─ Read .agent/reviews/<slug>.review.md
        │
        ├─ PASS              → Tell user: "Review passed, safe to merge."
        │                       Optionally summarize 0-2 nits if any worth knowing.
        │
        ├─ NEEDS_CHANGES     → For each blocker, form own judgment:
        │                       "Reviewer says X. I think [valid / false positive] because Y.
        │                        Recommend [accept / push back / ask user]."
        │                       Then ask user how to proceed:
        │                       a) re-dispatch the implementer subagent with fix instructions
        │                          (SendMessage to the same subagent, or a fresh Agent call)
        │                       b) Override the blocker
        │                       After fixes: re-run verify subagent → update §9 → commit →
        │                       re-trigger /codex:adversarial-review (Codex again, not Claude)
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

## Command Cheatsheet

```bash
# Setup (once per project / machine)
/codex:setup                              # Check Codex availability
!codex login                              # Auth if needed

# Implement (Claude subagent, not Codex)
Agent(subagent_type="general-purpose", prompt=<implement-prompt.md>)   # background implementer
SendMessage(to=<implementer>, message=<fix instructions>)              # continue same implementer

# Verify (separate Claude subagent)
Agent(subagent_type="general-purpose", prompt="run §9 commands, report tails")

# Review (Codex only)
/codex:adversarial-review --base develop --background <focus>  # Default
/codex:review --background                # Lighter, non-steerable (fast-path tasks)

# Background job management (Codex review jobs)
/codex:status                             # All running/recent jobs
/codex:status <task-id>                   # Specific job
/codex:result                             # Latest completed result
/codex:cancel                             # Abort current background job
```

---

## Anti-Patterns (Do Not Do)

### ❌ Mixing plan and implement

Wrong: Claude starts editing files while discussing the approach.
Right: Finish spec, wait for approval, then spawn the implementer.

### ❌ Same model for implement + review

Wrong: implementer subagent finishes, main agent spawns another Claude subagent to "review the diff" — or reviews it itself.
Right: `/codex:adversarial-review` starts a fresh Codex session. Two Claude agents are one model; the review must cross models or it is not a review.

### ❌ Falling back to a Claude reviewer when Codex is unavailable

Wrong: Codex stalls twice or hits its usage limit, so a general-purpose subagent "takes over the review just this once."
Right: cancel, tell the user Codex is unavailable, and wait / retry / pin another Codex model. Shipping on a same-model verdict is worse than waiting.

### ❌ Spec written like pseudocode

Wrong: Spec contains 50 lines of implementation code.
Right: Spec says "add Y validation in function X, handle edge case Z" and lets the implementer write the actual code.

### ❌ Vague acceptance criteria

Wrong: "Code quality good, performance OK"
Right: "`<test command>` passes; manual test: set `updated_at` to now-25h via SQL, refresh page, stale badge appears on the affected row."

### ❌ Pasting review reports verbatim

Wrong: Copy the whole `.review.md` into chat.
Right: Distill to 3-5 bullets with Claude's own take.

### ❌ Auto-advancing without user approval

Wrong: Write spec → immediately spawn the implementer because it "looked fine".
Right: Always wait for explicit user "approved" / "通过" between phases.

### ❌ Enabling the review gate

Wrong: `/codex:setup --enable-review-gate` — official README warns this creates long agent loops and drains usage quotas. This workflow is already gate-equivalent through Phase 3, no need.

### ❌ Main agent editing implementation files or running verify directly

Wrong: the main agent opens an implementation file with Edit/Write, or runs `pytest` / `npm run build` itself "because it's just one line / one command." This violates the orchestrator boundary and contaminates the main agent's later triage of the Codex report.
Right: implementation edits → implementer subagent. Verify execution → a separate host subagent that reports tails. The main agent only dispatches, records results into the spec, drives git, and judges. Authoring the spec/review markdown is the one writing the main agent keeps.

### ❌ Letting the implementer verify its own work into Section 9

Wrong: implementer subagent runs the tests, pastes green tails into Section 9, main agent commits.
Right: the implementer may run builds/tests while developing, but the Section 9 evidence Codex reads is produced by a fresh verify subagent. The implementer only lists the command lines.

### ❌ Letting the implementer commit

Wrong: implementer prompt says "commit when done" — now the main agent cannot inspect the file list against Section 2 before it lands, and a parallel session may have moved HEAD.
Right: the main agent creates the branch before spawning, the subagent only edits files + lists commands in Section 9, the main agent commits after verify.

### ❌ Triggering Phase 3 review with empty Section 9

Wrong: skip the verify step in Phase 2c, hand straight to review — reviewer cannot execute commands, so it returns `EVIDENCE_MISSING` blockers across the board, wasted review run.
Right: a host subagent runs the commands and the main agent records the tails into Section 9.1 / 9.2 / 9.3 before `/codex:adversarial-review`. The reviewer's verdict quality is bounded by the evidence you give it.

### ❌ Silently waiting while a background job runs

Wrong: spawn the implementer or kick off `/codex:adversarial-review --background`, then go quiet until the user asks "is it done yet?". The main agent looks dead and silent stalls go undetected for 20+ minutes.
Right: implementer → check `git status --short` + task state every 300s and surface a one-liner; review → poll `/codex:status` every 120s and report `[poll T+Nmin] state=...`. Two consecutive checks with no progress OR an explicit `error / timeout / failed` state triggers the stall procedure for that phase.

---

## Repository Layout

```
项目根/
├── CLAUDE.md                    # Project identity card (10-15 lines, see CLAUDE.md template)
├── .codex/
│   └── config.toml              # Optional: pin Codex model/effort for review in this project
└── .agent/
    ├── specs/
    │   └── YYYY-MM-DD-<slug>.md       # Specs (commit to git)
    └── reviews/
        └── YYYY-MM-DD-<slug>.review.md  # Review reports (commit to git)
```

**Commit `.agent/specs/` and `.agent/reviews/` to git.** Specs and reviews are design history — valuable to future-you and future agents. `.agent/handoff.md` is gitignored — it is transient resume state, not history.

---

## Project-Specific Notes

Stack-specific rules, project glossaries, third-party integration names, hand-off lists, and "who must personally validate this" conventions all belong in the project's own `CLAUDE.md` (see `CLAUDE.md.template`), not here. This skill stays language- and project-agnostic by design.

For code-level conduct (assumptions, simplicity, surgical changes), the `karpathy-guidelines` skill complements this one — this skill defines the workflow, karpathy defines the code conduct.

---

## Files in This Skill

- **`SKILL.md`** (this file) — workflow definition, decision rules, command reference
- **`spec-template.md`** — load when writing a spec in Phase 1
- **`implement-prompt.md`** — load when spawning the implementer subagent in Phase 2
- **`review-prompt.md`** — load when triggering Codex review in Phase 3
- **`CLAUDE.md.template`** — minimal per-project CLAUDE.md to copy into new projects
