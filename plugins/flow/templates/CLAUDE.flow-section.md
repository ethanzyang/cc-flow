## 工作流（flow：按后果分级，以上线为终点）

规则的**唯一事实源**是 `conductor/workflow.md`（flow 插件托管区 + 文末「项目补充」；导览 `dev-docs/TEAM_GUIDE.md`）。

- **先定形再动手**：新需求先 `/flow:shape` 出一张 ≤15 行的定形卡（目标 / 第一片做完你能 / 这次不做 / 胃口 /
  门 / 怎么验收 / 切片）；用户在问方案时只出方案、不写代码。用户说「做」后 `/flow:build` 一片一片做。
- **两类门**：错了 revert 重发就没事的是双向门——一次 `flow:pr-reviewer` 审阅、无 BLOCKER 就合并上线；
  收不回来的是单向门（项目补充 P1）——spec + 写代码前一轮 `flow:risk-reviewer` + PR 终审加安全审阅、用户合并。
- **小片上线**：一片一个 PR、非测试代码约 ≤400 行、端到端可用；不按层切。合并后 `/flow:closeout` 部署、清理、请用户试。
- **停点只有三处**：定形卡 / 单向门 PR 合并 / 上线后请用户试；等用户时发通知。其余由模型拍板，不问流程问题。
- 超过胃口 2 倍、审阅两轮仍有 BLOCKER、同一问题纠正两次 → 停下带选项找用户（断路器）。

## 分支与并行开发

**主 checkout（仓库根目录）是只读基座**：永远停在 `{{MAIN}}`，从不在里面编辑（flow 的 hook 按被改
文件所在分支拦截）。

- **新任务**：`EnterWorktree`，或 `git worktree add -b <branch> .claude/worktrees/<name> origin/{{MAIN}}`
- **动手前** `git fetch`，查有没有既有分支或已合并 PR 在做同一件事
- `.env` 等本地文件不跟着 worktree 走，flow 的 hook 自动软链主 checkout 那份（`.claude/flow.json` 的 `worktree_links`）
- 多个 worktree 同时跑 dev server 会抢端口，手动错开

新教训归档：代码类 → hook（`.claude/flow.json`；硬禁止用 `permissions.deny`）→ `.claude/rules/`（frontmatter 用
`paths:`）/ 领域陷阱进 skill → 最后才进本文件；**流程类 → 当天改 `conductor/workflow.md`**（通用的提到 flow
插件仓库，本项目的写进「项目补充」），不要只记在 memory 里。
