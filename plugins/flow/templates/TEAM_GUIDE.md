# 团队开发指南（flow 工作流）

> 10 分钟上手。本文是**导览**，不是规则原文——规则的权威出处是 **`conductor/workflow.md`**
> （托管区 + 文末「项目补充」）。两边冲突时以 workflow.md 为准。

---

## 0. 装好工具

- clone 仓库后用 Claude Code 打开并**信任该目录**，会提示安装 `flow@cc-flow` 与
  `conductor@conductor-cc` 两个插件——都装上（插件仓库是私有的，本机 `gh auth login` 过即可）。
- 依赖：`jq`、`python3`、`gh`。缺 `jq` 时 flow 的 hook 全部失效（SessionStart 会提示）。
- 截图验收用 Playwright MCP（`/flow:visual-verify`）。

## 1. 一切从分诊开始

拿到任何需求，先跑 **`/flow:triage`**（或按 workflow §2 手工分诊）。分诊回答三件事：

**① 多重的流程？（档位，workflow §2.1）**

| | 一档 小明确 | 二档 中等 | 三档 高风险 |
|---|---|---|---|
| 判据 | 无敏感域 + ≤2 层 + schema 至多纯新增 + 一句话说得清 | 跨 ≥2 层或多 phase | 敏感域 / 改既有表列 / 改已上线口径 / 跨仓契约 / 视觉不确定 |
| 入口 | `/flow:spec` 或直接修 | `/conductor:new-track` | new-track（Lane A 先设计 → `/flow:design-track`） |
| session | 1 | 1（`/clear` 分隔） | 立项与实现**分 session** |
| review | PR 前 1 次 | spec 1 次 + 每个行为 phase 1 次 | spec 2 镜头 + plan + 每 phase 2 镜头 |

**文件数不作判据。** 敏感域与「层」的定义在 workflow.md 的 P1 / P2。

**② 哪条车道？（锚点形态，workflow §2.2）**

不确定性在「长什么样才对」→ **A**；在「怎么改才对」→ **B/C**；没有 → **D 直接修**。

> ⚠ **新页面 ≠ Lane A**。三条同时满足就降级走 Lane B（workflow §3.1）：只用既有 token 与既有
> 组件语法、无新交互模式、结构与文案能在 spec 里逐字给出。验收用 `/flow:visual-verify` 模式③。

**③ 拆不拆？（workflow §2.3）**

拆之前必须答一句：**「做完第一段，用户能亲手用到什么？」** 答不出、或答案里没有需求原话的主
入口 → **不拆**，一个 track 分 phase。决定拆 → **两段同时立项**（都进 tracks.md，后段描述行以
`⛔ blocked_by: <前一段>` 开头，由前一段的 `/flow:closeout` 删掉），第二段**免重走采访**。

第一段必须**端到端自洽**：从入口（含未登录访客）到目标动作走得通，不得把桥接件删到第二段。

---

## 2. 每条车道怎么跑

### Lane D — 小 bug（日常最多）

1. **先写复现测试**（Red）→ 修（Green）→ 全量回归。编译失败也算有效 Red。
2. **one-shot first**：先让 Claude 全自动试一把；连改两轮改不动就**重开会话重述问题**。
3. **升级判据**：跨 ≥2 层、涉 schema、或发现是类别性问题 → 升 Lane B 开 track。
4. 修完的教训：**代码类** hook（`.claude/flow.json`；硬禁止用 `permissions.deny`）→ skill →
   CLAUDE.md；**流程类**：通用的提到 flow 插件仓库，本项目的写进 workflow.md「项目补充」。

### 一档 — `/flow:spec` 一页规格直接做完

≤3 问访谈 → subagent 调研 → 一页 DELTA 规格（目标 / 现状→目标 / 明确不改 / AC 带可跑命令 /
做完用户能用到什么）→ TDD 实现 → PR 前 1 次 code review agent → 合并后回填 `已合并 PR #n`。

### Lane B — 功能调整

- 锚点是 **DELTA 规格**，重点写「明确不改清单」——review 和验收都拿它当边界。
- UI 微调：**动手前**先截现状当 baseline（事后补不了），验收 `/flow:visual-verify` 模式②。
- 新页面降级：spec 内嵌结构清单 + 逐字文案，验收模式③。

### Lane C — 重构

锚点是**不变量声明 + 测试基线**。覆盖薄的部位，plan 的 Phase 0 = 先补 characterization tests 把
现状钉死再动刀。验收 = 基线外全绿；涉 UI 时截图 diff 为零。

> ⚠ 这个 Phase 0 **要走 review gate**——它写的是测试代码，是重构唯一的安全网。别和
> 「存档失败基线」那种记账 Phase 0 混为一谈（workflow §5）。

### Lane A — 视觉不确定

```
① 设计    在自己的设计工具项目里画（claude-design 等）
② 拉回    当天拉回设计真相源目录（workflow.md P4）开 PR——没拉回来的改动等于没发生
③ 立项    /flow:design-track <feature>  ← 校验四件套，快照进 conductor/tracks/
          再 /conductor:new-track       ← INVENTORY 全部条目进验收标准
④ 实现    /conductor:implement，TDD 照常
⑤ 验收    每个行为 phase：review agent + /flow:visual-verify 模式①（needs_work 阻断）
⑥ 收尾    /flow:closeout；token/组件演化必须已在同一 PR 落回设计真相源
```

**四件套** = BRIEF / SPEC / INVENTORY / DECISIONS（+ tokens.css + 高保真稿）。缺一件
`/flow:design-track` 会拒绝立项。实现中发现功能与设计冲突：**停下列清单等拍板**，不得自行取舍。

