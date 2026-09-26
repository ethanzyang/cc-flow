# cc-flow

分诊驱动的 Claude Code 开发工作流，做成插件，新项目 3 步接入。从 token-router 的 workflow v2.1 抽离。

目标：**人专注立项**——立项做对了，实现按 plan 自己跑，设计系统串在同一条线上。

```
新需求 → /flow:triage ─┬─ 一档 → /flow:spec（一页规格，一个 session 做完）
                       ├─ 二/三档 → /conductor:new-track → spec review → 立项终点
                       └─ Lane A（视觉未定）→ /flow:design-track（拉设计包 → new-track → spec review）
       立项之后 → /conductor:implement（phase gate：review agent + /flow:visual-verify）→ PR → /flow:closeout
```

机制：**按风险三档决定流程重量**、**停点只有 5 处**（其余由 review agent 代拍板）、**主 checkout
只读 + worktree**、**合并即收尾**、**犯错就沉淀成规则**（hook > rules / skill > CLAUDE.md）。规则正文见
[`plugins/flow/templates/workflow.md`](plugins/flow/templates/workflow.md)。

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
| `CLAUDE.md` | 按原则写的高频规则（≤约 100 行）+ 工作流段 + 分支纪律；已存在的插入工作流段，过长则把按路径 / 按领域的规则分流出去 |
| `.claude/rules/*.md` | 按文件类型的规则（frontmatter `paths:`，读到匹配文件才加载）；只为既有约定建 |
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
| `/flow:triage` | 分诊卡：档位 + 车道 + 拆分判断 + 「做完用户能用到什么」，把需求送进对的立项入口 |
| `/flow:spec` | 一档全流程：≤3 问 → 一页 DELTA 规格 → TDD → review → PR |
| `/flow:design-track` | Lane A 立项一条龙：从 Claude Design 拉设计包 → 快照 → new-track → spec review |
| `/flow:visual-verify` | 截图矩阵验收（对设计稿 / 对现状 / 对 spec 清单） |
| `/flow:closeout` | 合并后收尾三连 + 记账 |
| `/flow:design push` / `pull` | 仓库设计系统 ⇄ 自己的 Claude Design 副本；仅手动调用 |
| `/flow:init` | 接入新项目；已接入时：插件升级后同步托管区、补设计模块 |

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
  `/flow:design push` 建自己的云端副本；改了已有设计文件当天 `/flow:design pull` 拉回开 PR
- Lane A：在云端按 feature 文件夹画完 → `/flow:design-track <feature>`（设计包 + spec/plan 同一个立项 PR）
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
  "sensitive_paths": ["*/billing/*", "*/payment/*"], // 改到时往模型上下文注入一次「三档 + 用户合并」提醒
  "format_on_edit": [                               // 在被改文件所属仓库根执行，路径在 $FILE
    { "globs": ["*.go"], "cmd": "gofmt -w \"$FILE\"" },
    { "globs": ["*.ts", "*.tsx"], "cmd": "cd web && bunx prettier --write \"$FILE\"" }
  ],
  "json_dup_key_check": [                           // JSON 合法 + 同一对象内不许新增重复键
    { "glob": "*/web/src/i18n/locales/*.json", "known": ["历史遗留的重复键"] }
  ],
  "design": { "dir": "design-system" }              // 设计模块；有它 /flow:init 才管 SYNC.md
}
```

glob 用 shell `case` 语义，`*` 可以跨 `/`，所以开头写 `*/` 就能匹配任意深度。体检：
`bash plugins/flow/scripts/doctor.sh <项目目录>`。

## 托管区与升级

`conductor/workflow.md` 里夹在 `<!-- flow:managed:begin vX -->` 和 `<!-- flow:managed:end -->`
之间的内容由插件下发，`/flow:init` 整段覆盖；标记之外（文末项目补充）一字不动。

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
   看到漂移提示后 `/flow:init`

本地调试：`claude --plugin-dir ./plugins/flow`（不用安装，直接加载工作区代码）。

## 已知限制

- Bash 守卫是子串匹配：命令文本里仅仅**提到**保护路径且带 `>` 也会被拦（改用 Write/Edit 即可）；
  `cp`/`mv` 落到保护路径不拦
- `.claude/flow.json` 取自 session 启动目录：在 worktree 分支上改 flow.json，合并前不影响当前
  session 的 hook
- 插件 skill 必须带前缀调用（`/flow:triage`，不能 `/triage`）
