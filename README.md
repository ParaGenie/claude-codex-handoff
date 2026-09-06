# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **Claude Code plans, a Claude subagent implements, a fresh OpenAI Codex session adversarially reviews.**
> A three-phase workflow for code changes that deserve a written spec — the model that writes the code is never the model that grades it.

---

## Why this exists

Claude Code is excellent at exploring code, asking the right clarifying questions, and — through a subagent with full host access — implementing against a spec without leaving the session. What it cannot give itself is a credible second opinion: the same model that wrote the code will rationalize its own choices. Codex CLI reading the finished diff cold is that second opinion from a **different model**.

This skill encodes the protocol so you get, every task:

- A **written spec** before any code is touched
- An **implementer subagent** bound to that spec, with no license to improvise
- An **adversarial reviewer from a different model** with no memory of why the code was written this way

## How it works

```
┌────────────────────────────────────────────────────────────┐
│  PHASE 1 — PLAN    (Claude Code)                           │
│  Probe code → ask one clarifying question at a time →      │
│  write .agent/specs/<slug>.md → STOP for your approval     │
└──────────────────────────┬─────────────────────────────────┘
                           │ you reply "approved"
                           ▼
┌────────────────────────────────────────────────────────────┐
│  PHASE 2 — IMPLEMENT                                       │
│  Claude:      git switch -c feat/<slug>                    │
│  Implementer: edit files + list cmds in spec §9 (no commit)│
│  Verifier:    run §9 cmds on host → report tails           │
│  Claude:      record tails → git commit                    │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│  PHASE 3 — REVIEW   (fresh Codex via /codex:adversarial-…) │
│  Plugin auto-injects diff → Codex judges against           │
│  spec + §9 evidence → report blockers                      │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
        Claude triages the report (real bug vs. false positive),
        recommends fix-or-ship, hands the decision back to you.
```

Everything happens **inside one Claude Code session**: implementation via the built-in `Agent` tool, review via the `/codex:*` slash commands from the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin.

### The two rules

1. **The main Claude agent only dispatches.** It never edits the target codebase or runs verify itself — not even a one-line fix. An implementer subagent edits under the spec's constraints and writes the *command lines* the verifier should run into spec §9; a separate verifier subagent runs them and reports the tails; the main agent records the evidence, drives git, and judges. Separate hands mean the evidence Codex reads was not produced by whoever wrote the code.

2. **Implementation and review are never the same model.** Claude implements, Codex reviews — always. If Codex stalls or hits its usage limit, the task waits; the skill forbids substituting a Claude subagent as reviewer, because two Claude agents are "different agents" on paper and one model in practice.

Why Codex reviews instead of implementing: v0.1 handed implementation to `/codex:rescue`, and the Codex sandbox (no git writes, no `.venv` / `node_modules`, usage quotas mid-task, prompt + polling overhead) cost more than it returned. A Claude subagent on the host has none of those problems and is about as fast. The sandbox is, however, exactly right for a cold read of a diff — so Codex now does the one job Claude structurally cannot.

## When to use it

✅ **Reach for it when** the change touches more than one file or a new module, involves real business logic, money, auth, user data, DB migrations, or external integrations, or you would want a written spec anyway.

❌ **Skip it for** typo fixes, single-line tweaks, comment edits, exploration questions, discussion-only turns.

🟡 **In-between tasks** (< 30 lines, single file, no business logic): the spec is skipped, but a subagent still makes the edit, a separate subagent verifies, and `/codex:review` runs as a lighter cross-model check before commit.

## Files in this repo

| File | Purpose | Loaded when |
|---|---|---|
| `SKILL.md` | Roles, the two rules, phase flow, command cheatsheet | Auto-loaded when the skill triggers |
| `spec-template.md` | Spec format, filling guide, worked example | Phase 1 |
| `implement-prompt.md` | Implementer prompt, sanity checklist, fix loop | Phase 2 |
| `review-prompt.md` | Codex review prompt, focus areas, report triage | Phase 3 |
| `CLAUDE.md.template` | Minimal per-project `CLAUDE.md` | Copied into each project root |

## Install

### 1. Install the skill

#### Option A — In-session, one command (recommended) 🌟

Run inside any Claude Code session:

```
/plugin marketplace add ParaGenie/claude-codex-handoff
/plugin install codex-handoff@paragenie-skills
```

No terminal needed; works on macOS / Linux / Windows. Requires Claude Code **v2.1.142+** (plugin-root `SKILL.md` support) — check with `claude --version`.

#### Option B — Bare skill (terminal)

For older Claude Code versions, air-gapped setups, or files-on-disk preference.

**macOS / Linux**:

```bash
mkdir -p ~/.claude/skills && \
  git clone https://github.com/ParaGenie/claude-codex-handoff.git \
            ~/.claude/skills/codex-handoff
```

**Windows** (PowerShell):

```powershell
New-Item "$env:USERPROFILE\.claude\skills" -ItemType Directory -Force | Out-Null
git clone https://github.com/ParaGenie/claude-codex-handoff.git "$env:USERPROFILE\.claude\skills\codex-handoff"
```

