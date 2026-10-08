---
name: catchup
description: 恢复上下文——在 /clear 之后、新 session 开始、或上下文吃紧换会话时，找回「做到哪一片、下一步做什么」（conductor/workflow.md §3.3）。用户说「恢复上下文」「继续之前的工作」「做到哪了」「catchup」时触发。
---

只读：不改文件、不提交、不开分支。主干名取 `.claude/flow.json` 的 `main_branch`（缺省 `main`），下文写作 `<main>`。

## 步骤

1. **分支与提交**：`git branch --show-current`、`git status --short`、`git log --oneline -20`；`git worktree list`
   看还有哪些进行中的 worktree。在主 checkout（停在 `<main>`）上 → 下面按 tracks.md 找进行中的工作，提示去对应 worktree。
2. **所属 track**：读 `conductor/tracks.md` 的 `[~]` 条目（描述行以 `⛔ blocked_by` 开头的是还没轮到的后段）；按分支名或
   最近提交对上是哪个 track。
3. **进度**（track）：读 `conductor/tracks/<track>/plan.md`——它是进度真相源。定位最后一个 `[~]` 或第一个 `[ ]` 任务，
   说出它在第几个 phase（= 第几片）、这一片的目标；前面的片看 meta-task 是否 `[x]`（已交付）。三档再看 spec 里有没有
   先行测试（§4.5）、本片是不是单向门片。
4. **一档**：没有 track 的，找 `docs/specs/` 里状态行为 `进行中` 或 `PR #n` 的规格（`git log` 最近改过的优先）。
   都没有 → 属一次性任务（D 车道小 bug、纯文案）。
5. **变更面**：`git fetch -q` 后 `git diff --stat origin/<main>...HEAD`，加上未提交的改动。
6. **PR**：`gh pr list --head <分支> --state all --json number,state,title,url`；有 open PR 就看
   `gh pr view <n> --json reviewDecision,statusCheckRollup,comments` 里有没有 `VERDICT:` 评论、check 是否通过。
   已合并却还在的 worktree → 下一步是 `/flow:closeout`。

## 输出

先用用户的三行（workflow §1），再给下一步：

```
现在能用什么：<已上线的片，按需求原话对号；没有写「还没有」>
还缺什么：<当前片还差的 + 后面的片 / 无>
需要你做什么：<合并 PR #n ｜ 去哪里试 ｜ 无>

下一步：<1–3 条，具体到命令或任务，如「继续 plan.md 第 2 片的任务『…』，先跑 check 记基线」「PR #n 已合并 → /flow:closeout」>
```

三行里不讲 phase 编号、SHA、审阅轮次（workflow §1）；接着做要用的定位信息放在最后一行：
「分支 <名> ｜ track <id> 第 N 片 ｜ 未提交 <n> 个文件」。
