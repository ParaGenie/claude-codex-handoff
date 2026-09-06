---
name: codex-handoff
description: Three-phase delivery workflow — Claude plans and writes a spec, a Claude subagent implements in the host working tree, a fresh Codex session adversarially reviews the diff (via the codex-plugin-cc plugin). Implementation and review are never the same model. Use for any change touching more than one file or real business logic, new modules, refactors, or when the user says "plan and implement", "走交付流程", "走流程", "write a spec". Skip for typo fixes, single-line tweaks, exploration, and discussion-only turns.
license: MIT
---

# Codex Handoff Workflow

Claude plans and writes a spec, a Claude subagent implements in the host working tree, a fresh Codex session reviews the diff through the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin. Everything happens inside one Claude Code session.

## Roles

| Role | Who | Does |
|---|---|---|
| **Orchestrator** | Claude main agent (you) | Probe code, write the spec, spawn subagents, record results, drive git, triage the review |
| **Implementer** | Claude subagent (`general-purpose`, host) | Edit only the files in spec §2, write acceptance *command lines* into §9, no commit |
| **Verifier** | A second, fresh Claude subagent (host) | Run the §9 commands, report output tails |
| **Reviewer** | Codex via `/codex:adversarial-review` | Judge diff + §9 evidence against the spec, write the report |

## Two rules that hold everywhere

1. **The orchestrator never touches the codebase.** No implementation edits, no build/test runs — not even a one-line fix. Edits go to the implementer subagent; verify runs go to a separate host subagent. The main agent keeps planning, judgment, the spec/review markdown, and git (branch + commit).
2. **Implementation and review are never the same model.** Claude implements, Codex reviews. Two Claude subagents are one model. If Codex is unavailable (stall, usage limit), the task waits — there is no Claude-reviewer fallback, not "just this once". `/codex:rescue` is not part of this loop; the only `/codex:*` commands used are `review`, `adversarial-review`, `status`, `result`, `cancel`.

Why this split: the Codex sandbox cannot write to `.git/` and does not mount `.venv` / `node_modules`, so it cannot run the project's build/test tools. That makes it a poor implementer but a fine cold reader of a diff. Its only source of acceptance truth is the §9 evidence recorded in Phase 2c — and keeping implementer and verifier separate means that evidence was not produced by the hands that wrote the code.

## When to use

- **Full flow**: multi-file changes, new modules, cross-cutting refactors, anything touching money / auth / user data / DB migrations / external integrations, or whenever the user says "走流程".
- **Skip**: typo fixes, single-line tweaks, comment edits, exploration ("show me how X works"), discussion-only turns.
- **Fast path** (< 30 lines, single file, no business logic): skip the spec. A subagent edits from a precise instruction, a verifier runs the commands, `/codex:review` runs before commit. Both rules above still hold.

## The loop

```
PHASE 1  PLAN      Claude probes → grills open questions → writes .agent/specs/<date>-<slug>.md → STOP
                   │ user replies "approved"
PHASE 2  IMPLEMENT 2a main:        git switch -c feat/<slug> <base>
                   2b implementer: edit §2 files, write command lines into §9, report (no commit)
                   2c verifier:    run §9 commands on host → tails
                      main:        record tails into §9 → git commit
                   │ §9 filled, commit on branch
PHASE 3  REVIEW    /codex:adversarial-review --base <base> --background <focus>
                   plugin injects diff → Codex judges against spec + §9 → .agent/reviews/<date>-<slug>.review.md
                   │
                   PASS → recommend merge   NEEDS_CHANGES → triage with user   FAIL → likely re-plan
```

Never auto-advance between phases. The user approves the spec, and the user decides what to do with the review.

---

## Phase 1 — Plan

1. **Probe first.** Read the relevant code and whatever design docs the project's `CLAUDE.md` pins under "Key Docs".
2. **Grill uncertain plans before writing.** Walk the decision tree one branch at a time; read code instead of asking when the repo can answer; ask **one** question at a time with your recommended answer as a confirm/reject choice. Cover edge cases, user/data impact, backward compatibility, acceptance criteria. Scale to risk: skip when unambiguous, grill hard for money / auth / data / migrations. Feed the answers into §1 (WHY), §4 (Do NOT), §5 (acceptance).
3. **Write `.agent/specs/YYYY-MM-DD-<slug>.md`** using `spec-template.md`. Slug is short kebab-case (`order-refund-rounding-fix`, not `fix-bug`).
4. **Do not summarize the spec in chat.** Say only:

   > Spec written: `.agent/specs/YYYY-MM-DD-<slug>.md`. Please review and reply "approved" to start implementation.

5. Wait for explicit approval.

---

## Phase 2 — Implement

### 2a. Pre-flight (main agent)

```bash
git switch -c feat/<slug> <base>
```

Confirm `.venv` / `node_modules` are installed on the host. Resolve the **absolute working-tree path** to hand the subagent — in a git worktree that is the worktree path, not the main checkout (a subagent given the main checkout edits a stale copy).

### 2b. Spawn the implementer

Use the template in `implement-prompt.md`:

```
Agent(subagent_type="general-purpose", description="Implement <slug> per spec", prompt=<implement-prompt.md, substituted>)
```

The subagent has full host access, so the discipline (no commit, only §2 files, command lines only in §9, no compat/adapter code) comes from the prompt — keep every rule in it.

### While the implementer works

