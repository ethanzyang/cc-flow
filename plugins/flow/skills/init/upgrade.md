# /flow:init 附录：升级与旧项目接入

## 1. 升级（已接入项目，托管区落后）

插件升级后 SessionStart 会提示托管区版本落后。EnterWorktree（`flow-upgrade`）后：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" --check "<工作目录>"   # 看差距
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-managed.sh" "<工作目录>"           # 覆盖托管区，项目补充不动
```

读 `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` 里旧版本之后的条目，挑出会改变日常行为的 1–3 条写进汇报。
提交 `docs(flow): sync managed workflow to v<版本>`、开 PR、合并（纯文档，双向门，不审）。跨大版本时下面的结构调整
放在同一个 PR 里。

### 从 0.5 升级到 0.6（回到 conductor 底座）

0.6 重新以 conductor 为底座：二 / 三档用 `/conductor:new-track` + `/conductor:implement`，tracks.md 与 plan.md 恢复为
状态真相源；入口回到 `/flow:triage` / `/flow:spec`，审阅者回到 `flow:spec-reviewer` / `flow:phase-gate-reviewer`。
0.5 的小片上线、按后果分级、一个改动审一次、断路器都保留。

1. **重新启用 conductor**：`.claude/settings.json` 的 `enabledPlugins` 加 `"conductor@conductor-cc": true`，
   `extraKnownMarketplaces` 有 `conductor-cc`（`{"source": {"source": "git", "url": "https://github.com/pilotparpikhodjaev/conductor_cc.git"}}`）。
   auto 模式可能把改 `.claude/` 配置判为需要用户批准而拦下——拦下就把这两处改动原样给用户，请用户改或批准，不要换写法
   绕过。本机还没装的请用户 `/plugin install conductor@conductor-cc`。项目从没跑过 conductor setup（`status` 报
   `conductor=none`）→ 升级合并后按 `/flow:init` 的 D 路线补做产品定义。
2. **CLAUDE.md**：seed 会报「待替换」——用 `templates/CLAUDE.flow-section.md`（`{{MAIN}}` 换成主干名）替换 0.5 的工作流段
   与分支段（`/flow:shape`、`/flow:build`、定形卡、两类门、`pr-reviewer` / `risk-reviewer`、「停点只有三处」）。
   其余段落里指向 `/flow:shape` `/flow:build` 的地方改成 `/flow:triage` `/flow:spec` `/conductor:implement`。
3. **tracks.md 恢复为活的状态登记**：删掉 0.5 加的「存档 / 0.5 起不再登记新 track，状态看 GitHub PR」之类的说明；
   每节前置 `---`、状态标记只用 `[ ]` / `[~]` / `[x]`（hook 校验）。0.5 期间做完的工作不补登记（PR 历史就是记录）；
   还在做的多片需求，从下一片起按 0.6 开 track 并登记，spec 引用原来的 `docs/specs/<名>.md`，不重写。
4. **项目补充保持 0.5 的结构**：P1 单向门清单就是 0.6 三档的判据，P2 上线、P3 check 原样沿用；顺手核对 P1 的路径列到了
   真正做判定、写库的代码（不只是入口）。删掉 P4–P6 里引用定形卡、`/flow:shape`、`/flow:build`、`pr-reviewer`、
   `risk-reviewer` 的条目。
5. **项目自带的同名副本**：`.claude/skills/` 里与插件同名的（如 `catchup`，0.6 起插件自带 `/flow:catchup`）删掉，以插件为准。
6. **memory**：用户 memory 里写着「不用 conductor」「用 /flow:shape / /flow:build」「状态看 GitHub、不登记 track」的条目，
   改成指向 workflow.md 的指针或删掉——流程以 workflow.md 为准。

### 从 0.4 升级到 0.6（按后果分级、一片一上线）

0.4 的 conductor 底座、分诊、tracks.md 都还在；变的是档位判据、plan 的切法、审阅次数与记账。

1. **项目补充改结构**（托管区不会动它）：
   - P1「敏感域」→「单向门清单」：按后果重写（错了 revert 重发也收不回来的），每条「后果 — 典型路径」；原敏感域路径
     保留为典型路径，并补上清单外但同样会动钱 / 改记账口径的代码——worker 里的后台任务与计划执行、core 里做判定的
     纯函数、写账的 repo / service、对账。
   - P2「层划分」→「上线」：部署命令、谁来跑、冒烟检查、回滚；三档涉及资金的 testnet / dry-run 怎么跑。层划分整段删掉
     （0.6 不按层数分档）。
   - P3 命令里补一条 **check** 命令（一条跑完 typecheck / lint / test）。
   - P4–P6 保留项目特有的规则，删掉其中的流程条目：冻结 RED、每 phase 的 phase gate 验收、`baseline.md`、phase 报告 /
     REPORT / HANDOFF、SHA 回填与 git notes、截图矩阵作为必过关卡。
2. **CLAUDE.md**：旧的工作流段里也有 `/flow:triage`，seed **不会**报「待替换」——手工比对：讲「无敏感域 + ≤2 层」、
   「停点只有 5 处」、拍板清单、立项终点的整段，用 `templates/CLAUDE.flow-section.md`（`{{MAIN}}` 换成主干名）替换
   工作流段与分支段；「敏感域」段改成「单向门」口径（`.claude/rules/` 与 domain-traps 里的路径提醒可以保留）。
3. **进行中的 track**：已完成的 phase 不动；剩下的 phase 按 workflow §3.1 重排成能单独上线的竖切片（按层切的合并），
   plan.md 里未勾的 SHA 回填、记账、phase 报告类任务删掉。
4. **项目自带的旧流程副本**：`.claude/skills/` 里与 flow 同名或同义的（triage、spec、closeout、visual-verify、catchup）、
   `.claude/agents/` 里的 spec-reviewer / phase-gate-reviewer / architecture-reviewer / security-reviewer 删掉，以插件为
   唯一来源；项目自己的 domain-traps 等保留。项目自带的 hook 与 flow 的 hook 重复的（主 checkout 只读、保护路径、
   Bash 守卫、worktree 软链、未收尾提醒、tracks.md 校验）从 `.claude/settings.json` 移除，改由 `.claude/flow.json` 配置；
   保存即格式化之类写进 `format_on_edit`；测试库口径写进 `bash_guard.test_db_pattern`。
5. **memory**：用户 memory 里如果有流程规则正文（例如「每段都审」「spec 审到 PASS」「先开立项 PR」），改成指向
   workflow.md 的指针或删掉。

## 2. 接入旧 workflow.md（「无标记」）

目标文件已存在但没有托管标记（手写的 workflow.md，或 conductor 自带模板）时脚本不动它：

1. 改名为 `<原名>.pre-flow.md`，重跑 seed，生成带托管区 + 项目补充骨架的新文件
2. 逐节对照旧文件：与托管区口径相同的丢弃；**本项目特有的**（单向门、上线、命令、设计源、失败基线、专属规则）
   迁进 P1–P6；与托管区口径冲突、又会改变产品行为的，列清单交用户拍板，不自行取舍
3. 迁完删掉 `.pre-flow.md`，同一个 PR 提交

托管区本身不在项目里改（下次同步会被覆盖）：所有项目都适用的流程改进，到 flow 插件仓库改
`plugins/flow/templates/`、`plugin.json` 的 `version` 加一、写 CHANGELOG；各项目 `/plugin update flow`
后重跑 `/flow:init` 同步。
