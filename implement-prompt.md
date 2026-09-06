# Implementer Prompt Template

> Read this file when entering Phase 2 of the `codex-handoff` workflow. Use the template below to delegate implementation to a Claude subagent spawned from the main session. Codex is **not** the implementer in this workflow — it is the reviewer (Phase 3).

## Who runs what (read first)

- **Implementer** = `Agent(subagent_type="general-purpose")`, runs in the host working tree with full shell + git visibility. Discipline comes from this prompt, not from a sandbox.
- **Verifier** = a *second*, fresh subagent spawned after the implementer reports back. It produces the Section 9 evidence. The implementer never fills Section 9 output blocks itself.
- **Main agent** = branch + commit + recording tails into the spec. Never edits source, never runs verify.
- **Reviewer** = Codex, Phase 3. Never a Claude subagent.

See `SKILL.md` "Cross-model rule" and Phase 2c for why implementer and verifier are kept separate.

---

## Before You Spawn the Implementer (main agent prep, ~30s)

1. `git switch -c feat/<SLUG> <BASE_BRANCH>` — create the branch in the host working tree. The subagent will see it as the current branch.
2. Confirm the spec at `.agent/specs/YYYY-MM-DD-<SLUG>.md` exists and Section 5 lists concrete, runnable acceptance commands.
3. Confirm `.venv` / `node_modules` are installed in the host working tree.
4. Resolve the **absolute working-tree path** you will hand the subagent. If the session is in a git worktree, this is the worktree path — a subagent given the main-checkout path edits a stale copy and its diff never lands on `feat/<SLUG>`.

---

## Standard Template

Substitute `<SLUG>`, `<SPEC_PATH>`, `<BASE_BRANCH>`, `<WORKTREE_PATH>` then spawn:

```
Agent(
  subagent_type="general-purpose",
  description="Implement <SLUG> per spec",
  prompt="""
Implement strictly according to <SPEC_PATH>.

Working tree: <WORKTREE_PATH> (absolute). Do ALL reads and edits under this path — do not touch any other checkout of this repository. Verify with `git -C <WORKTREE_PATH> rev-parse --abbrev-ref HEAD` that you are on `feat/<SLUG>` before editing anything.

Rules:
1. Do NOT commit, and do NOT run any git command that moves HEAD or touches the index: no `switch / checkout / branch / add / commit / restore / stash / reset / rebase / merge`. Read-only `git status / diff / log / show` are fine. The main agent commits after verification.
2. Only modify files listed in spec Section 2 ("Files to modify" / "Files to create"). Do not edit anything else, even if you notice a bug or smell — log it in your report under "Observed, not touched".
3. Strictly observe spec Section 4 ("Do NOT"). Treat every bullet as a hard prohibition.
4. You MAY run the project's build / test / lint commands while developing, to check your own work. But do NOT paste any output into spec Section 9. Into spec Section 9.1 / 9.2 / 9.3, write only the **exact command lines** a separate verifier should run (one per acceptance criterion in Section 5), and leave the output blocks under each `$ <command>` empty. A fresh verify subagent will run them and the main agent will record the tails — evidence must not come from the same hands that wrote the code.
5. Do NOT try to enable feature flags, change `.env*` files, or modify production config.
6. Do NOT write compatibility / adapter / fallback code unless spec Section 8 (Compatibility Exemption Registry) is filled with a justified entry first. If a contract in the spec conflicts with what the code actually needs (field names, types, units, API shapes), STOP and report the conflict — do not bridge it with a mapping layer and mention it in passing.
7. Prefer the simplest implementation that satisfies Section 5. No speculative abstractions, no defensive layers for low-probability cases, no "while I'm here" cleanups.
8. When done, report:
   - Files you modified / created (file paths only, no diff dump)
   - Which spec sections you addressed (Section 2 line numbers / Section 3 bullet numbers)
   - The exact command lines you wrote into Section 9.1 / 9.2 / 9.3 (so the verifier can run them)
   - Any spec ambiguity you resolved and how (so the main agent can confirm or push back)
   - "Observed, not touched": anything outside Section 2 you think needs attention
9. If you encounter ambiguity in the spec that changes the outcome, stop and report — do not improvise. List the specific question and which spec line is unclear.

Acceptance commands must cover three tiers per spec Section 5:
- 5.1 Static build (always required) → command lines into Section 9.1
- 5.2 Runtime verification (when changes touch service/UI) → command lines into Section 9.2
- 5.3 Unit tests (when changes touch critical paths) → command lines into Section 9.3

Do NOT declare the task done because your own test run was green. A separate verifier re-runs everything; failures come back to you via the main agent.
"""
)
```

### What the main agent does after the implementer reports

