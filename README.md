# cc-flow

分诊驱动的 Claude Code 开发工作流，做成插件，新项目 3 步接入。从 token-router 的 workflow v2.1 抽离。

核心机制：**按风险三档决定流程重量**（一档一页规格直接做 / 二档开 track / 三档全套 + 立项实现分
session）、**停点只有 5 处**（其余由 review agent 代拍板）、**主 checkout 只读 + worktree**、
**合并即收尾**。规则正文见 [`plugins/flow/templates/workflow.md`](plugins/flow/templates/workflow.md)。

## 新项目接入

```text
/plugin marketplace add ethanzyang/cc-flow
/plugin install flow@cc-flow
/flow:init
```

`/flow:init` 负责编排：先放 flow 的规则 → 完整跑 `/conductor:setup` 的产品定义访谈（产品、产品规范、技术栈、代码规范、首个 track）→ 问敏感域、补 flow 那层 → 最后激活 hook。已有提交的仓库在 `chore/adopt-flow` worktree 里做。产出：

| 文件 | 内容 |
|---|---|
| `conductor/workflow.md` | 规则正文：**托管区**（插件下发）+ 文末**项目补充 P1–P6**（本项目自己的） |
| `dev-docs/TEAM_GUIDE.md` | 10 分钟上手导览（托管） |
| `conductor/{product,product-guidelines,tech-stack}.md`、`code_styleguides/`、首个 track | conductor setup 访谈产出 |
| `conductor/backlog.md` | 未立项待办池 |
| `CLAUDE.md` | 工作流段 + 分支纪律（已存在则只插入这一段） |
| `.claude/flow.json` | hook 配置：保护路径、敏感路径、格式化命令等 |
| `.claude/settings.json` | 合并：插件自动安装（flow + conductor）+ 权限基线 |

合并 PR 后，队友 clone 仓库、信任目录，就会被提示安装 `flow@cc-flow` 与 `conductor@conductor-cc`。
私有仓库靠本机 git 凭据（`gh auth login` 过即可）。

