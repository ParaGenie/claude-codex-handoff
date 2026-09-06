# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **Let Claude Code plan, a Claude subagent implement, and a fresh OpenAI Codex session adversarially review.**
> A battle-tested three-phase workflow for code changes that deserve a written spec — the model that writes the code is never the model that grades it.

---

## Why this exists

Claude Code is excellent at exploring code, asking the right clarifying questions, making judgment calls — and, through a subagent with full host access, implementing against a spec without leaving the session.
Codex CLI reading the finished diff cold is a credible **second opinion from a different model**, which is the one thing Claude cannot give itself.

Combine them poorly and you get hand-waving and double work. Combine them well and you get:

- A **written spec** before any code is touched
- An **implementer subagent** bound to that spec, with no license to improvise
- An **adversarial reviewer from a different model** with no memory of why the code was written this way

This skill encodes that protocol so you don't have to reinvent it every task.

## How it works (60-second tour)

```
┌────────────────────────────────────────────────────────────┐
│  PHASE 1 — PLAN    (Claude Code)                           │
│  Probe code → ask clarifying questions →                   │
│  write .agent/specs/<slug>.md → STOP for your approval     │
└──────────────────────────┬─────────────────────────────────┘
                           │ you reply "approved"
                           ▼
┌────────────────────────────────────────────────────────────┐
│  PHASE 2 — IMPLEMENT (Claude subagent edits, another       │
│                       subagent verifies)                   │
│  Claude:      git switch -c feat/<slug>                    │
│  Implementer: edit files + list cmds in spec §9 (no commit)│
│  Verifier:    run §9 cmds on host → report tails           │
│  Claude:      record tails → git commit                    │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│  PHASE 3 — REVIEW   (fresh Codex via /codex:adversarial-…) │
│  Plugin auto-injects diff → Codex evaluates against        │
│  spec + §9 evidence → report blockers                      │
│  Reviewer is ALWAYS Codex — never a Claude subagent        │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
        Claude triages the report (real bug vs. false positive),
        recommends fix-or-ship, hands the decision back to you.
```

Everything happens **inside one Claude Code session**: implementation via the built-in `Agent` tool, review via `/codex:*` slash commands provided by the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin.

Phase 1 now includes a compact "grill" loop: Claude walks the decision tree one unresolved branch at a time, asks one confirm/reject question with a recommended answer, and reads code instead of asking when the repo can answer. If a run crosses a session boundary, Claude may write a gitignored `.agent/handoff.md` resume pointer with transient state, suggested skills, and no secrets; the durable design stays in the committed spec.

### Why Phase 2 is split

This workflow holds one rule above all: **the main Claude agent only dispatches and coordinates — it never edits the target codebase or runs verify with its own hands.** So Phase 2 splits like this:

- **An implementer subagent** (spawned by the main agent, running in the host working tree with full shell + git visibility) edits source files under the spec's constraints and writes the *exact command lines* the verifier should run into spec Section 9. It does not commit and does not fill Section 9 output.
- **A separate verifier subagent** runs those commands in the host working tree and reports the output tails. Keeping it separate from the implementer means the evidence the reviewer reads was not produced by the hands that wrote the code.
- **The Claude main agent** never touches source or runs verify itself; it dispatches, records the verifier's tails into Section 9, drives git (branch + commit — git is the orchestration glue), and judges.

Phase 3 then has a complete artifact: the diff (auto-injected by the plugin) and Section 9 evidence (real command tails). Codex evaluates against both without trying to re-run anything — its sandbox can't see `.venv` / `node_modules` anyway.

### Why the implementer is Claude and the reviewer is Codex

Earlier versions delegated implementation to Codex via `/codex:rescue`. In practice that cost more than it returned: the Codex sandbox can't run git or the project's build tools, it hits usage quotas mid-task, it sometimes can't write outside the repo, and every dispatch needed a hand-written prompt plus polling. A Claude subagent on the host has none of those problems and is about as fast — the bottleneck is host verification either way.

