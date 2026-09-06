# Implementer Prompt Template

> Load in Phase 2 of `codex-handoff`. Roles, the two rules, the 300-second check loop, and stall handling are in `SKILL.md` — this file holds the prompt itself and the post-report procedure.

## Before spawning (main agent)

1. `git switch -c feat/<SLUG> <BASE_BRANCH>` in the host working tree.
2. The spec exists at `.agent/specs/YYYY-MM-DD-<SLUG>.md` and §5 lists concrete, runnable acceptance commands.
3. `.venv` / `node_modules` are installed on the host.
4. Resolve the **absolute working-tree path** (`<WORKTREE_PATH>`). In a git worktree, this is the worktree path — a subagent given the main-checkout path edits a stale copy and its diff never lands on `feat/<SLUG>`.

## Standard template

Substitute `<SLUG>`, `<SPEC_PATH>`, `<WORKTREE_PATH>`, then spawn:

```
Agent(
  subagent_type="general-purpose",
  description="Implement <SLUG> per spec",
  prompt="""
Implement strictly according to <SPEC_PATH>.

Working tree: <WORKTREE_PATH> (absolute). Do ALL reads and edits under this path — do not touch any other checkout of this repository. Verify with `git -C <WORKTREE_PATH> rev-parse --abbrev-ref HEAD` that you are on `feat/<SLUG>` before editing anything.

Rules:
1. Do NOT commit, and do NOT run any git command that moves HEAD or touches the index (switch / checkout / branch / add / commit / restore / stash / reset / rebase / merge). Read-only `git status / diff / log / show` are fine. The main agent commits after verification.
2. Only modify files listed in spec Section 2 ("Files to modify" / "Files to create"). Do not edit anything else, even if you notice a bug — log it in your report under "Observed, not touched".
3. Treat every bullet in spec Section 4 ("Do NOT") as a hard prohibition.
4. You MAY run the project's build / test / lint commands while developing. But do NOT paste any output into spec Section 9. Into Section 9.1 / 9.2 / 9.3 write only the **exact command lines** a separate verifier should run (one per acceptance criterion in Section 5), leaving the output block under each `$ <command>` empty. A fresh verify subagent runs them; evidence must not come from the hands that wrote the code.
5. Do NOT enable feature flags, change `.env*` files, or modify production config.
6. Do NOT write compatibility / adapter / fallback code unless spec Section 8 already holds a justified entry. If a contract in the spec conflicts with what the code needs (field names, types, units, API shapes), STOP and report the conflict — do not bridge it with a mapping layer and mention it in passing.
7. Prefer the simplest implementation that satisfies Section 5. No speculative abstractions, no defensive layers for low-probability cases, no "while I'm here" cleanups.
8. If a spec ambiguity changes the outcome, stop and report the question and the unclear spec line — do not improvise.
9. When done, report:
   - Files modified / created (paths only, no diff dump)
   - Which spec sections you addressed
   - The exact command lines written into Section 9.1 / 9.2 / 9.3
   - Any ambiguity you resolved and how
   - "Observed, not touched": anything outside Section 2 that needs attention

Acceptance commands cover three tiers per Section 5: 5.1 static build (always) → 9.1; 5.2 runtime verification (service/UI changes) → 9.2; 5.3 unit tests (critical paths) → 9.3.

Do NOT declare the task done because your own test run was green. A separate verifier re-runs everything; failures come back to you via the main agent.
"""
)
```

### Fast path (small task, no spec)

For the `SKILL.md` fast path (< 30 lines, single file): give the subagent a precise, self-contained instruction instead of a spec path and keep Rules 1, 2 (name the one file), 4, 6, 7. Then a verify subagent + `/codex:review`.

## When the implementer reports back

### Sanity checklist

- [ ] Reported file list matches spec §2 **and** `git status --short` in `<WORKTREE_PATH>`
- [ ] Command lines present in §9.1 / 9.2 / 9.3, output blocks still empty
- [ ] No commit landed (`git log <BASE_BRANCH>..HEAD` empty)
- [ ] No "I couldn't do X because Y"
- [ ] No adapter / mapping / compatibility layer mentioned in passing (grep the report for 映射 / 适配 / 兼容 / adapter / fallback — a bridged contract conflict is a Rule 6 violation)

Then spawn the verifier, record §9, commit (see `SKILL.md` 2c).

### If a check fails

- **No file modifications** → re-dispatch with corrective instructions.
- **§9 command lines empty** → send back, cite Rule 4.
- **Spec ambiguity reported** → bring the question to the user, amend the spec, continue the same implementer.
- **Committed anyway** → `git reset --soft <BASE_BRANCH>` on the feature branch, proceed as if it had not, restate Rule 1 next message.
- **Acceptance command failed** (verifier reports red) → not a Phase 3 problem; send it back:

```
SendMessage(
  to="<implementer agent name>",
  message="""
Acceptance command failed:

$ <command>
<last 30 lines of output>

Spec Section 5 item: <criterion>. Fix and report which files changed. Same rules as before: stay on feat/<SLUG> in <WORKTREE_PATH>, no commit / HEAD-moving commands, do not fill Section 9 output blocks (update the command lines if they must change), do not expand scope.
"""
)
```

The same message shape carries review blockers from Phase 3 (replace the failure paste with the numbered blocker list from `<REVIEW_PATH>`). `SendMessage` keeps the implementer's context; if it has been torn down, spawn a fresh `Agent` with the standard template plus the list appended. After any fix, re-run the verifier — never reuse old tails.

### Once Phase 2 is clean

> Implementation finished on `feat/<SLUG>`. A separate host subagent ran the §9 acceptance commands — all green, tails recorded in the spec. Committed as `<hash>`. Starting Codex review.

Then issue the review (`review-prompt.md`).
