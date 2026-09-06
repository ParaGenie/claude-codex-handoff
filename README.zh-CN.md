# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **Claude Code 出方案，Claude 子代理实现，再开一个全新的 OpenAI Codex 会话做对抗式评审。**
> 一套三阶段工作流，专为"值得写一份 spec 再动手"的代码改动设计 —— 写代码的模型永远不是给它打分的模型。

---

## 为什么需要这个 skill

Claude Code 擅长探查代码、提出关键澄清问题，并且通过一个拥有完整主机权限的子代理，不出会话就能按 spec 落地实现。它唯一给不了自己的，是一个可信的第二意见：写代码的模型会为自己的选择找理由。Codex CLI 冷读最终 diff，就是来自**不同模型**的那个第二意见。

这个 skill 把协议固化下来，让每个任务都得到：

- 动代码之前先有一份**书面 spec**
- 一个被 spec 约束住、没有即兴发挥空间的**实现子代理**
- 一个来自**不同模型的对抗式评审方**，对"代码为什么这样写"完全没有记忆负担

## 工作流

```
┌────────────────────────────────────────────────────────────┐
│  阶段 1 — 规划    （Claude Code）                          │
│  探查代码 → 一次只问一个澄清问题 →                         │
│  撰写 .agent/specs/<slug>.md → 停下等你审批                │
└──────────────────────────┬─────────────────────────────────┘
                           │ 你回复 "approved"
                           ▼
┌────────────────────────────────────────────────────────────┐
│  阶段 2 — 实现                                             │
│  Claude：    git switch -c feat/<slug>                     │
│  实现子代理：改源码 + 把验收命令行写进 spec §9（不 commit）│
│  验证子代理：在 host 上跑 §9 命令 → 回报输出尾巴           │
│  Claude：    记录尾巴 → git commit                         │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│  阶段 3 — 评审   （全新 Codex via /codex:adversarial-…）   │
│  插件自动注入 diff → Codex 对照 spec + §9 evidence 评审    │
│  → 输出阻断项报告                                          │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
        Claude 分流报告（真 bug vs. 误报），
        建议修复或放行，最终决定权交还给你。
```

一切**都在一个 Claude Code 会话内**完成：实现走内置 `Agent` 工具，评审走 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 插件提供的 `/codex:*` 斜杠命令。

### 两条铁律

1. **主 Claude agent 只负责调度。** 它绝不亲手改目标代码库、也不亲手跑 verify —— 哪怕只是一行。实现子代理按 spec 约束改源码，并把验证方该跑的**命令行**写进 spec §9；另一个验证子代理跑这些命令、回报输出尾巴；主 agent 记录证据、驱动 git、做判断。两双手分开，意味着 Codex 读到的证据不是写代码的那双手产出的。

2. **实现与评审永远不是同一个模型。** Claude 实现，Codex 评审，没有例外。Codex 卡死或撞额度时任务就等着 —— skill 明文禁止拿 Claude 子代理顶替评审，因为两个 Claude 子代理字面上是"不同 agent"，实际上是同一个模型。

为什么 Codex 只评审不实现：v0.1 把实现交给 `/codex:rescue`，而 Codex sandbox（写不了 git、看不见 `.venv` / `node_modules`、中途撞额度、写 prompt 和轮询的开销）得不偿失。主机上的 Claude 子代理没有这些问题，速度也基本持平。但 sandbox 恰好适合冷读 diff —— 所以 Codex 现在只做 Claude 在结构上做不到的那件事。

## 什么时候用

✅ **该用的场景：** 改动涉及多个文件或新模块；触及真实业务逻辑、计费/账务、鉴权、用户数据、数据库迁移、第三方对接；或你本来就想先写 spec。

❌ **跳过的场景：** 错别字、单行微调、注释改动、探索性提问、仅讨论不落代码的对话轮。

🟡 **中等粒度任务**（< 30 行、单文件、无业务逻辑）：省掉 spec，但仍由子代理改文件、另一子代理验证，提交前跑一次轻量的 `/codex:review` 跨模型检查。

## 仓库文件清单

| 文件 | 用途 | 加载时机 |
|---|---|---|
| `SKILL.md` | 角色、两条铁律、阶段流程、命令速查 | 技能触发时自动加载 |
| `spec-template.md` | spec 格式、填写指南、完整示例 | 阶段 1 |
| `implement-prompt.md` | 实现子代理提示词、健全性检查表、修复回路 | 阶段 2 |
| `review-prompt.md` | Codex 评审提示词、关注点、报告分流 | 阶段 3 |
| `CLAUDE.md.template` | 极简的项目级 `CLAUDE.md` | 复制到各项目根目录 |

## 安装

### 1. 安装 skill 文件

#### 方案 A —— 会话内一键安装（推荐）🌟

在任意 Claude Code 会话中执行：

```
/plugin marketplace add ParaGenie/claude-codex-handoff
/plugin install codex-handoff@paragenie-skills
```

不用开终端，macOS / Linux / Windows 都一样。需要 Claude Code **v2.1.142+**（支持 plugin root 直接放 `SKILL.md`），用 `claude --version` 查看。

#### 方案 B —— 装为裸 skill（终端方式）

适合 Claude Code 版本较旧、离线环境，或就是喜欢文件落到磁盘的人。

**macOS / Linux**：

```bash
mkdir -p ~/.claude/skills && \
  git clone https://github.com/ParaGenie/claude-codex-handoff.git \
            ~/.claude/skills/codex-handoff
```

**Windows**（PowerShell）：

