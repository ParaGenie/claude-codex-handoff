# Rescue Prompt Template

> Read this file when entering Phase 2 of `codex-handoff` workflow. Use the template below to delegate implementation to Codex.

## Standard Template

Substitute `<SLUG>`, `<SPEC_PATH>`, and `<BASE_BRANCH>` then issue:

```
/codex:rescue --background

Implement strictly according to <SPEC_PATH>.

Rules:
1. Create a new branch `feat/<SLUG>` from `<BASE_BRANCH>` (do not branch from main).
2. Only modify files listed in spec section 2 ("Files to modify" / "Files to create"). Do not edit anything else, even if you notice a bug or smell.
3. Strictly observe spec section 4 ("Do NOT"). Treat every bullet as a hard prohibition.
4. After implementation, run every acceptance command from spec section 5. Paste the output (last 20-30 lines per command) into the final commit message.
5. Do not merge the branch. Do not push to main/develop.
6. Do not enable feature flags or modify production config.
7. When done, report: branch name, final commit hash, summary of which spec sections you addressed.

If you encounter ambiguity in the spec, stop and report — do not improvise. List the specific question and which spec line is unclear.

If acceptance commands fail, do not declare success. Report the failure with the command and last 30 lines of output.
```

---

## Variations

### Variation: small task, foreground (no `--background`)

For tasks expected to finish in under ~5 minutes (a few-line bugfix with tests):

```
/codex:rescue

Implement strictly according to <SPEC_PATH>.
[... same rules 1-7 ...]
```

Trade-off: blocks the Claude Code session while running. Acceptable for short tasks.

### Variation: continue previous rescue

When Reviewer flagged blockers and we want Codex to fix them:

```
/codex:rescue --resume

Address the blockers listed in <REVIEW_PATH>:

1. <Blocker 1 — specific instruction>
2. <Blocker 2 — specific instruction>

Stay on branch `feat/<SLUG>`. Same rules as before:
- Do not expand scope beyond what's listed above
- Re-run acceptance commands from <SPEC_PATH> section 5 after fixes
- Paste outputs in commit message
- Report final commit hash when done
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

### Sanity check (before proceeding to Phase 3)

- [ ] Branch was created with the expected name?
- [ ] Commits exist on that branch?
- [ ] Acceptance command outputs visible in commit message?
- [ ] Codex reported success (not "I couldn't do X because Y")?

If any of these fail, **do not advance to Phase 3**. Either:

1. **Structural failure** (no branch / no commits) → re-issue `/codex:rescue` with corrective instructions. Don't review nothing.
2. **Codex reported it couldn't complete** → bring the blocker back to the user, possibly amend spec, then `--resume`.
3. **Acceptance commands failed** → this is a Phase 2 problem, not a review problem. Have Codex fix it via `--resume`.

### If sanity checks pass

Proceed directly to Phase 3. Do not:

- Comment on code quality (Reviewer's job)
- Read the diff (bias risk)
- Ask the user to read the diff first (defeats the purpose of having a reviewer)

Just say to the user:

> Codex finished implementation on `feat/<SLUG>` (commit `<hash>`), acceptance commands passed. Starting review.

Then issue the review command (see `review-prompt.md`).