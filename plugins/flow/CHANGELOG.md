# Changelog

版本号即 `plugins/flow/.claude-plugin/plugin.json` 的 `version`，也是各项目 `conductor/workflow.md`
托管区标记里的版本。**不改 version 的提交，已安装的项目拿不到。**

## 0.1.1 — 2026-09-26

- **修复：`/flow:init` 不再跳过 conductor 的产品定义访谈。** 0.1.0 为了防 conductor setup 2.5 覆盖
  workflow.md，直接把 setup 标成了完成，连带跳过了产品 / 产品规范 / 技术栈 / 代码规范访谈与首个
  track。现在 `/flow:init` 改为编排：`seed`（放 flow 规则，并放一份到 `.conductor_templates/workflow.md`
  ——conductor 2.5 会优先拷它）→ 完整跑 `/conductor:setup`（只覆盖 2.5 不问覆盖率/git notes、首个
  track 过 `flow:spec-reviewer`）→ 补 flow 那层 → `finish` 最后写 `.claude/flow.json` 激活 hook
- 新项目判定由 flow 先做（conductor 会把「有 .git」当成已有项目，跳过「你想做什么」与需求访谈）
- 0.1.0 接入过的项目：重跑 `/flow:init` 会识别出伪造的 setup 状态（`conductor=flow-seeded`），
  在 worktree 里补做完整访谈，已填的项目补充与 hook 规则保留
- 敏感域提问加「无」选项，措辞改为如实（PR 由用户合并是规则约束，不是硬拦截）
- `init-project.sh` 拆成 `status` / `seed` / `finish`；doctor 检查 conductor setup 是否真跑过
- flow 不再生成 product / tech-stack / product-guidelines 骨架与 setup_state.json

## 0.1.0 — 2026-09-26

首个版本，从 token-router 的 workflow v2.1（2026-08-29）抽离。

- 规则正文：`templates/workflow.md`（§0–§8）→ 各项目 `conductor/workflow.md` 托管区；项目特有内容
  （敏感域、层划分、命令、设计源、失败基线、其他规则）挪到文末「项目补充 P1–P6」
- skills：`init` `sync` `triage` `spec` `closeout` `catchup` `visual-verify` `design-track`
- agents：`spec-reviewer` `phase-gate-reviewer` `architecture-reviewer` `security-reviewer`
- hooks（仅对有 `.claude/flow.json` 的仓库生效）：主 checkout 只读、design 快照只读、保护路径、
  禁止整文件重写、危险 Bash 命令、tracks.md 不变量、JSON 重复键、保存即格式化、敏感域提醒、
  worktree 自动软链 .env、开场上下文 + 版本漂移检查、未收尾提醒
- 与 token-router 原版的差异：
  - 主 checkout 只读只管**本项目仓库**的文件（原版拦所有处于 main 的仓库）
  - 敏感域提醒改为 PostToolUse `additionalContext`，同 session 同文件只提醒一次
  - Stop 提醒不再报「当前 worktree 有未提交变更」（干活中途是常态），只报真正没收尾的
  - tracks.md 状态标记校验收紧为「只许 `[ ]/[~]/[x]`」
  - no_full_rewrite 只拦 Write **已存在**的文件，新建放行