```powershell
New-Item "$env:USERPROFILE\.claude\skills" -ItemType Directory -Force | Out-Null
git clone https://github.com/ParaGenie/claude-codex-handoff.git "$env:USERPROFILE\.claude\skills\codex-handoff"
```

<details>
<summary>没装 <code>git</code>？用 <code>curl</code> + <code>tar</code></summary>

**macOS / Linux：**

```bash
mkdir -p ~/.claude/skills/codex-handoff && \
  curl -L https://github.com/ParaGenie/claude-codex-handoff/tarball/main | \
  tar -xz --strip-components=1 -C ~/.claude/skills/codex-handoff
```

**Windows（PowerShell）：**

```powershell
$dest = "$env:USERPROFILE\.claude\skills\codex-handoff"
New-Item $dest -ItemType Directory -Force | Out-Null
curl.exe -L -o "$env:TEMP\codex-handoff.tgz" https://github.com/ParaGenie/claude-codex-handoff/tarball/main
tar.exe -xz --strip-components=1 -C $dest -f "$env:TEMP\codex-handoff.tgz"
Remove-Item "$env:TEMP\codex-handoff.tgz"
```

</details>

> ⚠️ 方案 B 的目标目录名**必须叫 `codex-handoff`**（与 `SKILL.md` 中 `name:` 一致）—— Claude Code 按目录名识别裸 skill。

### 2. 安装 codex-plugin-cc 插件

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

未装 Codex CLI 时 `/codex:setup` 会提示安装（或 `npm install -g @openai/codex`）。然后 `!codex login` 登录（支持 ChatGPT 订阅与 OpenAI API key）。

### 3. 初始化项目

```bash
cd /path/to/your/project
cp ~/.claude/skills/codex-handoff/CLAUDE.md.template ./CLAUDE.md   # 编辑：技术栈、文档、命令、约束
mkdir -p .agent/specs .agent/reviews

# 可选：为本项目固定 Codex 模型与思考强度
mkdir -p .codex && cat > .codex/config.toml <<'EOF'
model = "gpt-5.5"
model_reasoning_effort = "high"
EOF

git add CLAUDE.md .agent/ .codex/
git commit -m "chore: bootstrap codex-handoff workflow"
```

## 真实运行一次长这样

```
You: 给条目列表加一个「过期」徽标 —— 高亮超过 24 小时未更新的条目。
     走 codex-handoff 流程。

Claude: [加载 skill、探查代码、提 1-2 个澄清问题，
         撰写 .agent/specs/2026-05-21-stale-items-indicator.md]
        Spec 已写好，请审阅并回复 "approved" 开始实现。

You: approved

Claude: [git switch -c feat/stale-items-indicator main]
        [用 implement-prompt.md spawn 实现子代理]
        实现子代理正在后台干活，完成后我会回报。

Claude: 实现完成。spawn 验证子代理跑 §9 的验收命令。
        [验证方跑 `npm run typecheck`、`npm test`、dev server + 手测点击流]
        全绿。尾巴已记录到 §9，提交为 abc123。开始 Codex 评审。
        [执行 /codex:adversarial-review --background]

Claude: 评审结论：NEEDS_CHANGES。评审方标出 2 个阻断项：

  1. isStale() 用本地时间而非 UTC —— 午夜前后会差几个小时。
     → 我的判断：成立，建议修复。

  2. 横幅在父组件每次更新时都重渲染。
     → 我的判断：误报 —— 此处重渲染开销很低，且是有意为之。

  建议：#1 发回实现子代理修，跳过 #2，然后再让 Codex 评一轮。是否继续？
```

## FAQ

**Q：为什么不直接只用 Claude Code？**
完全可以。但改动不再琐碎时，让同一个模型既写代码又给自己评分是已知盲点。第二个模型冷读 diff 能抓到作者已经自我说服的问题。

**Q：会增加额外费用吗？**
会 —— Codex 走你的 ChatGPT 订阅或 OpenAI API key，在 Claude 之外按改动规模计费。

**Q：可以换别的评审模型吗？**
可以，只要**不是实现方的模型**。默认用 Codex 是因为 codex-plugin-cc 把 diff 注入和后台任务都做好了。绝不能做的是 Codex 忙时拿 Claude 子代理兜底。

**Q：万一 Codex 评审结论是错的？**
那正是阶段 3 中 Claude 的工作：分流报告，区分真阻断项与误报，给出建议。最终决定权在你。

**Q：plugin 安装 vs 裸 skill 安装有什么区别？**
几乎没有。plugin 装到 `~/.claude/plugins/cache/...`，skill 名带命名空间 `codex-handoff:codex-handoff`；裸 skill 装到 `~/.claude/skills/codex-handoff/`。本 skill 按任务描述自动触发，命名空间实际无感。plugin 路径额外提供 `/plugin disable codex-handoff`。

## 关联技能

- **`karpathy-guidelines`** —— 代码层面的行为准则（假设、简洁性、外科手术式编辑）。本技能管*工作流*，那个管*代码风格*。

## 更新方式

- **plugin：** 重新跑 `/plugin install codex-handoff@paragenie-skills` 强制刷新。
- **裸 skill：** `cd ~/.claude/skills/codex-handoff && git pull`（PowerShell：`cd "$env:USERPROFILE\.claude\skills\codex-handoff"; git pull`）。curl+tar 装的重跑安装命令即可。

项目级 `CLAUDE.md` 与 `.agent/` 不受影响。

## 贡献

欢迎 Issue 和 PR，尤其是：实际 spec 证明缺少的模板字段、稳定更好用的实现/评审提示词模式、工作流成功或失败的故事。

## 许可证

[MIT](./LICENSE)
