---
name: build
description: 实现一片（workflow §3.3–§3.5）：worktree → 测试先行实现 → check 全绿 → 独立审阅一轮 → 开 PR → 双向门合并上线 / 单向门交用户合并。定形卡确认后用；用户说「做」「开始」「实现」时触发。
---

输入：定形卡里的**一片**（单向门另有 `docs/specs/<名>.md`，且已过 `flow:risk-reviewer`）。一次只做一片。

先读 `conductor/workflow.md` §3–§4 与文末 **P1 / P2 / P3 / P5**。

## 1. 开工

- `git fetch -q`，查有没有既有分支或已合并 PR 在做同一件事。
- EnterWorktree（或 `git worktree add -b <type>/<slug> .claude/worktrees/<slug> origin/<主干>`）。
- 大片（预计超过一个上下文能装下的）或单向门：派一个新的 agent 来做本 skill 的第 2–4 步，只给它定形卡
  （+ spec）与本 skill 的路径；主会话只收结论。小片直接在当前会话做。

## 2. 实现

- 计算、判定、状态流转、账务、鉴权、数据读写：先写失败测试（编译失败也算有效的红），再实现到绿。
  纯展示改动不强制测试先行。
- 外部系统的 fixture 从真实响应录制（只读 key / testnet），不手写推测的格式和错误码。
- 单向门：核心不变量的测试由另一个 agent 先写好提交；实现时不改它们的既有断言，确需改的记下理由写进 PR 描述。
- 只做这一片。冒出来的新范围记进 PR 的「已知未做」，不顺手做。
- 每完成一步就提交（conventional commit，英文描述）并推送，断线不丢活。

## 3. 检查

- 跑 P3 的 check 命令到全绿。与本次改动无关的失败：在主干上复跑，确认是既有失败（或在 P5 里）后写进 PR 描述。
- 改了 UI：起 dev server，截一张关键状态的截图作为证据（不做截图矩阵，除非用户要求 `/flow:visual-verify`）。

## 4. 审阅（一轮）

- 开 PR（或先推分支），描述按下面的模板写。
- 派 `flow:pr-reviewer`（单向门同时派 `flow:security-reviewer`，并行），把 PR 号与定形卡给它；让它把报告
  写进 scratch 文件或直接返回，**不要层层转交**。
- 只修 BLOCKER；「建议」自己判断，大多不修，写进 PR 评论即可。修完请审阅者只复核 BLOCKER。
- 把审阅 verdict 贴成 PR 评论（一行 verdict + BLOCKER 清单及处理）。
- 两轮后仍有 BLOCKER → 断路器（workflow §3.6）：停下，带选项找用户。

## 5. 合并与上线

- **双向门**：无 BLOCKER → `gh pr merge <n> --squash --match-head-commit <审过的 sha>` → `/flow:closeout`
  （部署、冒烟、清理、请用户试）。
- **单向门**：停在「PR 可合并」，通知用户合并（workflow §5 停点 2）；用户合并后 `/flow:closeout`。
- 由 agent 执行本 skill 时：agent 做到「PR 已审、可合并」并回报；合并与上线由主会话做。

## PR 描述模板

```
## 定形卡
<原样贴>

## 做了什么
- …

## 怎么试
<上线后在哪里点、看到什么>

## check
<命令与结果摘要；既有失败及在主干上的复跑结论>

## 审阅
<VERDICT 与 BLOCKER 处理>

## 已知未做
- …
```

## 汇报（给用户，用用户的语言）

现在能用什么 / 还没做什么 / 需要你做什么（双向门通常是「上线后去 <哪里> 试一下」）。
