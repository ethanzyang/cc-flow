---
name: init
description: 把 flow 开发工作流接入当前仓库：放规则（conductor/workflow.md 托管区 + 项目补充）→ 填项目补充（单向门、上线、命令）与 CLAUDE.md → 最后激活 hook。用户说「接入 flow」「初始化工作流」「flow init」、或在还没有 .claude/flow.json 的仓库里想用 /flow:* 时触发；也用于插件升级后同步托管区（含从 0.4 及以前升级）、给已接入项目补设计模块。
---

确定性步骤交给脚本 `${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh`（`status` / `seed` / `design` / `finish`），
你负责填写项目特有的内容。接入本身是双向门：一个 PR，doctor 通过即可合并。

## 0. 摸底（写任何文件之前）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" status "$(pwd)"
```

没有 `jq` → 停下请用户安装（flow 的 hook 全靠它）。按输出选路线：

| status | 路线 |
|---|---|
| `flow=none` | **A 接入** |
| `flow=adopted`，`workflow=managed:v<旧>` | **U 升级**：读 `upgrade.md` 照做 |
| `flow=adopted`，托管区最新 | 跑 `doctor.sh` 汇报；用户要补设计模块 → **E 路线**；否则结束 |

**E 补设计模块**：EnterWorktree（`design-module`）→ 第 3 步的「设计模块」小节 → `doctor.sh` → 提交
`chore: add flow design module`、开 PR。

## 1. 工作区

- `git=none` → 问用户是否 `git init -b main`（唯一的前置问题），然后就地做。
- `git=unborn` → 就地做。
- `git=commits` → `git fetch -q`（有远端时）后 **EnterWorktree**（`adopt-flow`）。

## 2. 放规则（seed）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" seed "<工作目录>" --main <主干>
```

生成 `conductor/workflow.md`（托管区 + 项目补充骨架；路径是历史沿用）与 `dev-docs/TEAM_GUIDE.md`；
`CLAUDE.md` 不存在时从模板生成；合并 `.claude/settings.json`（插件自动安装 + 权限基线）；补 `.gitignore`。
**不写** `.claude/flow.json`。输出里「无标记」→ 按 `upgrade.md` 第 2 节迁移后重跑；「待插入 / 待替换」→ 第 3 步处理。

## 3. 填项目特有的内容

先摸清项目：greenfield 问用户 3 个问题以内（做什么、给谁用、技术栈有没有定），写进 CLAUDE.md 的定位行；
brownfield 派一个 Explore subagent 返回：构建 / 测试 / lint / 格式化 / dev 命令、部署方式、会动钱或不可逆的
代码路径（给 glob）、UI 与主题切换方式、既有约定（AGENTS.md / .cursorrules / CONTRIBUTING）。

**问用户（一次 AskUserQuestion，没有歧义的不问）**：

1. **单向门**：列候选（「错了 revert 也收不回来」的：动钱、记账口径、密钥权限、数据迁移、审批守卫、对外不可撤回），
   并给「无」选项。措辞如实：「这些改动走更重的路径（spec + 写代码前风险审阅 + 终审加安全审阅），PR 由你合并」。
2. **上线**：合并后怎么部署、模型能不能自己跑部署命令、冒烟看什么（没有部署环境就选「无」）。
3. **设计系统**（有 UI 时才问）：要不要用 Claude Design 管设计系统（建 `design-system/`，之后 `/flow:design push|pull`）。

**填写（用 Edit；此时 hook 尚未激活）**：

- `conductor/workflow.md` 文末：P1 单向门清单（后果 — 路径；「无」就写无）、P2 上线（部署命令、谁跑、冒烟、
  回滚）、P3 命令块（**一条 check 命令**跑完 typecheck / lint / test）、P4 UI（无 UI 写「无 UI」）、P5 失败基线
  （主干上跑一遍 check 记下已知失败；全绿写「无」）、P6 项目规则。不留（待填）。
- **CLAUDE.md**——每个 session 常驻，只写「不写 Claude 就会做错」的：
  - 碰某类文件才相关 → `.claude/rules/<名>.md`（frontmatter 用 **`paths:`**；写成 `globs:` 会被当成无条件规则）；
    高危领域的陷阱全文 → `.claude/skills/domain-traps/SKILL.md`，CLAUDE.md 每域只留 ≤3 行 + 指针；流程 → workflow.md；
    能机械强制的 → `flow.json` / `permissions.deny`。目标 ≤100 行。
  - 新生成的：填实 `{{NAME}}` 等占位符，**不编造**规则。
  - 已存在的：「待插入」→ 把 `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.flow-section.md`（`{{MAIN}}` 换成主干名）插到
    命令段之后；「待替换」→ 用它替换旧的工作流段与分支段（旧段讲分诊 / 三档 / 停点 5 处的内容整段删掉）。
- **设计模块**（选了「要」，或 E 路线）：
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" design "<工作目录>" [--dir design-system]
  ```
  然后填 `SYNC.md` 文末 D1–D3、workflow.md P4，CLAUDE.md 插入 `templates/CLAUDE.design-section.md`。
- **hook 规则**写进 scratch 目录下的 `flow-rules.json`（**不要**写进仓库），只放非空字段：
  ```json
  {
    "sensitive_paths": ["*/billing/*"],
    "protected_paths": [{ "glob": "*/generated/*", "reason": "生成文件，改源再生成。" }],
    "no_full_rewrite": [{ "glob": "*/locales/*.json", "reason": "有重复键。" }],
    "json_dup_key_check": [{ "glob": "*/locales/*.json", "known": ["已存在的重复键"] }],
    "format_on_edit": [{ "globs": ["*.go"], "cmd": "gofmt -w \"$FILE\"" }],
    "worktree_links": [".env"],
    "bash_guard": { "test_db_pattern": "(^|_)test(_|$)" }
  }
  ```
  glob 用 shell `case` 语义（`*` 可跨目录）；`format_on_edit.cmd` 在被改文件所属仓库根执行，路径在 `$FILE`；
  数组字段会与模板默认项（.env、CI 保护）合并。`sensitive_paths` 只是提醒，单向门的判据是后果。

## 4. 激活并体检

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" finish "<工作目录>" --rules "<scratch>/flow-rules.json"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" "<工作目录>"
```

`finish` 最后写 `.claude/flow.json`——它一出现 flow 的 hook 就生效；就地接入的项目此后主干上的 Edit 会被拦。
所以**所有填写必须在 finish 之前做完**。doctor 必须「结论：通过」；△ 项能处理的处理掉，处理不了的写进汇报。

## 5. 提交与交付

- 提交 `chore: adopt flow workflow`。
- worktree 且有 `origin` + `gh` → 推分支、开 PR（描述列出生成 / 修改的文件与 doctor 输出），合并。没有远端 →
  主 checkout `git merge --ff-only <分支>` 后删 worktree。就地接入 → 提交即完成。

## 汇报

```
现在能用什么：本仓库已接入 flow——新需求 /flow:shape，说「做」后 /flow:build，合并后 /flow:closeout
还缺什么：<doctor 的 △ 项 / 无>
需要你做什么：<无 ｜ 部署方式待你确认>
```
