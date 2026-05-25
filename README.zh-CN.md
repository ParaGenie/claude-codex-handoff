# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **让 Claude Code 出方案，OpenAI Codex CLI 实现，再开一个全新的 Codex 会话做对抗式评审。**
> 一套经过实战验证的三阶段工作流，专为"值得写一份 spec 再动手"的代码改动设计 —— 不让同一个模型既写代码又给自己打分。

---

## 为什么需要这个 skill

Claude Code 擅长探查代码、提出关键澄清问题、做判断决策。
Codex CLI 实现速度快、能稳定后台跑、并且开一个全新会话时，它就是一个可信的"独立第二意见"。

随便拼这两个，得到的是各种含糊和重复工作。
**拼得好**，得到的是：

- 动代码之前先有一份**书面 spec**
- 一个**独立的实现方**，不会接受规划方早已自我说服的那些捷径
- 一个**对抗式评审方**，对"代码为什么这样写"完全没有记忆负担

这个 skill 把这套协议固化下来，让你不用每次重新发明。

## 60 秒了解工作流

```
┌────────────────────────────────────────────────────────────┐
│  阶段 1 — 规划    （Claude Code）                          │
│  探查代码 → 提澄清问题 →                                   │
│  撰写 .agent/specs/<slug>.md → 停下等你审批                │
└──────────────────────────┬─────────────────────────────────┘
                           │ 你回复 "approved"
                           ▼
┌────────────────────────────────────────────────────────────┐
│  阶段 2 — 实现   （拆分：Codex 改文件，Claude 验证）       │
│  Claude：git switch -c feat/<slug>                         │
│  Codex： 改源码 + 把验收命令行写进 spec §9（不跑 git/命令）│
│  Claude：跑 §9 命令 → 粘贴输出 → git commit                │
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

所有沟通**都在一个 Claude Code 会话内**完成，通过 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 插件提供的 `/codex:*` 斜杠命令打通。

### 为什么阶段 2 要拆开

Codex CLI 的 sandbox 有两条不可配置的限制：`.git/` 只读（不能 `commit` / `branch`）、`.venv` / `node_modules` 在 sandbox 内不可见（不能 `pytest` / `npm run build`）。所以工作流沿这条边界拆分阶段 2：

- **Codex** 干 sandbox 允许的事：改源码、把验证方应该跑的**精确命令行**写进 spec Section 9
- **Claude 主会话** 干主仓库工作树才能干的事：git 操作 + 跑 verify（主工作树里 `.venv` / `node_modules` 是真的）、把命令输出粘贴回 Section 9、提交

到阶段 3，评审方拿到的是完整 artifact：插件自动注入的 diff + Section 9 里真实命令尾巴。评审方对照两者评估，不再尝试自己重跑 —— 反正它也跑不了。

## 什么时候用

✅ **该用这个 skill 的场景：**

- 改动涉及多个文件，或引入新模块
- 触及真实业务逻辑、计费/账务、鉴权、用户数据、数据库迁移、第三方对接
- 你本来就想先写 spec 再动手
- 合并前你想让第二个模型对抗式地评审 diff

❌ **跳过这个 skill 的场景：**

- 错别字、单行微调、注释改动
- 探索性提问（"给我看看 X 是怎么工作的"）
- 仅讨论不落代码的对话轮

🟡 **中等粒度任务**（< 30 行、单文件、无业务逻辑）：Claude 直接动手实现，仅跑 `/codex:review` 做一次轻量兜底检查 —— 跳过阶段 1 与阶段 2。

## 仓库文件清单

| 文件 | 用途 | 加载时机 |
|---|---|---|
| `SKILL.md` | 工作流定义、决策规则、命令清单 | 技能触发时自动加载 |
| `spec-template.md` | spec 格式与填写指南 | 阶段 1 —— Claude 撰写 spec 时 |
| `rescue-prompt.md` | `/codex:rescue` 的标准提示词 | 阶段 2 —— Claude 移交给 Codex 时 |
| `review-prompt.md` | `/codex:adversarial-review` 的标准提示词 | 阶段 3 —— Claude 发起评审时 |
| `CLAUDE.md.template` | 极简的项目级 `CLAUDE.md` 模板 | 复制到各项目根目录 |

## 安装

### 1. 安装 skill 文件

#### 方案 A —— 会话内一键安装（推荐）🌟

在任意 Claude Code 会话中执行：

```
/plugin marketplace add ParaGenie/claude-codex-handoff
/plugin install codex-handoff@paragenie-skills
```

就这两行 —— 不用开终端，macOS / Linux / Windows 都一样。skill 会在相关任务出现时自动加载。

> 需要 Claude Code **v2.1.142+**（支持 plugin root 直接放 `SKILL.md` 的版本）。跑 `claude --version` 查看你的版本。

#### 方案 B —— 装为裸 skill（终端方式）

适合 Claude Code 版本较旧、离线环境，或就是喜欢文件落到磁盘的人。

**macOS / Linux**（Bash / Zsh）：

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
<summary>没装 <code>git</code>？用 <code>curl</code> + <code>tar</code>（macOS / Linux / Windows 10+ 均自带）</summary>

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

> ⚠️ 使用方案 B 时，目标目录名**必须叫 `codex-handoff`**（与 `SKILL.md` 中 `name:` 字段一致）—— Claude Code 是按目录名识别裸 skill 的，与 repo 名无关。

### 2. 安装 codex-plugin-cc 插件

在 Claude Code 会话中执行：

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

如果尚未安装 Codex CLI，`/codex:setup` 会提示是否帮你装。也可以手动装：

```bash
npm install -g @openai/codex
```

然后登录鉴权（支持 ChatGPT 订阅账号与 OpenAI API key）：

```
!codex login
```

### 3. 初始化项目

```bash
cd /path/to/your/project

