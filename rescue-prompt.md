# Rescue Prompt Template

> Read this file when entering Phase 2 of `codex-handoff` workflow. Use the template below to delegate implementation to Codex.

## Sandbox Reality Check (read first)

The Codex CLI sandbox has two hard-coded constraints that shape Phase 2 division of labor:

1. **`.git/` is read-only.** All `git switch / branch / add / commit / restore / stash / reset / checkout` write operations fail with `Operation not permitted` on `.git/index.lock`, even when the project is marked `trust_level = "trusted"`.
2. **`.venv/` and `node_modules/` are not visible.** The sandbox sees a filtered copy of the working tree that excludes these directories, so `pytest`, `ruff`, `npm run build`, anything that resolves to `.venv/bin/*` or `node_modules/.bin/*` fails with `command not found`.

Both are unconfigurable. Don't waste cycles trying to work around them — design around them:

| Job | Owner |
|---|---|
| Create `feat/<SLUG>` branch and check it out | **Main session** (before `/codex:rescue`) |
| Modify source files per spec | **Codex sandbox** |
| List acceptance commands in spec Section 9 | **Codex sandbox** |
| Run acceptance commands, paste output | **Main session** (after Codex finishes) |
| `git add` + `git commit` | **Main session** |
| Browser screenshot for UI tasks (Section 9.2) | **User** (handed off by main session) |

The handoff template below enforces this split. Codex stays in its lane (file edits), main session does the rest.

---

## Before You Trigger Rescue (main session prep, ~30s)

1. `git switch -c feat/<SLUG> <BASE_BRANCH>` — create the branch in the host working tree. Codex will see it as the current branch.
2. Confirm the spec at `.agent/specs/YYYY-MM-DD-<SLUG>.md` exists and Section 5 lists concrete, runnable acceptance commands.
3. Confirm `.venv` / `node_modules` are installed in the host working tree (you will run verify against them later — Codex will not).

---

## Standard Template

Substitute `<SLUG>`, `<SPEC_PATH>`, and `<BASE_BRANCH>` then issue:

```
/codex:rescue --background

Implement strictly according to <SPEC_PATH>.

Rules:
1. The main session already checked out branch `feat/<SLUG>` for you. Do NOT run any git command — your sandbox blocks all writes to `.git/`. No `git switch / branch / add / commit / restore / stash / reset / checkout`. Just edit files.
2. Only modify files listed in spec Section 2 ("Files to modify" / "Files to create"). Do not edit anything else, even if you notice a bug or smell.
3. Strictly observe spec Section 4 ("Do NOT"). Treat every bullet as a hard prohibition.
4. **Do NOT execute acceptance commands.** Your sandbox cannot see `.venv` / `node_modules`, so `pytest`, `npm run build`, `ruff`, etc. will all fail with `command not found`. Instead: into spec Section 9.1 / 9.2 / 9.3, paste the **exact command lines** the main session should run (one per acceptance criterion in Section 5). Leave the output blocks empty under `$ <command>` — the main session fills them.
5. Do NOT try to enable feature flags, change `.env*` files, or modify production config.
6. Do NOT write compatibility code unless spec Section 8 (Compatibility Exemption Registry) is filled with a justified entry first. If you encounter what looks like a legitimate compat need mid-task, stop and report — do not improvise.
7. When done, report:
   - Files you modified / created (file paths only, no diff dump)
   - Which spec sections you addressed (Section 2 line numbers / Section 3 bullet numbers)
   - The exact command lines you wrote into Section 9.1 / 9.2 / 9.3 (so the main session can run them)
   - Any spec ambiguity you resolved and how (so the main session can confirm or push back)
8. If you encounter ambiguity in the spec, stop and report — do not improvise. List the specific question and which spec line is unclear.

Acceptance commands must cover three tiers per spec Section 5:
- 5.1 Static build (always required) → command lines into Section 9.1
- 5.2 Runtime verification (when changes touch service/UI) → command lines into Section 9.2
- 5.3 Unit tests (when changes touch critical paths) → command lines into Section 9.3

Do NOT assume tests will pass. You are not running them. The main session will run them and report failures back to you via `/codex:rescue --resume` if needed.
```

### What the main session does after Codex finishes

1. Read `/codex:result` to confirm files were modified.
2. Run the command lines Codex pasted into Section 9.1 / 9.2 / 9.3 in the host working tree.
3. Paste the actual tails (last 20-30 lines per command) under each `$ <command>` in Section 9.
4. For UI changes: hand off to the user for the screenshot + console + network triple (Section 9.2). Background sessions cannot drive a browser.
5. `git add <Section-2-files>` + `git commit -m "<task>: implement per spec"` on `feat/<SLUG>`.
6. If any acceptance command failed, do not advance to Phase 3 — go back to Codex via `/codex:rescue --resume` with the failure paste.

