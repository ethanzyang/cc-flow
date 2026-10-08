---
name: closeout
description: 每一片 PR 合并之后：上线（按 P2 部署 + 冒烟）、清理分支与 worktree、请用户去试；track 的最后一片还要触发 track 做完的那次审阅（conductor/workflow.md §5、§7.1）。PR 已合并、用户说「收尾」「部署」「上线」「closeout」，或看到已合并却仍存在的 worktree 时触发。
---

合并后**立刻**跑，不留尾巴。主干名取 `.claude/flow.json` 的 `main_branch`（缺省 `main`），下文写作 `<main>`。
收尾本身**不产生任何提交**：track 登记、`[x]`、`blocked_by` 前缀都已随这一片的 PR 合并（workflow §5、§7.2）。

## 1. 确认已合并

```bash
gh pr view <n> --json state,mergeCommit,headRefName --jq '{state,merge:.mergeCommit.oid,branch:.headRefName}'
```

`state != MERGED` → **停**，先查清楚再删任何东西。squash 合并时 worktree HEAD 不是主干祖先，属正常；确认 worktree
没有未推送的提交即可。没有远端的本地项目：`git branch --merged <main>` 里有该分支即可。

## 2. 上线（按 P2）

- 读 `conductor/workflow.md` 的 **P2**：部署命令、谁来跑、冒烟检查。
- P2 写明模型可以跑的 → 跑部署，再跑冒烟（健康检查 + 本片改动的关键页面 / 接口）。被权限拦下 → 把一条可直接粘贴
  的命令给用户（提示用 `!` 前缀在本会话里跑，输出会回到对话），并发通知。
- P2 写「用户来部署」，或单向门片要求先 testnet / dry-run → 把命令和要看的结果给用户，发通知。
- 冒烟失败 → 立刻告诉用户，按 P2 的回滚办法处理，不要带病继续下一片。
- P2 为「无」→ 跳过。

## 3. 清理

叠链 PR 先 `gh pr edit <后续 n> --base <main>`（否则删 base 分支时 GitHub 会**关闭**叠在上面的 PR）。

```bash
git push origin --delete <branch>          # gh pr merge --delete-branch 已删则跳过
git worktree remove <path>                  # 或 ExitWorktree(action=remove)
git branch -D <branch>                      # squash 合并后只能 -D；第 1 步已确认合并
git worktree prune
git -C <主 checkout> pull --ff-only origin <main>
```

track 还有下一片 → 从最新主干开下一片的 worktree，接着 `/conductor:implement`。

## 4. 请用户去试

按分诊卡或 PR 描述的「怎么试」告诉用户去哪里点、会看到什么，**发通知，不等回复**。用户的反馈作为后面几片的输入；
设计包的 UI 片：确认实现中的 token / 组件演化已在同一 PR 落回设计真相源（P4），提醒协作者 `/flow:design push`。

## 5. track 做完（最后一片上线后）

- **二档**：按 workflow §6 派 `flow:phase-gate-reviewer` 审一次整个 track：输入 = 本 track 各片的 PR 号（纯展示的片除外）+
  spec。全是展示片就跳过。**三档不再审**（单向门片合并前都审过）。
- 结论贴在最后一片的 PR 上（首行 `VERDICT:`）。有 BLOCKER → 立刻开一个修复片（代码已经在线上），并告诉用户。
- 一档规格（`docs/specs/`）的状态行已在 PR 里写了 `PR #n`，不用再改。

## 汇报（用户的语言，三行）

```
现在能用什么：…（已上线 / 等你部署）
还缺什么：…（下一片 / 无）
需要你做什么：去 <哪里> 试一下 ｜ 跑这条部署命令 ｜ 无
```

## 自查

- [ ] `git worktree list` 里没有分支已合并却仍存在的 worktree
- [ ] 主 checkout `git status` 干净且在 `<main>`