<details>
<summary>No <code>git</code>? Use <code>curl</code> + <code>tar</code></summary>

**macOS / Linux:**

```bash
mkdir -p ~/.claude/skills/codex-handoff && \
  curl -L https://github.com/ParaGenie/claude-codex-handoff/tarball/main | \
  tar -xz --strip-components=1 -C ~/.claude/skills/codex-handoff
```

**Windows (PowerShell):**

```powershell
$dest = "$env:USERPROFILE\.claude\skills\codex-handoff"
New-Item $dest -ItemType Directory -Force | Out-Null
curl.exe -L -o "$env:TEMP\codex-handoff.tgz" https://github.com/ParaGenie/claude-codex-handoff/tarball/main
tar.exe -xz --strip-components=1 -C $dest -f "$env:TEMP\codex-handoff.tgz"
Remove-Item "$env:TEMP\codex-handoff.tgz"
```

</details>

> ⚠️ For Option B the directory **must be named `codex-handoff`** (matching `name:` in `SKILL.md`) — Claude Code locates bare skills by directory name.

### 2. Install the codex-plugin-cc plugin

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

`/codex:setup` offers to install Codex CLI if missing (or `npm install -g @openai/codex`). Then authenticate with `!codex login` (ChatGPT subscription or OpenAI API key).

### 3. Bootstrap each project

```bash
cd /path/to/your/project
cp ~/.claude/skills/codex-handoff/CLAUDE.md.template ./CLAUDE.md   # edit: stack, docs, commands, constraints
mkdir -p .agent/specs .agent/reviews

# Optional: pin the Codex model / reasoning effort for this project
mkdir -p .codex && cat > .codex/config.toml <<'EOF'
model = "gpt-5.5"
model_reasoning_effort = "high"
EOF

git add CLAUDE.md .agent/ .codex/
git commit -m "chore: bootstrap codex-handoff workflow"
```

## What a real run looks like

```
You: Add a "stale" indicator to the items list — highlight items whose
     last update was more than 24 hours ago. Follow the codex-handoff flow.

Claude: [loads skill, probes code, asks 1-2 clarifying questions,
         writes .agent/specs/2026-05-21-stale-items-indicator.md]
        Spec written. Please review and reply "approved" to start implementation.

You: approved

Claude: [git switch -c feat/stale-items-indicator main]
        [spawns implementer subagent with implement-prompt.md]
        Implementer is working in the background. I'll check back when it's done.

Claude: Implementer finished. Spawning a verifier for the §9 commands.
        [verifier runs `npm run typecheck`, `npm test`, dev-server + manual click-through]
        All green. Recorded tails into §9. Committed as abc123. Starting Codex review.
        [issues /codex:adversarial-review --background]

Claude: Review verdict: NEEDS_CHANGES. Reviewer flagged 2 blockers:

  1. isStale() uses local time instead of UTC — off-by-hours near midnight.
     → My take: valid. Recommend fix.

  2. Banner re-renders on every parent update.
     → My take: false positive — re-renders here are cheap and intentional.

  Recommended: send #1 back to the implementer, skip #2, then re-review with Codex. OK to proceed?
```

## FAQ

**Q: Why not just use Claude Code alone?**
You can. But once the change is non-trivial, having one model both write and grade its work is a known weak spot. A second model reading the diff cold catches what the author rationalized.

**Q: Does it cost extra?**
Yes — Codex runs on your ChatGPT subscription or OpenAI API key on top of Claude, scaling with the size of the change.

**Q: Can I use a different reviewer model?**
Yes, as long as it is **not the implementer's model**. Codex ships as the default because codex-plugin-cc makes diff injection and background jobs turnkey. What you must not do is fall back to a Claude subagent when Codex is busy.

**Q: What if Codex's review is wrong?**
That is Claude's job in Phase 3: triage the report, separate real blockers from false positives, recommend next steps. You remain the final decision-maker.

**Q: Plugin vs bare skill — what's different?**
Almost nothing. The plugin path installs under `~/.claude/plugins/cache/...` and namespaces the skill as `codex-handoff:codex-handoff`; the bare path uses `~/.claude/skills/codex-handoff/`. The skill auto-triggers from task descriptions, so the namespace is invisible in practice. The plugin path adds `/plugin disable codex-handoff`.

## Related skills

- **`karpathy-guidelines`** — code-level conduct (assumptions, simplicity, surgical edits). This skill is the *workflow*; that one is the *code conduct*.

## Updating

- **Plugin:** re-run `/plugin install codex-handoff@paragenie-skills` to force a refresh.
- **Bare skill:** `cd ~/.claude/skills/codex-handoff && git pull` (PowerShell: `cd "$env:USERPROFILE\.claude\skills\codex-handoff"; git pull`). If installed via curl+tar, re-run the install command.

Per-project `CLAUDE.md` and `.agent/` directories are unaffected.

## Contributing

Issues and PRs welcome — especially spec-template fields that real specs turned out to need, implementer / review prompt patterns that consistently work better, and stories of where the workflow did or did not hold up.

## License

[MIT](./LICENSE)