依赖：`jq`（必需，hook 全靠它）、`python3`（JSON 重复键检查）、`gh`（PR 操作）、Playwright MCP
（截图验收）、[conductor](https://github.com/pilotparpikhodjaev/conductor_cc) 插件（二/三档的
`new-track` / `implement`）。

## 包含什么

**Skills**（调用时带前缀 `flow:`）

| 命令 | 用途 |
|---|---|
| `/flow:init` | 接入新项目 |
| `/flow:sync` | 插件升级后把托管区同步进项目；也用于接入手写过 workflow.md 的旧项目 |
| `/flow:triage` | 分诊卡：档位 + 车道 + 拆分判断 + 「做完用户能用到什么」 |
| `/flow:spec` | 一档全流程：≤3 问 → 一页 DELTA 规格 → TDD → review → PR |
| `/flow:closeout` | 合并后收尾三连 + 记账 |
| `/flow:catchup` | `/clear` 后恢复上下文 |
| `/flow:visual-verify` | 截图矩阵验收（对设计稿 / 对现状 / 对 spec 清单） |
| `/flow:design-track` | 设计四件套快照进 track |
| `/flow:design-push` | 设计系统目录 → 自己的 Claude Design 副本（首次选/建项目）；仅手动调用 |
| `/flow:design-pull` | Claude Design 改动 → 设计系统目录并开 PR；仅手动调用 |

**Agents**：`flow:spec-reviewer`（立项审阅）、`flow:phase-gate-reviewer`（phase 验收）、
`flow:architecture-reviewer`、`flow:security-reviewer`。

**Hooks**（只对有 `.claude/flow.json` 的仓库生效，插件装在用户级也不影响别的仓库）

| 事件 | 做什么 |
|---|---|
| SessionStart | 注入「本仓库走 flow」上下文；托管区版本漂移提示；未收尾提醒；worktree 软链 .env |
| PreToolUse Edit/Write | 主 checkout 只读；design 快照只读；`protected_paths`；`no_full_rewrite` |
| PreToolUse Bash | 危险命令（rm -rf 高危目标 / DROP / force push / reset --hard）；Bash 写保护文件 |
| PostToolUse Edit/Write | `format_on_edit`；tracks.md 不变量；JSON 重复键；敏感域提醒 |
| CwdChanged | 进 worktree 时软链 `worktree_links` |
| Stop | 主 checkout 被写 / 已合并未删的 worktree |

## 设计模块（可选）

有 UI 的项目在 `/flow:init` 时选「要」即启用（已接入的项目重跑 `/flow:init` 补）：

- `design-system/` 是设计唯一真相源，协作规范 `design-system/SYNC.md`（托管区 + 项目补充 D1–D3）
- Claude Design 的设计系统项目是账号私有的，所以用 git 合流：每人 `/design-login` 后
  `/flow:design-push` 建自己的云端副本；在云端改完当天 `/flow:design-pull` 拉回开 PR
- Lane A：`/flow:design-pull <feature>` → `/flow:design-track <feature>` → `/conductor:new-track`
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
  "sensitive_paths": ["*/billing/*", "*/payment/*"], // 改到时往模型上下文注入一次「三档 + 用户合并」提醒
  "format_on_edit": [                               // 在被改文件所属仓库根执行，路径在 $FILE
    { "globs": ["*.go"], "cmd": "gofmt -w \"$FILE\"" },
    { "globs": ["*.ts", "*.tsx"], "cmd": "cd web && bunx prettier --write \"$FILE\"" }
  ],
  "json_dup_key_check": [                           // JSON 合法 + 同一对象内不许新增重复键
    { "glob": "*/web/src/i18n/locales/*.json", "known": ["历史遗留的重复键"] }
  ],
  "design": { "dir": "design-system" }              // 设计模块；有它 /flow:sync 才管 SYNC.md
}
```

glob 用 shell `case` 语义，`*` 可以跨 `/`，所以开头写 `*/` 就能匹配任意深度。体检：
`bash plugins/flow/scripts/doctor.sh <项目目录>`。

## 托管区与升级

`conductor/workflow.md` 里夹在 `<!-- flow:managed:begin vX -->` 和 `<!-- flow:managed:end -->`
之间的内容由插件下发，`/flow:sync` 整段覆盖；标记之外（文末项目补充）一字不动。

- 在某个项目里发现**所有项目都适用**的流程问题 → 改本仓库 `plugins/flow/templates/`，发版
- **只属于那个项目**的 → 写进它的 workflow.md 项目补充

为什么不让规则只活在插件里：conductor 插件的 `new-track` / `implement` 硬读项目里的
`conductor/workflow.md`，所以规则正文必须落在项目里；托管区 + 版本号 + SessionStart 漂移提示是
「一处维护、各项目同步」的折中。

## 发版

1. 改 `plugins/flow/`；跑 `bash tests/lint.sh && bash tests/hooks.test.sh`（全绿）
2. `claude plugin validate ./plugins/flow && claude plugin validate .`
3. `plugins/flow/.claude-plugin/plugin.json` 的 `version` 加一（**不加，已安装的项目拿不到**），
   写 `plugins/flow/CHANGELOG.md`
4. 提交推送。各项目：`/plugin marketplace update cc-flow` → `/plugin update flow` → 开新 session
   看到漂移提示后 `/flow:sync`

本地调试：`claude --plugin-dir ./plugins/flow`（不用安装，直接加载工作区代码）。

## 已知限制

- Bash 守卫是子串匹配：命令文本里仅仅**提到**保护路径且带 `>` 也会被拦（改用 Write/Edit 即可）；
  `cp`/`mv` 落到保护路径不拦
- `.claude/flow.json` 取自 session 启动目录：在 worktree 分支上改 flow.json，合并前不影响当前
  session 的 hook
- 插件 skill 必须带前缀调用（`/flow:triage`，不能 `/triage`）