---

## Variations

### Variation: small task, foreground (no `--background`)

For tasks expected to finish in under ~5 minutes (a few-line bugfix with tests):

```
/codex:rescue

Implement strictly according to <SPEC_PATH>.
[... same rules 1-8 ...]
```

Trade-off: blocks the Claude Code session while running. Acceptable for short tasks.

### Variation: continue previous rescue

When Reviewer flagged blockers and we want Codex to fix them:

```
/codex:rescue --resume

Address the blockers listed in <REVIEW_PATH>:

1. <Blocker 1 — specific instruction>
2. <Blocker 2 — specific instruction>

Stay on branch `feat/<SLUG>` (main session already on it). Same rules as before:
- Do not run any git command
- Do not execute acceptance commands — update Section 9 command lines if they need to change, main session re-runs them
- Do not expand scope beyond the blockers above
- Report what you changed and which Section 9 commands the main session should re-run
```

Note: `--resume` continues the latest Codex thread for this repo, preserving context. Faster than `--fresh` for follow-ups.

### Variation: explicit model pin

The default model is whatever's set in `.codex/config.toml` (project-level) or `~/.codex/config.toml` (user-level). The recommendation across all projects in this workflow is **`gpt-5.5`** — it's the current Codex flagship and handles complex coding, long-context work, and agentic flows well.

You only need to override on the command line for one-off experiments:

```
/codex:rescue --background --model gpt-5.5 --effort high

[... standard template body ...]
```

`--effort` accepts `low | medium | high | xhigh`. Default `high` is appropriate for this workflow (we're committing to a review pass anyway, so don't shortcut reasoning time).

Other models exposed by the plugin (`gpt-5.4-mini`, `gpt-5.3-codex`, `spark` alias, `gpt-5.1-codex-max`) exist but are not recommended for this workflow — stick with `gpt-5.5` unless you have a specific reason.

---

## What Claude Should Do While Codex Works

- **Do not read the diff.** Diff-reading creates implementation bias that contaminates Phase 3 review interpretation.
- Continue conversation with user on other topics if they want.
- If user asks status, run `/codex:status`.
- If user wants to abort, run `/codex:cancel`.
- Do not preemptively start writing the review prompt — wait until Phase 2 actually finishes.

---

## When Codex Reports Back

After `/codex:result` returns:

### Sanity check (before running verify yourself)

- [ ] Codex reported a list of modified / created files matching spec Section 2?
- [ ] Codex pasted command lines into Section 9.1 / 9.2 / 9.3?
- [ ] Codex did NOT report attempting git or shell commands (those should have been rejected by sandbox)?
- [ ] Codex did NOT report "I couldn't do X because Y" — if so, address the blocker before proceeding?

If sanity check passes, **the main session takes over**:

### Main session verify + commit cycle

```bash
# In the host working tree (where .venv / node_modules are real)

# 1. Run the commands Codex listed in Section 9.1 — paste tails into Section 9.1
<command from Section 9.1>
# ... paste last ~30 lines under the $ <command> line ...

# 2. If service/UI is touched, run Section 9.2 commands — paste tails
<service start command>
# ... paste startup banner + ready marker ...

<curl health check>
# ... paste status + body ...

# 3. If critical-path tests are touched, run Section 9.3
<test command>
# ... paste tail ...

# 4. Commit
git add <files from Section 2>
git commit -m "<short message per spec>"
```

### If acceptance commands fail

This is **not** a Phase 3 problem. Send back to Codex via `/codex:rescue --resume`:

```
/codex:rescue --resume

Acceptance command failed:

$ <command>
<last 30 lines of output>

Spec Section 5 item: <criterion>. Please fix and let me know which files changed. Same rules as before (no git, no shell execution).
```

### If sanity checks fail (Codex couldn't complete)

- **No file modifications** → re-issue `/codex:rescue` with corrective instructions.
- **Section 9 command lines empty** → re-issue, point out Rule 4.
- **Codex reported a spec ambiguity** → bring the question to the user, amend spec, then `--resume`.

Do not advance to Phase 3 with an incomplete Phase 2.

### Once Phase 2 is clean

Tell the user:

> Codex finished implementation on `feat/<SLUG>`. I ran the acceptance commands from Section 9 — all green. Committed as `<hash>`. Starting review.

Then issue the review command (see `review-prompt.md`).