1. Confirm with `git status --short` (in `<WORKTREE_PATH>`) that the files the subagent lists actually changed. A completion notification can carry a fabricated summary — trust the working tree, not the message.
2. **Spawn a fresh host subagent** to run the command lines written into Section 9.1 / 9.2 / 9.3 — not the implementer, not yourself. Hand it the command lines and `<WORKTREE_PATH>`; it reports the tails back.
3. Record the actual tails (last 20-30 lines per command) under each `$ <command>` in Section 9 (recording into the spec artifact is orchestration, not a code edit).
4. For UI changes: hand off to the user for the screenshot + console + network triple (Section 9.2). Background sessions cannot drive a browser.
5. `git add <Section-2-files> <SPEC_PATH>` + `git commit -m "<task>: implement per spec"` on `feat/<SLUG>` — git stays with the main agent. Re-check `git rev-parse --abbrev-ref HEAD` immediately before committing: a parallel session may have moved HEAD.
6. If any acceptance command failed, do not advance to Phase 3 — send the failure back to the implementer (below).

---

## Variations

### Variation: continue the same implementer (fix blockers / failed acceptance)

The implementer subagent keeps its context while it is alive. Prefer `SendMessage` over a fresh spawn:

```
SendMessage(
  to="<implementer agent name>",
  message="""
Address the blockers listed in <REVIEW_PATH> (or: acceptance command failed — paste below):

1. <Blocker 1 — specific instruction>
2. <Blocker 2 — specific instruction>

Stay on branch `feat/<SLUG>` in <WORKTREE_PATH>. Same rules as before:
- No git commit / HEAD-moving commands
- Do not fill Section 9 output blocks — update the command lines if they need to change; the verifier re-runs them
- Do not expand scope beyond the items above
- Report what you changed and which Section 9 commands should be re-run
"""
)
```

If the implementer has been torn down (session boundary, compaction), spawn a fresh `Agent` with the Standard Template plus the blocker list appended.

### Variation: fast path (small task, no spec)

For the "middle ground" in `SKILL.md` (< 30 lines, single file): spawn a general-purpose subagent with a precise, self-contained instruction instead of a spec path. Keep Rules 1, 2 (name the one file), 4, 6, 7. Then a verify subagent + `/codex:review`. The orchestrator boundary and the cross-model review still hold.

---

## What the Main Agent Does While the Implementer Works

- **Do not read the diff.** Diff-reading creates implementation bias that contaminates Phase 3 triage — and since the orchestrator and the implementer are the same model, a "self-review" here adds nothing the Codex review will not do better.
- **Check every 300 seconds, no more often:** `git status --short` in `<WORKTREE_PATH>` (file list only) plus the subagent's task state. Surface a one-liner: `[check T+Nmin] implementer <name> files-changed=<n> state=<running|done>`. Completion arrives as a notification; do not poll on a shorter loop.
- Continue conversation with the user on other topics if they want.
- Do not preemptively start writing the review prompt — wait until Phase 2 actually finishes.

---

## When the Implementer Reports Back

### Sanity check (before spawning the verify subagent)

- [ ] Reported file list matches spec Section 2 **and** matches `git status --short`?
- [ ] Command lines present in Section 9.1 / 9.2 / 9.3, output blocks still empty?
- [ ] No commit landed (`git log <BASE_BRANCH>..HEAD` is empty)?
- [ ] No "I couldn't do X because Y" — if so, address the blocker before proceeding?
- [ ] No adapter / mapping / compatibility layer mentioned in passing in the report? (grep the report for 映射 / 适配 / 兼容 / adapter / fallback — a contract conflict that was bridged instead of reported is a Rule 6 violation)

If the sanity check passes, spawn the verify subagent, record Section 9, commit.

### If acceptance commands fail

This is **not** a Phase 3 problem. Send it back to the implementer via `SendMessage` (see Variation above) with:

```
Acceptance command failed:

$ <command>
<last 30 lines of output>

Spec Section 5 item: <criterion>. Fix and report which files changed. Same rules as before (no commit, no Section 9 output).
```

Then re-run the verify subagent — do not reuse the old tails.

### If sanity checks fail (implementer couldn't complete)

- **No file modifications** → re-dispatch with corrective instructions.
- **Section 9 command lines empty** → send back, point out Rule 4.
- **Implementer reported a spec ambiguity** → bring the question to the user, amend spec, then continue the same implementer.
- **Implementer committed anyway** → `git reset --soft <BASE_BRANCH>` on the feature branch (main agent), then proceed as if it had not; remind it of Rule 1 on the next message.

Do not advance to Phase 3 with an incomplete Phase 2.

### If the implementer stalls

**Stuck signal (either is sufficient):**

1. The task state reports error / failed.
2. Two consecutive 300s checks show no new or changed files and no state change.

**Procedure:**

1. Stop the subagent.
2. Tell the user (one paragraph): "Implementer stuck — no file change for ~`<minutes>`m. Stopped. Options:" then list:
   - `(a)` re-dispatch the same task with a sharper prompt (name the file / function it should have been in — cheapest if it was almost there)
   - `(b)` split the spec into two smaller units and re-plan
   - `(c)` user takes over the remaining piece manually
3. Wait for the user's choice. **Never** have the main agent finish the edit itself, and never hand the edit to Codex — that would reintroduce the sandbox limits and quota wall this workflow moved away from.

### Once Phase 2 is clean

Tell the user:

> Implementation finished on `feat/<SLUG>`. A separate host subagent ran the acceptance commands from Section 9 — all green; I recorded the tails into the spec. Committed as `<hash>`. Starting Codex review.

Then issue the review command (see `review-prompt.md`).
