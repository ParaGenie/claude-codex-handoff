# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **Let Claude Code plan, OpenAI Codex CLI implement, and a fresh Codex session adversarially review.**
> A battle-tested three-phase workflow for code changes that deserve a written spec — not the same model writing and grading its own homework.

---

## Why this exists

Claude Code is excellent at exploring code, asking the right clarifying questions, and making judgment calls.
Codex CLI is fast at mechanical implementation, runs well in the background, and is a credible **second opinion** when it comes back fresh.

Combine them poorly and you get hand-waving and double work. Combine them well and you get:

- A **written spec** before any code is touched
- An **independent implementer** that can't take shortcuts the planner already rationalized
- An **adversarial reviewer** with no memory of why the code was written this way

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
│  PHASE 2 — IMPLEMENT   (split: Codex edits, Claude verifies)│
│  Claude:  git switch -c feat/<slug>                        │
│  Codex:   edit files + list cmds in spec §9 (no git/shell) │
│  Claude:  run §9 cmds → paste output → git commit          │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│  PHASE 3 — REVIEW   (fresh Codex via /codex:adversarial-…) │
│  Plugin auto-injects diff → Codex evaluates against        │
│  spec + §9 evidence → report blockers                      │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
        Claude triages the report (real bug vs. false positive),
        recommends fix-or-ship, hands the decision back to you.
```

All communication happens **inside one Claude Code session** via `/codex:*` slash commands provided by the [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin.

### Why Phase 2 is split

The Codex CLI sandbox has two unconfigurable limits: `.git/` is read-only (no `commit` / `branch`), and `.venv` / `node_modules` are not visible inside the sandbox (no `pytest` / `npm run build`). So the workflow splits Phase 2 along that boundary:

- **Codex** does what its sandbox allows: edit source files and write the *exact command lines* the verifier should run, into spec Section 9.
- **Claude main session** does git ops + verify against the host working tree (where `.venv` / `node_modules` actually live), pastes the command output into Section 9, and commits.

Phase 3 then has a complete artifact: the diff (auto-injected by the plugin) and Section 9 evidence (paste with real command tails). The reviewer evaluates against both without trying to re-run anything — which it couldn't, anyway.

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

🟡 **For in-between tasks** (< 30 lines, single file, no business logic): Claude implements directly and runs `/codex:review` as a lighter sanity check — Phases 1 & 2 are skipped.

## Files in this repo

| File | Purpose | Loaded when |
|---|---|---|
| `SKILL.md` | Workflow definition, decision rules, command catalog | Auto-loaded when the skill triggers |
| `spec-template.md` | Spec format and filling guide | Phase 1 — Claude writes a spec |
| `rescue-prompt.md` | Standard prompts for `/codex:rescue` | Phase 2 — Claude delegates to Codex |
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
        Spec written. Please review and reply "approved" to hand off to Codex.

You: approved

Claude: [git switch -c feat/stale-items-indicator main]
        [issues /codex:rescue --background]
        Codex is implementing in the background. I'll check back when it's done.

[...Codex edits files, writes acceptance command lines into spec §9...]

Claude: Codex finished. Running acceptance commands from §9 now.
        [runs `npm run typecheck`, `npm test`, dev-server + manual click-through]
        All green. Pasted output into §9.1 / §9.2 / §9.3.
        Committed as abc123. Starting review.
        [issues /codex:adversarial-review --background]

[...reviewer works...]

Claude: Review verdict: NEEDS_CHANGES. Reviewer flagged 2 blockers:

  1. isStale() uses local time instead of UTC — could cause
     off-by-hours bugs near midnight.
     → My take: valid. Recommend fix.

  2. Banner re-renders on every parent update.
     → My take: false positive — re-renders here are cheap and intentional.

  Recommended: /codex:rescue --resume to fix #1, skip #2. OK to proceed?
```

## FAQ

**Q: Why not just use Claude Code alone?**
You absolutely can. But once the change is non-trivial, having the same model both write and grade its own work is a known weak spot. A fresh second model reading the diff cold catches things the author rationalized.

**Q: Why not just use Codex CLI alone?**
Codex is fast and capable, but it benefits from a written spec and a separate review pass. This skill is the protocol that wraps both.

**Q: Does it cost extra?**
Yes — you're running Codex (via your ChatGPT subscription or OpenAI API key) on top of Claude. The cost scales with the size of the change.

**Q: Can I use a different reviewer model?**
The skill ships with Codex as both implementer and reviewer because they're decoupled by **session**, not by model — a fresh Codex with no memory of the implementation is genuinely adversarial. Swap if you have a strong preference; the skill structure stays the same.

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
- New `/codex:*` prompt patterns that consistently produce better implementations or reviews
- Stories of where the workflow worked / didn't (instructive for refining decision rules in `SKILL.md`)

## License

[MIT](./LICENSE)