What that change gives up is one layer of independent perspective *during* implementation. That is why the review side is now a hard rule: **implementation and review must never be the same model.** Codex reviews, always. If Codex stalls or hits its usage limit, the task waits — the skill explicitly forbids substituting a Claude subagent as reviewer, because two Claude agents are "different agents" on paper and the same model in practice.

## When to use it

✅ **Reach for this skill when:**

- The change touches more than one file or introduces a new module
- It involves real business logic, money/billing, auth, user data, DB migrations, or external integrations
- You'd want a written spec before code is written anyway
- You want a second model adversarially reviewing the diff before merging

❌ **Skip it for:**

- Typo fixes, single-line tweaks, comment edits
- Exploration questions ("show me how X works")
- Discussion-only turns

🟡 **For in-between tasks** (< 30 lines, single file, no business logic): the main agent still doesn't edit files itself — it spawns a subagent to make the edit and a separate host subagent to verify, then runs `/codex:review` as a lighter cross-model sanity check before committing. The written spec (Phase 1) is skipped, but the orchestrator boundary and the cross-model rule both hold.

## Files in this repo

| File | Purpose | Loaded when |
|---|---|---|
| `SKILL.md` | Workflow definition, decision rules, command catalog | Auto-loaded when the skill triggers |
| `spec-template.md` | Spec format and filling guide | Phase 1 — Claude writes a spec |
| `implement-prompt.md` | Standard prompt for the implementer subagent | Phase 2 — Claude spawns the implementer |
| `review-prompt.md` | Standard prompts for `/codex:adversarial-review` | Phase 3 — Claude requests review |
| `CLAUDE.md.template` | Minimal per-project `CLAUDE.md` template | Copied into each project root |

## Install

### 1. Install the skill

#### Option A — In-session, one command (recommended) 🌟

Run inside any Claude Code session:

```
/plugin marketplace add ParaGenie/claude-codex-handoff
/plugin install codex-handoff@paragenie-skills
```

That's it — no terminal needed, works on macOS / Linux / Windows. The skill auto-loads whenever a coding task warrants the workflow.

> Requires Claude Code **v2.1.142+** (the version that supports plugin-root `SKILL.md`). Run `claude --version` to check.

#### Option B — Install as a bare skill (terminal)

Useful for older Claude Code versions, air-gapped setups, or if you prefer files-on-disk.

**macOS / Linux** (Bash / Zsh):

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
<summary>No <code>git</code>? Use <code>curl</code> + <code>tar</code> (pre-installed on macOS, Linux, and Windows 10+)</summary>

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

> ⚠️ For Option B, the install target directory **must be named `codex-handoff`** (matching the `name:` field in `SKILL.md`) — Claude Code locates bare skills by directory name, not by repo name.

### 2. Install the codex-plugin-cc plugin

Inside a Claude Code session:

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

If Codex CLI itself isn't installed, `/codex:setup` will offer to install it. Or do it manually:

```bash
npm install -g @openai/codex
```

Then authenticate (supports both ChatGPT subscription and OpenAI API key):

```
!codex login
```

### 3. Bootstrap each project

