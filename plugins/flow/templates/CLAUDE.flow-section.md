## 工作流（先分诊再动手）

规则的**唯一事实源**是 `conductor/workflow.md`（flow 插件托管区 + 文末「项目补充」；导览
`dev-docs/TEAM_GUIDE.md`）。拿到需求先跑 `/flow:triage`。三句话版：

- **分档**：无敏感域 + ≤2 层 + 一句话说得清 → 一档（`/flow:spec` 或直接修）；跨层/多 phase → 二档
  （开 track）；敏感域、改既有表列、改已上线口径、视觉不确定 → 三档（全套 + 分 session）。
- **拆分守则**：拆之前先答「做完第一段用户能亲手用到什么」；答不出就不拆。拆了就**同时立项**
  （都进 tracks.md，后段标 `blocked_by`），第二段免重走采访。
- **停点只有 5 处**（workflow §0）：分诊卡 / 访谈 ≤3 问 / 拍板清单 / 立项终点 / 敏感域 PR merge。
  其余由 review agent 代拍板，不停下等人。

## 分支与并行开发

**主 checkout（仓库根目录）是只读基座**：永远停在 `{{MAIN}}`，从不在里面编辑（flow 的 hook 按被改
文件所在分支拦截）。

- **新任务**：`EnterWorktree`，或 `git worktree add -b <branch> .claude/worktrees/<name> origin/{{MAIN}}`
- **动手前** `git fetch`，查有没有既有分支或已合并 PR 在做同一件事
- **合并后立刻收尾**（`/flow:closeout`）：删远端分支 + `git worktree remove` + `git branch -d`
- `.env` 等本地文件不跟着 worktree 走，flow 的 hook 自动软链主 checkout 那份
  （`.claude/flow.json` 的 `worktree_links`）
- 多个 worktree 同时跑 dev server 会抢端口，手动错开

新教训归档顺序：代码类 → hook（`.claude/flow.json`；硬禁止用 `permissions.deny`）→ 只对某类文件成立
的进 `.claude/rules/`（frontmatter 用 `paths:`）/ 领域陷阱进 skill → 最后才进本文件；流程类 → 通用的
提到 flow 插件仓库，本项目的写进 `conductor/workflow.md`「项目补充」。
**每次 Claude 犯错就把它写成一条规则**，而不是当场口头纠正。
