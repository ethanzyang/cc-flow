# Changelog

版本号即 `plugins/flow/.claude-plugin/plugin.json` 的 `version`，也是各项目 `conductor/workflow.md`
托管区标记里的版本。**不改 version 的提交，已安装的项目拿不到。**

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
