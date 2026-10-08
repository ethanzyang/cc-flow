# /flow:init 附录：升级与旧项目接入

## 1. 升级（已接入项目，托管区落后）

EnterWorktree（`flow-upgrade`）后：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" --check "<工作目录>"   # 看差距
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" "<工作目录>"           # 覆盖托管区，项目补充不动
```

读 `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` 里旧版本之后的条目，挑出会改变日常行为的 1–3 条写进汇报。
提交 `docs(flow): sync managed workflow to v<版本>`、开 PR、合并（纯文档，双向门）。

### 从 0.4 及以前升级到 0.5（流程大改）

托管区同步之后，同一个 PR 里还要做：

1. **项目补充改结构**（托管区不会动它）：
   - P1「敏感域」→「单向门清单」：按后果重写（错了 revert 也收不回来的），原敏感域路径保留为典型路径；顺手补上
     清单外但同样会动钱 / 改记账口径的代码（后台任务、对账、计划执行等）。
   - P2「层划分」→「上线」：部署命令、谁来跑、冒烟检查、回滚。层划分整段删掉（0.5 不按层分级）。
   - P3 命令里补一条 **check** 命令（一条跑完 typecheck / lint / test）。
   - 其余（P4–P6）保留，删掉其中关于 track、phase gate、冻结 RED、截图矩阵的流程条目。
2. **CLAUDE.md**：用 `templates/CLAUDE.flow-section.md` 替换旧的工作流段与分支段（分诊、三档、停点 5 处、
   拆分守则、`blocked_by`）；「敏感域」段改成「单向门」口径；指向 `/flow:triage` `/flow:spec` 的地方改成
   `/flow:shape` `/flow:build`。
3. **项目里自带的旧流程副本**：`.claude/skills/` 里与 flow 同名或同义的（triage、spec、closeout、visual-verify、
   catchup）、`.claude/agents/` 里的 spec-reviewer / phase-gate-reviewer / architecture-reviewer / security-reviewer
   删掉，以插件为唯一来源；项目自己的 domain-traps 等保留。项目自带的 hook 与 flow 的 hook 重复的（主 checkout
   只读、保护路径、Bash 守卫、worktree 软链、未收尾提醒、tracks.md 校验）从 `.claude/settings.json` 移除，改由
   `.claude/flow.json` 配置；保存即格式化之类写进 `format_on_edit`。
4. **conductor 留下的文件**：`conductor/tracks/`、`tracks.md`、`backlog.md` 作为历史存档保留，`tracks.md` 顶部加一句
   「0.5 起不再登记新 track，状态看 GitHub PR」；`settings.json` 里的 `conductor@conductor-cc` 可以关掉。
5. **memory**：用户的 memory 里如果有流程规则正文（例如「每段都审」「用 /conductor:implement」），改成指向
   workflow.md 的指针或删掉——流程以 workflow.md 为准。

## 2. 接入旧 workflow.md（「无标记」）

目标文件已存在但没有托管标记（手写的 workflow.md）时脚本不动它：

1. 改名为 `<原名>.pre-flow.md`，重跑 seed，生成带托管区 + 项目补充骨架的新文件
2. 逐节对照旧文件：与托管区口径相同的丢弃；**本项目特有的**（单向门、上线、命令、设计源、失败基线、专属规则）
   迁进 P1–P6；与托管区口径冲突、又会改变产品行为的，列清单交用户拍板
3. 迁完删掉 `.pre-flow.md`，同一个 PR 提交

托管区本身不在项目里改（下次同步会被覆盖）：所有项目都适用的流程改进，到 flow 插件仓库改
`plugins/flow/templates/`、`plugin.json` 的 `version` 加一、写 CHANGELOG；各项目 `/plugin update flow`
后重跑 `/flow:init` 同步。
