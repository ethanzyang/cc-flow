---
name: closeout
description: PR 合并后的收尾三连 + 记账（conductor/workflow.md §6）。当 PR 已合并、用户说「收尾」「清理分支」「closeout」，或看到已合并却仍存在的 worktree 时触发。
---

合并后**立刻**跑，不留尾巴。不收尾会攒出几个 G 的 worktree 和无人认领的孤儿改动。

主干名取 `.claude/flow.json` 的 `main_branch`（缺省 `main`），下文写作 `<main>`。

## 前置：叠链 PR 先改 base

如果有后续 PR 叠在本分支上，**先**把它们全部 `gh pr edit <n> --base <main>`。否则删 base 分支时
GitHub 会直接**关闭**（而非重定向）叠在上面的 PR，救起来很麻烦。

## 步骤

1. **确认已合并且提交都在主干**
   ```bash
   gh pr view <n> --json state,mergeCommit --jq '{state,merge:.mergeCommit.oid}'
   git fetch -q origin && git merge-base --is-ancestor <worktree-HEAD> origin/<main> && echo safe
   ```
   `state != MERGED` 或不是 `origin/<main>` 祖先 → **停**，先查清楚再删任何东西。
   （squash 合并时 worktree HEAD 不是祖先：改用 `gh pr view` 的 MERGED + 确认 worktree 无未推送提交。）
   没有远端的本地项目：确认 `git branch --merged <main>` 里有该分支即可。

2. **三连清理**
   ```bash
   git push origin --delete <branch>          # gh pr merge --delete-branch 已删则跳过
   git worktree remove <path>                  # 或 ExitWorktree(action=remove)
   git branch -d <branch>                      # squash 合并需 -D，先确认第 1 步
   git worktree prune
   ```

3. **主 checkout 回到最新主干**：`git -C <主 checkout> pull --ff-only origin <main>`
   （主 checkout 只读，永远停在 `<main>`）

4. **记账**（conductor track 才需要；在新 worktree 或随下一个 PR 提交，不在主 checkout 上改）
   - `conductor/tracks.md` 该条目 → `[x]`
   - **若有条目的描述行以 `⛔ blocked_by: <本 track>` 开头**：把这段前缀删掉（workflow §2.3）。
     有后继却不在 tracks.md → 补登记（拆分即同时立项）
   - `docs/specs/` 的一档规格：头部状态改 `已合并 PR #n`
   - Lane A track：确认 token / 组件演化已在**同一 PR** 里落回设计真相源（workflow.md P4）；
     提醒协作者同步各自的云端副本

5. **汇报三行**（workflow §3.3）
   ```
   现在能用什么：…
   还缺什么：…
   需要你做什么：…（通常是「部署」或「无」）
   ```

## 检查清单（跑完自查）

- [ ] `git worktree list` 里没有分支已合并却仍存在的 worktree
- [ ] `git branch --merged origin/<main>` 里没有残留的本 track 分支
- [ ] 主 checkout `git status` 干净且在 `<main>`
- [ ] tracks.md `^## ` 计数 == `^---$` 计数（flow hook 也会校验）
