# cc-flow

Claude Code 开发工作流插件：**以 conductor 为底座，按后果分级，一片一上线**。从 token-router 的 workflow v2.1
抽离，把作者基于 conductor 的工作方式（分诊、访谈、拆分守则、Claude Design 设计环节、守卫、新项目一键接入）打包成
插件，新项目不用再从头搭流程。0.6 按两个项目的实测数据改轻（审阅占 44% token、spec 首轮全 FAIL、记账 PR 占一半、
上线后的问题 7/9 来自真实数据与产品理解）。

```
你的想法 → /flow:triage 分诊卡 → 你说「做」
   ├─ 一档（双向门、一个 PR 做得完）→ /flow:spec → PR
   └─ 二 / 三档 → /conductor:new-track（spec + plan，phase = 能上线的小片）→ 立项确认 → /conductor:implement
→ 每片：测试先行 → check → PR →（三档单向门片：审一次 + 你合并）→ /flow:closeout 部署 + 冒烟 + 清理 → 你去试 → 下一片
```

机制：
- **conductor 是骨架**：`/conductor:implement` 照 `conductor/workflow.md` 的 Task Workflow 与 Phase 完成协议执行，flow
  托管这份文件；
- **按后果分级**：错了 revert 就没事的走一 / 二档；收不回来的（动钱、记账口径、密钥、数据迁移、审批守卫）走三档；
- **小片上线**：plan 的一个 phase 一个 PR，非测试代码约 ≤400 行，端到端可用，不按层切；
- **一个改动审一次**：一档有逻辑的 1 次；二档 track 做完 1 次；三档 spec 1 次 + 单向门片合并前 1 次；只有 BLOCKER 必须修；
- **停点只有四处**：分诊卡 / 访谈 / 立项确认 / 三档合并；
- **主 checkout 只读 + worktree**；
- **流程类教训当天改规则**。

规则正文见 [`plugins/flow/templates/workflow.md`](plugins/flow/templates/workflow.md)。

## 新项目接入

```text
/plugin marketplace add ethanzyang/cc-flow
/plugin install flow@cc-flow
/plugin marketplace add https://github.com/pilotparpikhodjaev/conductor_cc.git
/plugin install conductor@conductor-cc
/flow:init
```

`/flow:init` 放规则 → 跑完整的 `/conductor:setup` 产品定义访谈（产品 / 规范 / 技术栈 / 代码规范 / 首个 track）→
问三件事（单向门、怎么上线、要不要设计系统）→ 填项目补充与 CLAUDE.md → 最后激活 hook。已有提交的仓库在
`adopt-flow` worktree 里做。产出：

| 文件 | 内容 |
|---|---|
| `conductor/product.md` 等 | conductor setup 的产物：产品、产品规范、技术栈、代码规范、`tracks.md` |
| `conductor/workflow.md` | 规则正文：**托管区**（插件下发）+ 文末**项目补充 P1–P6**（单向门 / 上线 / 命令 / UI / 失败基线 / 其他） |
| `conductor/backlog.md` | 想做但没立项的条目 |
| `dev-docs/TEAM_GUIDE.md` | 5 分钟上手导览（托管） |
| `CLAUDE.md` | 高频规则（≤约 100 行）+ 工作流段 + 分支纪律 |
| `.claude/rules/*.md` | 按文件类型的规则（frontmatter `paths:`）；只为既有约定建 |
| `.claude/flow.json` | hook 配置：保护路径、单向门提醒路径、格式化命令等 |
| `.claude/settings.json` | 合并：flow + conductor 插件自动安装 + 权限基线 |

依赖：conductor 插件（二 / 三档的 track）、`jq`（必需，hook 全靠它）、`python3`（Bash 守卫、JSON 重复键检查）、
`gh`（PR 与度量）、浏览器自动化（截图）。

## 包含什么

**Skills**（调用时带前缀 `flow:`）

| 命令 | 用途 |
|---|---|
| `/flow:triage` | 分诊卡：档位 / 车道与设计输入 / 第一片做完你能 / 切片 / 这次不做 / 胃口 / 怎么验收；讨论模式只出方案 |
| `/flow:spec` | 一档：一页 DELTA 规格 → 实现 → check → PR |
| `/flow:closeout` | 每片合并后：部署 + 冒烟 + 清理 + 请用户试；track 最后一片触发整体审阅 |
| `/flow:catchup` | `/clear` 或新会话后恢复进度（分支、plan、tracks、PR） |
| `/flow:design-track` | 立项里的设计环节：写 BRIEF 推给你画 → 拉回设计包、快照进 track |
| `/flow:design push` / `pull` | 仓库设计系统 ⇄ 自己的 Claude Design 副本；仅手动调用 |
| `/flow:visual-verify` | 截图矩阵验收（对设计稿 / 对现状 / 对 spec 清单），按需 |
| `/flow:stats` | 度量：PR 时长、大小、审阅次数、只改文档的提交占比、上线后 48 小时内的修复 |
| `/flow:init` | 接入新项目（编排 conductor setup）；已接入时：插件升级后同步托管区、补设计模块 |

track 的立项与实现用 conductor 自己的 `/conductor:new-track`、`/conductor:implement`，行为由 workflow.md 约束。

**Agents**：`flow:spec-reviewer`（三档写代码前审 spec 一次）、`flow:phase-gate-reviewer`（代码审阅：一个 PR 或整个
track；严重度按后果定，只有 BLOCKER 必须修）、`flow:security-reviewer` / `flow:architecture-reviewer`（按需加派）。

**Hooks**（只对有 `.claude/flow.json` 的仓库生效，插件装在用户级也不影响别的仓库）