# 1) 放入项目级"身份卡"
cp ~/.claude/skills/codex-handoff/CLAUDE.md.template ./CLAUDE.md
# 编辑 CLAUDE.md：技术栈、关键文档、常用命令、硬性约束。

# 2) 创建产物目录
mkdir -p .agent/specs .agent/reviews

# 3) （可选）为本项目固定 Codex 模型与思考强度
mkdir -p .codex
cat > .codex/config.toml <<'EOF'
model = "gpt-5.5"
model_reasoning_effort = "high"
EOF

# 4) 一次性提交
git add CLAUDE.md .agent/ .codex/
git commit -m "chore: bootstrap codex-handoff workflow"
```

## 真实运行一次长这样

```
You: 给条目列表加一个「过期」徽标 —— 高亮超过 24 小时未更新的条目。
     走 codex-handoff 流程。

Claude: [加载 skill、探查代码、提 1-2 个澄清问题，
         撰写 .agent/specs/2026-05-21-stale-items-indicator.md]
        Spec 已写好，请审阅并回复 "approved" 移交给 Codex。

You: approved

Claude: [git switch -c feat/stale-items-indicator main]
        [执行 /codex:rescue --background]
        Codex 正在后台实现，完成后我会回报。

[...Codex 改文件，把验收命令行写进 spec §9...]

Claude: Codex 已完成，开始跑 §9 的验收命令。
        [跑 `npm run typecheck`、`npm test`、dev server + 手测点击流]
        全绿。已把输出粘贴到 §9.1 / §9.2 / §9.3，并提交为 abc123。
        开始评审。
        [执行 /codex:adversarial-review --background]

[...评审方在干活...]

Claude: 评审结论：NEEDS_CHANGES。评审方标出 2 个阻断项：

  1. isStale() 中时区处理使用本地时间而非 UTC ——
     可能在午夜前后产生数小时偏差的 bug。
     → 我的判断：成立，建议修复。

  2. 横幅在父组件每次更新时都重渲染。
     → 我的判断：误报 —— 此处重渲染开销很低，且为实时更新有意保留。

  建议：用 /codex:rescue --resume 修复 #1，跳过 #2。是否继续？
```

## FAQ

**Q：为什么不直接只用 Claude Code？**
完全可以。但当改动不再是琐碎修改时，让同一个模型既写代码又给自己评分，是一个已知的盲点。第二个模型冷读 diff 时能抓到作者已经自我说服的问题。

**Q：为什么不直接只用 Codex CLI？**
Codex 足够快也足够能干，但它在"先有一份 spec、再有一次独立评审"的协议下表现更稳。这个 skill 就是把这套协议包好了。

**Q：会增加额外费用吗？**
会 —— 你在 Claude 之外，还会通过 ChatGPT 订阅或 OpenAI API key 跑 Codex。费用随改动规模线性增长。

**Q：可以换别的评审模型吗？**
可以。skill 默认让 Codex 同时承担实现和评审角色，因为这里的"对抗性"靠的是**独立的会话**而非不同模型 —— 一个对实现过程毫无记忆的全新 Codex 会话，本身就足够独立。如果你有强偏好可以替换，工作流结构不变。

**Q：万一 Codex 评审结论是错的怎么办？**
那正是阶段 3 中 Claude 的工作 —— 分流报告，区分真阻断项与误报，给出建议。最终决定权始终在你手里。

**Q：有一键安装吗？**
有 —— 本 repo 同时是一个 Claude Code **plugin marketplace**。在 Claude Code v2.1.142+ 中，进任意会话执行 `/plugin marketplace add ParaGenie/claude-codex-handoff` 然后 `/plugin install codex-handoff@paragenie-skills` 即可，不用开终端。`git clone` 的方案 B 保留作为旧版本 Claude Code 和离线环境的备选。

**Q：plugin 安装 vs 裸 skill 安装有什么区别？**
功能上几乎没区别。plugin 路径装到 `~/.claude/plugins/cache/...`，skill 被命名空间为 `codex-handoff:codex-handoff`；裸 skill 路径装到 `~/.claude/skills/codex-handoff/`，名字保持 `codex-handoff`。因为本 skill 是按任务描述**自动触发**的（不需要手动调用 skill 名），命名空间在实际使用中无感。plugin 路径额外给你 `/plugin disable codex-handoff` 这种一行启用/禁用能力。

## 关联技能

- **`karpathy-guidelines`** —— 代码层面的行为准则（假设、简洁性、外科手术式编辑）。与本技能互补：本技能管*工作流*，那个管*代码风格*。

## 更新方式

**方案 A（plugin 安装）：** Claude Code 会按自己的节奏刷新 marketplace；如需强制刷新，重新跑一次 `/plugin install codex-handoff@paragenie-skills` 即可。

**方案 B（裸 skill 安装）：**

```bash
# macOS / Linux
cd ~/.claude/skills/codex-handoff && git pull
```

```powershell
# Windows (PowerShell)
cd "$env:USERPROFILE\.claude\skills\codex-handoff"; git pull
```

（如果当初是用 curl+tar 装的，重新跑一遍安装命令即可，会原地覆盖。）

项目级的 `CLAUDE.md` 与 `.agent/` 目录是项目本地的，不受影响。

## 贡献

欢迎提 Issue 和 PR，尤其欢迎：

- 基于实际写过的 spec、对 spec template 字段的修订建议
- 能稳定产出更好实现/评审的 `/codex:*` 提示词模式
- 工作流"成功 / 失败"故事 —— 对打磨 `SKILL.md` 中的决策规则非常有用

## 许可证

[MIT](./LICENSE)
