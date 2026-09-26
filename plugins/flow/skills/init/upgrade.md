# /flow:init 附录：升级与旧项目接入

## 1. 升级（已接入项目，托管区落后）

插件升级后 SessionStart 会提示托管区版本落后。EnterWorktree（`flow-upgrade`）后：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" --check "<工作目录>"   # 看差距
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" "<工作目录>"           # 覆盖托管区，项目补充不动
```

读 `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` 里旧版本之后的条目，挑出会改变日常行为的 1–3 条写进汇报。
提交 `docs(flow): sync managed workflow to v<版本>`、开 PR（纯文档，无需 review agent）。

## 2. 接入旧 workflow.md（「无标记」）

目标文件已存在但没有托管标记（手写的 workflow.md，或 conductor 自带模板）时脚本不动它：

1. 改名为 `<原名>.pre-flow.md`，重跑 seed，生成带托管区 + 项目补充骨架的新文件
2. 逐节对照旧文件：与托管区口径相同的丢弃；**本项目特有的**（敏感域、命令、设计源、失败基线、专属
   规则）迁进 P1–P6；与托管区口径**冲突的**列清单交用户拍板（workflow §0 停点 3），不自行取舍
3. 迁完删掉 `.pre-flow.md`，同一个 PR 提交

托管区本身不在项目里改（下次同步会被覆盖）：所有项目都适用的流程改进，到 flow 插件仓库改
`plugins/flow/templates/`、`plugin.json` 的 `version` 加一、写 CHANGELOG；各项目 `/plugin update flow`
后重跑 `/flow:init` 同步。
