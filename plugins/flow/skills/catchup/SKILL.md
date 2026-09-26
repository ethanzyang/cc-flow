---
name: catchup
description: 恢复上下文。在 /clear 后或新 session 开始时使用。当用户说恢复上下文、继续之前的工作、catchup 时触发。
---

恢复上下文。在 /clear 后或新 session 开始时使用。

## 步骤

1. `git branch --show-current` + `git status` + `git log --oneline -20` 看分支与最近提交；
   `git worktree list` 看有哪些进行中的 worktree
2. 若在 track worktree：读该 track 的 `conductor/tracks/<track>/plan.md`（进度真相源），
   定位最后一个 `[~]` / 未勾任务与最近的检查点 SHA
3. 读 `conductor/tracks.md` 的 `[~]` 条目，确认当前工作属于哪个 track；
   一档任务改看 `docs/specs/<x>.md` 的状态行
4. `git diff --stat origin/<main>...HEAD` 看本分支累计变更面（`<main>` 见 `.claude/flow.json`）

## 输出格式

```
## 当前状态
- 分支: xxx
- 所属 track / spec: xxx（或「无，属一次性任务」）
- 最近工作: （从 git log 与 plan.md 总结）
- 未完成的事: （plan.md 未勾任务 + 未提交变更）

## 建议下一步
- （基于上下文给出 1-3 个建议）
```
