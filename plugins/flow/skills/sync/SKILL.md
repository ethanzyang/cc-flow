---
name: sync
description: 把 flow 插件新版本的托管规则同步进本仓库（conductor/workflow.md 托管区 + dev-docs/TEAM_GUIDE.md）。当 SessionStart 提示托管区版本落后、用户说「同步 flow」「flow sync」「更新工作流」时触发。也用于把一个没有托管标记的旧 workflow.md 接入 flow。
---

托管区 = 两行 `flow:managed` 标记之间的内容，由插件下发、整段覆盖；标记之外（workflow.md 文末
「项目补充」）一字不动。同步脚本：`${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh`。

## 1. 先看差距

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" --check "$(git rev-parse --show-toplevel)"
```

每个托管文件一行：`最新` / `需同步 vA → vB` / `缺失` / `无标记`。全是「最新」→ 告诉用户无需同步，结束。

版本之间改了什么：读 `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` 里 vA 之后的条目，挑出**会改变日常
行为**的几条（新停点、判档口径变化、新 hook 拦截），准备在汇报里讲。

## 2. 进 worktree 再同步

同步是一次普通的仓库改动：走 worktree + PR（主 checkout 只读；脚本在已接入项目的主干上会拒绝执行）。

```bash
git fetch -q origin
# EnterWorktree，或：git worktree add -b chore/flow-sync-<版本> .claude/worktrees/flow-sync origin/<main>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" "<worktree 路径>"
git -C "<worktree 路径>" diff --stat
```

提交 `docs(flow): sync managed workflow to v<版本>`，开 PR。纯文档改动，无需 review agent。

## 3. 「无标记」的处理（旧项目第一次接入）

目标文件已存在但没有托管标记（例如早先手写的 `conductor/workflow.md`）时脚本不会动它。接入步骤：

1. 把旧文件改名为 `<原名>.pre-flow.md`（保留，供对照）
2. 重跑同步脚本 → 生成带托管区 + 项目补充骨架的新文件
3. 逐节对照旧文件：**与托管区口径相同的**丢弃；**本项目特有的**（敏感域清单、命令、设计源、
   失败基线、项目专属规则）迁进新文件的 P1–P6；**与托管区口径冲突的** → 列清单交用户拍板
   （workflow §0 停点 3），不要自行取舍
4. 迁完删掉 `.pre-flow.md`，同一个 PR 提交

## 4. 在项目里发现托管区该改

别在项目里改托管区（下次同步会被覆盖）。流程类改进如果**所有项目都适用**：到 flow 插件仓库
（github.com/ethanzyang/cc-flow）改 `plugins/flow/templates/`，`plugin.json` 的 `version` 加一，
写 CHANGELOG，推上去；各项目 `/plugin marketplace update cc-flow` → `/plugin update flow` →
`/flow:sync`。**只属于本项目**的 → 写进 workflow.md「项目补充」。

## 汇报

```
现在能用什么：workflow.md 托管区已从 vA 同步到 vB（PR #n）；变化要点：<1–3 条>
还缺什么：<无 / 冲突待拍板>
需要你做什么：合并 PR
```
