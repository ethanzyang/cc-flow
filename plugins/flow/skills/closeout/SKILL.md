---
name: closeout
description: PR 合并之后：上线（按 P2 部署 + 冒烟）、清理分支与 worktree、请用户去试（conductor/workflow.md §3.5）。PR 已合并、用户说「收尾」「部署」「上线」「closeout」，或看到已合并却仍存在的 worktree 时触发。
---

合并后**立刻**跑，不留尾巴。主干名取 `.claude/flow.json` 的 `main_branch`（缺省 `main`），下文写作 `<main>`。

## 1. 确认已合并

```bash
gh pr view <n> --json state,mergeCommit,headRefName --jq '{state,merge:.mergeCommit.oid,branch:.headRefName}'
```

`state != MERGED` → **停**，先查清楚再删任何东西。squash 合并时 worktree HEAD 不是主干祖先，属正常；
确认 worktree 没有未推送的提交即可。没有远端的本地项目：`git branch --merged <main>` 里有该分支即可。

## 2. 上线（按 P2）

- 读 `conductor/workflow.md` 的 **P2**：部署命令、谁来跑、冒烟检查。
- P2 写明模型可以跑的 → 跑部署，再跑冒烟（健康检查 + 本次改动的关键页面 / 接口）。被权限拦下 → 把一条
  可直接粘贴的命令给用户（提示用 `!` 前缀在本会话里跑，输出会回到对话），并发通知。
- P2 写「用户来部署」或单向门要求先 testnet / dry-run → 把命令和要看的结果给用户，发通知。
- 冒烟失败 → 立刻告诉用户，按 P2 的回滚办法处理，不要带病继续。
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

不提交任何记账改动（workflow §6：状态在 GitHub 和 git 里）。

## 4. 请用户去试

用定形卡的「怎么验收」告诉用户去哪里点、会看到什么；问题就作为下一片的输入。等用户时发通知。

## 汇报（用户的语言，三行）

```
现在能用什么：…（已上线 / 等你部署）
还缺什么：…（下一片 / 无）
需要你做什么：去 <哪里> 试一下 ｜ 跑这条部署命令 ｜ 无
```

## 自查

- [ ] `git worktree list` 里没有分支已合并却仍存在的 worktree
- [ ] 主 checkout `git status` 干净且在 `<main>`