```bash
cd /path/to/your/project

# 1) Drop in a per-project "identity card"
cp ~/.claude/skills/codex-handoff/CLAUDE.md.template ./CLAUDE.md
# Edit CLAUDE.md: stack, key docs, commands, hard constraints.

# 2) Create artifact directories
mkdir -p .agent/specs .agent/reviews

# 3) (Optional) Pin Codex model / reasoning effort for this project
mkdir -p .codex
cat > .codex/config.toml <<'EOF'
model = "gpt-5.5"
model_reasoning_effort = "high"
EOF

# 4) Commit
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

[...subagent edits files, writes acceptance command lines into spec §9...]

Claude: Implementer finished. Spawning a verifier for the §9 commands.
        [verifier runs `npm run typecheck`, `npm test`, dev-server + manual click-through]
        All green. Recorded tails into §9.1 / §9.2 / §9.3.
        Committed as abc123. Starting Codex review.
        [issues /codex:adversarial-review --background]

[...reviewer works...]

Claude: Review verdict: NEEDS_CHANGES. Reviewer flagged 2 blockers:

  1. isStale() uses local time instead of UTC — could cause
     off-by-hours bugs near midnight.
     → My take: valid. Recommend fix.

  2. Banner re-renders on every parent update.
     → My take: false positive — re-renders here are cheap and intentional.

  Recommended: send #1 back to the implementer, skip #2, then re-review with Codex. OK to proceed?
```

## FAQ

**Q: Why not just use Claude Code alone?**
You absolutely can. But once the change is non-trivial, having the same model both write and grade its own work is a known weak spot. A fresh second model reading the diff cold catches things the author rationalized.

**Q: Why not let Codex implement too?**
It used to (v0.1). The sandbox limits (no git, no `.venv` / `node_modules`), usage quotas, and prompt/polling overhead outweighed the benefit, and speed was a wash. Codex now does the one job Claude structurally cannot: review Claude's code as a different model.

**Q: Does it cost extra?**
Yes — you're running Codex (via your ChatGPT subscription or OpenAI API key) on top of Claude. The cost scales with the size of the change.

**Q: Can I use a different reviewer model?**
Yes, as long as it is **not the implementer's model**. The skill ships with Codex because the codex-plugin-cc plugin makes the diff injection and background job handling turnkey. What you must not do is fall back to a Claude subagent for review when Codex is busy — that is the exact same-model blind spot the workflow exists to avoid.

**Q: What if Codex's review is wrong?**
That's Claude's job in Phase 3 — to triage the report, separate real blockers from false positives, and recommend next steps. You stay the final decision-maker.

**Q: Is there a one-click install?**
Yes — this repo doubles as a Claude Code **plugin marketplace**, so on Claude Code v2.1.142+ you can run `/plugin marketplace add ParaGenie/claude-codex-handoff` followed by `/plugin install codex-handoff@paragenie-skills` inside any session. No terminal needed. The `git clone` route is kept as Option B for older Claude Code versions and air-gapped setups.

**Q: Plugin vs bare skill — what's actually different?**
Functionally, almost nothing. The plugin path installs to `~/.claude/plugins/cache/...` and namespaces the skill as `codex-handoff:codex-handoff`; the bare-skill path installs to `~/.claude/skills/codex-handoff/` and uses the bare name. Since this skill is auto-triggered by task descriptions (not manually invoked by name), the namespace is invisible in practice. The plugin path also gives you `/plugin disable codex-handoff` for clean enable/disable.

## Related skills

- **`karpathy-guidelines`** — code-level conduct (assumptions, simplicity, surgical edits). Complementary: this skill is the *workflow*; that one is the *code conduct*.

## Updating

**Option A (plugin install):** Claude Code refreshes the marketplace on its own cadence; force a refresh by re-running `/plugin install codex-handoff@paragenie-skills`.

**Option B (bare skill install):**

```bash
# macOS / Linux
cd ~/.claude/skills/codex-handoff && git pull
```

```powershell
# Windows (PowerShell)
cd "$env:USERPROFILE\.claude\skills\codex-handoff"; git pull
```

(If you installed via curl+tar, re-run the install command — it overwrites in place.)

Per-project `CLAUDE.md` and `.agent/` directories stay local and are unaffected.

## Contributing

Issues and PRs welcome — especially:

- Tweaks to the spec template based on real-world specs that turned out to need a missing field
- Implementer-prompt or `/codex:*` review-prompt patterns that consistently produce better results
- Stories of where the workflow worked / didn't (instructive for refining decision rules in `SKILL.md`)

## License

[MIT](./LICENSE)