- **Do not read the diff.** It biases your later triage of the Codex report, and a same-model self-review adds nothing Codex will not do better.
- **Check every 300 seconds, not more often**: `git status --short` (file list only) plus the subagent's task state. Surface a one-liner: `[check T+Nmin] implementer files-changed=<n> state=<running|done>`. Completion arrives as a notification; do not poll on a shorter loop.
- **Stuck** = task state reports error/failed, or two consecutive checks show no new/changed files and no state change. Stop the subagent, tell the user, and offer: re-dispatch with a sharper prompt / split the spec / user takes over. Never finish the edit yourself.
- **Trust files, not notifications.** A completion message can carry a fabricated summary. Confirm with `git status --short` that the claimed files actually changed.

### 2c. Verify and commit (main agent)

1. Do not critique code quality — that is Phase 3.
2. Run the sanity checklist in `implement-prompt.md` § "When the implementer reports back".
3. **Spawn a fresh host subagent to run the §9 command lines** and report tails (~30 lines each). Record each tail under its `$ <command>` line in the spec — writing into the spec is orchestration, not a code edit.
4. UI tasks: the §9.2 screenshot + console + network triple is captured by the user; a background session cannot drive a browser.
5. Re-check `git rev-parse --abbrev-ref HEAD` (a parallel session may have moved HEAD), then `git add <§2 files> <spec>` and `git commit -m "<task>: implement per spec"`.
6. Any failed command → send the failure paste back to the implementer (`SendMessage` keeps its context; fresh `Agent` if it is gone), re-run the verifier, do not reuse old tails. Do not advance with an incomplete Phase 2.

---

## Phase 3 — Review

`/codex:adversarial-review --base <base>` runs the plugin's companion script in the main session, which injects the branch diff, commit log, and diff-stat into Codex's prompt. You bundle nothing. The branch must have a commit and §9 must be filled — an empty §9 yields `EVIDENCE_MISSING` blockers across the board and wastes the run.

Use `/codex:adversarial-review` by default (steerable via focus text). `/codex:review` is the non-steerable lighter pass for the fast path. Never enable the plugin's review gate (`/codex:setup --enable-review-gate`) — this workflow already is the gate.

Build the prompt from `review-prompt.md` (always include 3–5 task-specific focus bullets) and issue it with `--background`.

### While the review runs

- Poll `/codex:status` every 300 seconds and surface `[poll T+Nmin] codex <task-id> state=<…>`. Track state + last-message across polls.
- Do not read the in-progress report.
- **Stuck** = explicit `error / timeout / failed`, a usage-limit message, or two consecutive polls with no progress. First stall and not a usage limit → `/codex:cancel`, re-issue the same command. Second stall or any usage limit → `/codex:cancel`, stop, report to the user with the options (retry after reset, `--fresh`, pin another Codex model via `--model`). Write `.agent/handoff.md` so the review can be re-issued later. A Claude subagent is **not** an option, and green §9 tests are not an independent verdict.

### Triage the report

Read `.agent/reviews/<date>-<slug>.review.md`. LLM reviewers over-produce, so **never paste the raw report**. For each blocker form your own view — valid / false positive / evidence gap (§9.x missing) / need the user's call — and present: one-line verdict, numbered blockers with your take, nice-to-haves that matter, one next-action question. Full presentation format in `review-prompt.md` § "Interpreting the report".

- **PASS** → "Review passed, safe to merge" (plus 0–2 nits worth knowing).
- **NEEDS_CHANGES** → ask the user; valid code issues go back to the implementer via `SendMessage`, evidence gaps get §9 filled; then re-verify → commit → re-run Codex (never a Claude reviewer).
- **FAIL** → the spec is probably flawed; propose returning to Phase 1 and get agreement first.

---

## Cross-session resume

Only when the workflow must cross a session boundary (compaction, background job ending, user stepping away), write `.agent/handoff.md` (gitignored): current phase, slug, spec path, branch + base, subagent name / Codex task-id, blockers, next action, and a `Suggested skills:` line. No secrets, no spec content — the committed spec is the durable design. The next session deletes or overwrites it once resumed.

## Command cheatsheet

```
/codex:setup                                   # once per machine; !codex login if needed
Agent(subagent_type="general-purpose", ...)    # implementer, then a separate verifier
SendMessage(to=<implementer>, ...)             # continue the same implementer with fixes
/codex:adversarial-review --base <base> --background <focus>   # default review
/codex:review --background                     # fast-path review
/codex:status [task-id] | /codex:result | /codex:cancel
```

## Repository layout

```
<project>/
├── CLAUDE.md                 # project identity card — see CLAUDE.md.template
├── .codex/config.toml        # optional: pin Codex model / effort for review
└── .agent/
    ├── specs/YYYY-MM-DD-<slug>.md            # committed
    ├── reviews/YYYY-MM-DD-<slug>.review.md   # committed
    └── handoff.md                            # gitignored, transient
```

Stack rules, glossaries, and "who must personally validate this" lists belong in the project's `CLAUDE.md`, not in this skill.

## Files in this skill

- `SKILL.md` — this file: roles, rules, phase flow
- `spec-template.md` — load in Phase 1
- `implement-prompt.md` — load in Phase 2 (implementer prompt, sanity checklist, fix loop)
- `review-prompt.md` — load in Phase 3 (review prompt, focus areas, report triage)
- `CLAUDE.md.template` — copy into each project root
