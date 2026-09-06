# codex-handoff

**[English](./README.md) | [简体中文](./README.zh-CN.md)**

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange)
![Codex CLI](https://img.shields.io/badge/Codex%20CLI-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **让 Claude Code 出方案，Claude 子代理实现，再开一个全新的 OpenAI Codex 会话做对抗式评审。**
> 一套经过实战验证的三阶段工作流，专为"值得写一份 spec 再动手"的代码改动设计 —— 写代码的模型永远不是给它打分的模型。

---

## 为什么需要这个 skill

Claude Code 擅长探查代码、提出关键澄清问题、做判断决策 —— 并且通过一个拥有完整主机权限的子代理，不出会话就能按 spec 落地实现。
Codex CLI 冷读最终 diff，是一个来自**不同模型**的可信第二意见 —— 这是 Claude 自己无论如何给不了自己的东西。

随便拼这两个，得到的是各种含糊和重复工作。
**拼得好**，得到的是：

- 动代码之前先有一份**书面 spec**
- 一个被 spec 约束住、没有即兴发挥空间的**实现子代理**
- 一个来自**不同模型的对抗式评审方**，对"代码为什么这样写"完全没有记忆负担

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
│  阶段 2 — 实现   （Claude 子代理改文件，另一子代理验证）   │
│  Claude：    git switch -c feat/<slug>                     │
│  实现子代理：改源码 + 把验收命令行写进 spec §9（不 commit）│
│  验证子代理：在 host 上跑 §9 命令 → 回报输出尾巴           │
│  Claude：    记录尾巴进 §9 → git commit                    │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│  阶段 3 — 评审   （全新 Codex via /codex:adversarial-…）   │
│  插件自动注入 diff → Codex 对照 spec + §9 evidence 评审    │
│  → 输出阻断项报告                                          │
│  评审方永远是 Codex —— 绝不用 Claude 子代理替代            │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
        Claude 分流报告（真 bug vs. 误报），
        建议修复或放行，最终决定权交还给你。
```

一切**都在一个 Claude Code 会话内**完成：实现走内置 `Agent` 工具，评审走 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 插件提供的 `/codex:*` 斜杠命令。

阶段 1 现在包含一个紧凑的"拷问"循环：Claude 按依赖顺序逐个解决决策分支，每次只问一个带推荐答案的确认/拒绝问题；代码能回答的就先读代码，不问人。如果流程跨会话，Claude 可以写一个 gitignored 的 `.agent/handoff.md` 恢复指针，只放临时状态、建议启用的 skills，且不放 secrets；持久设计仍以已提交的 spec 为准。

### 为什么阶段 2 要拆开

本工作流有一条凌驾一切的规范：**Claude 主 agent 只负责调度和协同沟通，绝不亲手改目标代码库、也不亲手跑 verify。** 所以阶段 2 这样拆：

- **实现子代理**（由主 agent spawn，在主机工作树里运行，有完整 shell + git 可见性）按 spec 的约束改源码，并把验证方应该跑的**精确命令行**写进 spec Section 9。它不 commit，也不填 Section 9 的输出块。
- **另一个验证子代理**在主机工作树里跑这些命令，把输出尾巴回报给主 agent。和实现方分开，意味着评审方读到的证据不是写代码的那双手产出的。
- **Claude 主 agent** 自己不碰源码、不跑 verify：它负责派活、把验证方回报的尾巴记录进 Section 9、驱动 git（建分支 + commit —— git 是调度的黏合剂）、做判断。

到阶段 3，评审方拿到的是完整 artifact：插件自动注入的 diff + Section 9 里真实命令尾巴。Codex 对照两者评估，不再尝试自己重跑 —— 它的 sandbox 反正也看不到 `.venv` / `node_modules`。

### 为什么实现是 Claude、评审是 Codex

早期版本（v0.1）把实现交给 Codex 的 `/codex:rescue`。实际用下来得不偿失：Codex sandbox 跑不了 git 和项目构建工具、任务中途撞用量上限、偶尔写不到仓外要手工套 patch、每次派单都要手写英文 prompt 再轮询。换成主机上的 Claude 子代理，这些问题全没了，速度也基本持平 —— 瓶颈本来就在主机验证。

代价是实现期间少了一层独立视角。所以评审那一侧现在是硬规则：**实现与评审不得是同一个模型。** 评审永远是 Codex。Codex 卡死或撞额度时，任务就等着 —— skill 明文禁止拿 Claude 子代理顶替评审，因为两个 Claude 子代理字面上是"不同 agent"，实际上是同一个模型。

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

🟡 **中等粒度任务**（< 30 行、单文件、无业务逻辑）：主 agent 仍然不亲手改文件 —— 它 spawn 一个 subagent 改文件、再 spawn 另一个 host subagent 验证，然后跑 `/codex:review` 做一次轻量的跨模型检查后再提交。省掉的是书面 spec（阶段 1），但"主 agent 只调度"和"实现评审不同模型"两条边界都不破。

## 仓库文件清单

| 文件 | 用途 | 加载时机 |
|---|---|---|
| `SKILL.md` | 工作流定义、决策规则、命令清单 | 技能触发时自动加载 |
| `spec-template.md` | spec 格式与填写指南 | 阶段 1 —— Claude 撰写 spec 时 |
| `implement-prompt.md` | 实现子代理的标准提示词 | 阶段 2 —— Claude spawn 实现子代理时 |
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
        Spec 已写好，请审阅并回复 "approved" 开始实现。

You: approved

Claude: [git switch -c feat/stale-items-indicator main]
        [用 implement-prompt.md spawn 实现子代理]
        实现子代理正在后台干活，完成后我会回报。

[...子代理改文件，把验收命令行写进 spec §9...]

Claude: 实现完成。spawn 验证子代理跑 §9 的验收命令。
        [验证方跑 `npm run typecheck`、`npm test`、dev server + 手测点击流]
        全绿。已把尾巴记录到 §9.1 / §9.2 / §9.3，并提交为 abc123。
        开始 Codex 评审。
        [执行 /codex:adversarial-review --background]

[...评审方在干活...]

Claude: 评审结论：NEEDS_CHANGES。评审方标出 2 个阻断项：

  1. isStale() 中时区处理使用本地时间而非 UTC ——
     可能在午夜前后产生数小时偏差的 bug。
     → 我的判断：成立，建议修复。

  2. 横幅在父组件每次更新时都重渲染。
     → 我的判断：误报 —— 此处重渲染开销很低，且为实时更新有意保留。

  建议：#1 发回实现子代理修，跳过 #2，然后再让 Codex 评一轮。是否继续？
```

## FAQ

**Q：为什么不直接只用 Claude Code？**
完全可以。但当改动不再是琐碎修改时，让同一个模型既写代码又给自己评分，是一个已知的盲点。第二个模型冷读 diff 时能抓到作者已经自我说服的问题。

**Q：为什么不让 Codex 也负责实现？**
以前（v0.1）是这样的。sandbox 限制（没 git、看不见 `.venv` / `node_modules`）、用量上限、写 prompt 和轮询的开销，加起来超过了收益，速度也没优势。现在 Codex 只做 Claude 在结构上做不到的那件事：以另一个模型的身份评审 Claude 写的代码。

**Q：会增加额外费用吗？**
会 —— 你在 Claude 之外，还会通过 ChatGPT 订阅或 OpenAI API key 跑 Codex。费用随改动规模线性增长。

**Q：可以换别的评审模型吗？**
可以，只要**不是实现方的模型**。默认用 Codex 是因为 codex-plugin-cc 插件把 diff 注入和后台任务管理都做好了。绝对不能做的是：Codex 忙的时候拿 Claude 子代理兜底评审 —— 那正是本工作流要避免的同模型盲区。

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
- 能稳定产出更好结果的实现子代理提示词或 `/codex:*` 评审提示词模式
- 工作流"成功 / 失败"故事 —— 对打磨 `SKILL.md` 中的决策规则非常有用

## 许可证

[MIT](./LICENSE)