| 事件 | 做什么 |
|---|---|
| SessionStart | 注入「本仓库走 flow」上下文；托管区版本漂移提示；未收尾提醒；worktree 软链 .env |
| PreToolUse Edit/Write | 主 checkout 只读；track 的 design 快照只读（新建放行）；`protected_paths`；`no_full_rewrite` |
| PreToolUse Bash | 只拦致命不可逆命令（按 shell 词法判断，提到不算）：删根 / 家目录 / 主 checkout / .git、非测试库 DROP / TRUNCATE、强推主干、删数据卷、抹盘；Bash 写 protected_paths / worktree_links 文件、no_full_rewrite、已入仓的旧 design 快照 |
| PostToolUse Edit/Write | `format_on_edit`；tracks.md 格式（`---` 分隔、状态标记）；JSON 重复键；单向门提醒 |
| CwdChanged | 进 worktree 时软链 `worktree_links` |
| Stop | 主 checkout 被写 / 已合并未删的 worktree |

## 设计模块（可选）

有 UI 的项目在 `/flow:init` 时选「要」即启用（已接入的项目重跑 `/flow:init` 补）：

- `design-system/` 是设计唯一真相源，协作规范 `design-system/SYNC.md`（托管区 + 项目补充 D1–D3）
- Claude Design 的设计系统项目是账号私有的，所以用 git 合流：每人 `/design-login` 后
  `/flow:design push` 建自己的云端副本；改了已有设计文件当天 `/flow:design pull` 拉回开 PR
- 视觉没定的新界面：`/flow:design-track <feature>` 先写 BRIEF 推给你 → 你在 Claude Design 画 → 再跑一次拉回
  `design-system/<feature>/`、快照进 track 的 `design/`，接着出 spec / plan
- CLAUDE.md 设计段声明「美学方向归设计系统」：有设计输入时 frontend-design 等 skill 的自由发挥条款失效
- 实现侧镜像 token 的（如 `web/src/styles/tokens.css`），在 SYNC.md D2 写清并加字符级比对测试——
  每个项目不一样，flow 只留位置、不做通用实现

## `.claude/flow.json`

```jsonc
{
  "version": 1,
  "main_branch": "main",
  "worktree_links": [".env"],                       // 进 worktree 时从主 checkout 软链
  "protected_paths": [                              // Edit/Write 一律拦；reason 原样回给模型
    { "glob": "*/.github/workflows/*", "reason": "CI 配置禁止修改。" }
  ],
  "no_full_rewrite": [                              // 已存在的文件不许 Write 整文件重写，也不许 Bash 重定向写
    { "glob": "*/web/src/i18n/locales/*.json", "reason": "locale 有重复键，往返会被静默折叠。" }
  ],
  "sensitive_paths": ["*/billing/*", "*/payment/*"], // 改到时往模型上下文注入一次「单向门」提醒（判据仍是后果）
  "format_on_edit": [                               // 在被改文件所属仓库根执行，路径在 $FILE
    { "globs": ["*.go"], "cmd": "gofmt -w \"$FILE\"" },
    { "globs": ["*.ts", "*.tsx"], "cmd": "cd web && bunx prettier --write \"$FILE\"" }
  ],
  "json_dup_key_check": [                           // JSON 合法 + 同一对象内不许新增重复键
    { "glob": "*/web/src/i18n/locales/*.json", "known": ["历史遗留的重复键"] }
  ],
  "design": { "dir": "design-system" },             // 设计模块；有它 /flow:init 才管 SYNC.md
  "bash_guard": { "test_db_pattern": "(^|_)test(_|$)" } // 只有匹配它的库允许 DROP / TRUNCATE
}
```

glob 用 shell `case` 语义，`*` 可以跨 `/`，所以开头写 `*/` 就能匹配任意深度。体检：
`bash plugins/flow/scripts/doctor.sh <项目目录>`。

## 托管区与升级

`conductor/workflow.md` 里夹在 `<!-- flow:managed:begin vX -->` 和 `<!-- flow:managed:end -->`
之间的内容由插件下发，`/flow:init` 整段覆盖；标记之外（文末项目补充）一字不动。

- 在某个项目里发现**所有项目都适用**的流程问题 → 改本仓库 `plugins/flow/templates/`，发版
- **只属于那个项目**的 → 写进它的 workflow.md 项目补充

为什么规则正文落在项目里：每个 session 和 agent 都能直接读到，项目补充与托管区在同一个文件里；
托管区 + 版本号 + SessionStart 漂移提示是「一处维护、各项目同步」的折中。

## 发版

1. 改 `plugins/flow/`；跑 `bash tests/lint.sh && bash tests/hooks.test.sh && python3 tests/guard-bash.test.py`（全绿）
2. `claude plugin validate ./plugins/flow && claude plugin validate .`
3. `plugins/flow/.claude-plugin/plugin.json` 的 `version` 加一（**不加，已安装的项目拿不到**），
   写 `plugins/flow/CHANGELOG.md`
4. 提交推送。各项目：`/plugin marketplace update cc-flow` → `/plugin update flow` → 开新 session
   看到漂移提示后 `/flow:init`

本地调试：`claude --plugin-dir ./plugins/flow`（不用安装，直接加载工作区代码）。

## 已知限制

- Bash 守卫按 shell 词法判断，解析失败一律放行（由 auto 模式分类器兜底）；变量展开出来的路径认不出
- `.claude/flow.json` 取自 session 启动目录：在 worktree 分支上改 flow.json，合并前不影响当前
  session 的 hook
- 插件 skill 必须带前缀调用（`/flow:triage`，不能 `/triage`）
