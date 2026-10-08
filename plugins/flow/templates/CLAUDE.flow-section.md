## 工作流（flow：conductor 为底座，按后果分级，一片一上线）

规则的**唯一事实源**是 `conductor/workflow.md`（flow 插件托管区 + 文末「项目补充」；导览 `dev-docs/TEAM_GUIDE.md`）。

- **先分诊再动手**：新需求先 `/flow:triage` 出分诊卡（档位 / 第一片做完你能 / 切片 / 这次不做 / 胃口 / 怎么验收），
  用户说「做」才开工；用户在问方案时只出方案、不写代码。
- **三档按后果和规模**：双向门、一个 PR 做得完 → 一档 `/flow:spec`；双向门、要多片 → 二档
  `/conductor:new-track` + `/conductor:implement`；碰单向门（项目补充 P1）→ 三档，同样走 track，spec 审一次、
  先行测试不改断言、单向门那一片合并前审一次并由用户合并。层数、文件数不作判据。
- **plan 按能上线的小片排**：一个 phase 一个 PR，非测试代码约 ≤400 行，端到端可用，不按层切；每片合并后
  `/flow:closeout` 部署、冒烟、清理，通知用户去试，接着做下一片。
- **一个改动审一次**：一档有逻辑的审 1 次；二档整个 track 做完审 1 次；三档写代码前审 spec 1 次 + 单向门片合并前
  审 1 次。只有 BLOCKER 必须修。
- **停点只有 4 处**：分诊卡 / 访谈 ≤3 问 / 立项确认（spec + plan 一次）/ 三档 PR 合并；等用户时发通知。
  超过胃口 2 倍、复审后仍有 BLOCKER、同一问题纠正两次 → 停下带选项找用户（断路器）。
- **记账随代码走**：plan 勾选与代码同一提交；立项文件跟第一片的 PR，`[x]` 跟最后一片；不回填 SHA、不开记账 PR。

## 分支与并行开发

**主 checkout（仓库根目录）是只读基座**：永远停在 `{{MAIN}}`，从不在里面编辑（flow 的 hook 按被改
文件所在分支拦截）。

- **新任务**：`EnterWorktree`，或 `git worktree add -b <branch> .claude/worktrees/<name> origin/{{MAIN}}`
- **动手前** `git fetch`，查有没有既有分支或已合并 PR 在做同一件事
- `.env` 等本地文件不跟着 worktree 走，flow 的 hook 自动软链主 checkout 那份（`.claude/flow.json` 的 `worktree_links`）
- 多个 worktree 同时跑 dev server 会抢端口，手动错开；`/clear` 之后用 `/flow:catchup` 接上进度

新教训归档：代码类 → hook（`.claude/flow.json`；硬禁止用 `permissions.deny`）→ `.claude/rules/`（frontmatter 用
`paths:`）/ 领域陷阱进 skill → 最后才进本文件；**流程类 → 当天改 `conductor/workflow.md`**（通用的提到 flow
插件仓库，本项目的写进「项目补充」），不要只记在 memory 里。**每次 Claude 犯错就把它写成一条规则**，而不是当场口头纠正。