---

## 3. 所有车道通用的纪律

- **停点只有 5 处**（workflow §0）：分诊卡 / 访谈 ≤3 问 / 拍板清单 / 立项终点 / 敏感域 PR merge。
  其余决策点一律开 review agent 代拍板，**不停下等人**。审计报回的 finding 直接修，不要拿回来问。
- **⚠ 敏感域**（workflow.md P1）：任何车道碰到都要 review agent 过目，且 **PR 由用户显式合并**。
- **主 checkout 只读**，永远停在 main。一切改动走 worktree（`EnterWorktree`），flow 的 hook 会拦下
  对 main 的编辑。
- **动手前 `git fetch`**，查有没有既有分支或已合并 PR 在做同一件事。
- **合并后立刻收尾**：跑 `/flow:closeout`（三连清理 + tracks.md `[x]` + `blocked_by` 后继确认）。
- **叠链 PR**：开始合并前先把后续 PR 全部 `gh pr edit --base main`——否则删 base 分支时 GitHub 会
  直接**关闭**叠在上面的 PR。
- **状态真相只看两处**：tracks.md 的 `[ ]/[~]/[x]` + plan.md 复选框。想做未立项的条目进
  `conductor/backlog.md`。
- commit 描述用英文（conventional commit）；记账提交用 `conductor(plan|track):` 前缀。
- 多个 worktree 同时起 dev server 会抢端口，手动错开。

---

## 4. Phase gate 怎么过

- **只有含行为变更的 phase 开 review agent**（`flow:phase-gate-reviewer`）。记账/登记 phase 用
  可执行清单自检；纯文档 / HANDOFF 并入相邻实现 phase 的同一次 review，不单开。
- review agent **只报正确性与 AC 缺口**；风格、记账格式不在范围内。**复核轮只针对未闭环的
  MAJOR**，MINOR 修完直接 PASS。
- verdict 以 `(review agent PASS)` 或 `(review agent FAIL→fix <sha>→PASS)` 留痕在 plan.md；报告存
  `phase<N>-verify/REPORT.md`。
- UI phase 追加 `/flow:visual-verify`（模式①/②/③）：**截图是 ground truth，DOM 测量只用于诊断**；
  连续 3 轮 needs_work → 停止微调，量化根因做一次决定性修改。needs_work 与 review FAIL 同级。
- **每个 gate 后按三行格式汇报**（workflow §3.3）：现在能用什么 / 还缺什么 / 需要你做什么。
  SHA、Rev、review 轮次只进 plan.md，**不进汇报正文**。

---

## 5. 记账要多轻

**任务勾 `[x]` 与代码同一提交**，phase 末一次回填 SHA + 一条 `conductor(plan):` 提交。
不做逐任务 `git notes`、逐任务单独记账提交，不设覆盖率阈值。验收锚点是「每条 AC 一条可跑的
检查」，不是覆盖率百分比。

---

## 6. 命令速查

| 命令 | 用途 | 什么时候 |
|---|---|---|
| `/flow:triage` | 分诊卡：档位 + 车道 + 拆分判断 + 「用户能用到什么」 | **任何新需求的第一步** |
| `/flow:spec` | 一档全流程：≤3 问 → 一页规格 → 实现 → PR | 小而明确的需求 |
| `/conductor:new-track` | 二/三档立项：spec + plan | 跨层 / 多 phase / 高风险 |
| `/conductor:implement` | 按 plan 执行 | 立项之后（三档要新 session） |
| `/flow:design-track` | 把设计四件套快照进 track | Lane A 立项 |
| `/flow:visual-verify` | 截图矩阵验收（①对设计稿 ②对现状 ③对 spec 清单） | UI phase gate |
| `/flow:closeout` | 合并后收尾三连 + 记账 + `blocked_by` 后继确认 | PR 合并后立刻 |
| `/flow:catchup` | `/clear` 或新 session 后恢复上下文 | 接着干之前的活 |
| `/flow:sync` | 把插件新版的托管区同步进本仓库 | SessionStart 提示版本落后时 |

---

## 7. 常见坑速查

| 坑 | 一句话 |
|---|---|
| 截图主题不对 | 页面默认跟系统偏好，**首张截图前必须显式设置主题** |
| Playwright 截图落错目录 | MCP server 的 cwd 是主 checkout 根目录，相对路径会落到那里，记得归位 |
| 全绿但有一个测试红 | 查 `baseline.md` / workflow.md P5 的失败基线——基线内的红是豁免项 |
| 纯前端页面也要先写测试？ | 展示型改动可豁免 RED-GREEN，换成 `/flow:visual-verify`（workflow §4.5） |
| 改了项目 hook 却不生效 | 项目 settings/hook 锚定 session 启动目录，worktree 分支上的新 hook 合并后才生效 |
| 在 main 上改文件被拦 | 设计如此：先 `EnterWorktree`；要改保护规则去 `.claude/flow.json` |
| workflow.md 托管区想改 | 别在项目里改——提到 flow 插件仓库发版，再 `/flow:sync` |

---

## 8. 新人 checklist

- [ ] 装好插件（§0），开一个新 session 确认开场提示「本仓库启用 flow 工作流」
- [ ] 读两份文档：本文 → `conductor/workflow.md`（重点看文末项目补充）
- [ ] 在 worktree 里跑通一次构建（命令见 workflow.md P3）
- [ ] 找一个 Lane D 小 bug 走一遍全流程（复现测试 → 修 → 回归 → PR → `/flow:closeout`）
- [ ] 拿一个真需求跑一次 `/flow:triage`，看它怎么判档
