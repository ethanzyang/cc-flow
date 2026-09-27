# Changelog

版本号即 `plugins/flow/.claude-plugin/plugin.json` 的 `version`，也是各项目 `conductor/workflow.md`
托管区标记里的版本。**不改 version 的提交，已安装的项目拿不到。**

## 0.4.1 — 2026-09-28

**guard-bash 不再误拦只读和正常的 git 命令。**之前只要命令里出现 `>`，同时 `conductor/tracks/` 后面任意位置
带 design 字样就拦。而 `2>/dev/null`、`2>&1`、commit 尾注 `<noreply@…>` 里都有 `>`，于是读快照、`git add`
快照、提 PR、改 `design-input.md` 旁边的 plan.md 全被当成「写 design 快照」拦下，`/flow:design-track`
自己提交快照这一步也会撞上。

- 改成只判断**写入目标**：重定向目标、tee/sponge 的参数、dd 的 `of=`、sed -i 的参数；相对路径按命令里的
  `cd` 目录补全后再判断
- 快照路径严格按 `conductor/tracks/<id>/design*/…` 判：track 目录下的 `design-input.md`、名字里带
  design 的 track 都不算快照
- `no_full_rewrite` 也改成按写入目标判断，`cat x.json 2>&1` 之类的读命令不再被拦
- 残余缺口：用变量展开写出的路径（`> "$f"`）认不出

## 0.4.0 — 2026-09-26

**设计包是 track 立项里的一个环节，不是 new-track 之外的入口**（0.3.0 把它写成了并列入口，判据也错成了「有没有设计稿」）。

- `/flow:triage`：分诊卡加「设计输入」一行——判据是视觉不确定且不满足 §3.1 降级三条 → 设计包；满足降级 →
  spec 内嵌结构（模式③）；UI 微调 → 现状截图（模式②）；纯后端 → 无。要设计包的再定时机：设计先行 / 行为先冻结
- `/flow:design-track` 改成按状态走的设计环节：
  - 阶段 A（还没有设计包）：核实约束设计的事实（或做已冻结 spec 的投影），写 BRIEF、预填业务规则进 DECISIONS，
    推到用户的 Claude Design，停下交给用户画
  - 阶段 B（四件套齐了）：拉回 → 校验与冲突检查 → 快照 → 新 track 接 new-track（复用已登记条目）/
    `--track <id>` 挂到已有 track 并修订 spec（设计改版快照到 `design-r2/`）→ spec review
  - 新 track 停在立项终点；已有 track 审过后继续 UI phase
- `/flow:init`：conductor 提议的首个 track 若是「设计包 · 设计先行」，不在 setup 里生成 spec/plan，交给 design-track
- workflow §2.1 / §3 / §3.2、TEAM_GUIDE、README、CLAUDE.md 设计段同步改写

## 0.3.0 — 2026-09-26

收敛到核心使命：**人专注立项，立项做对后实现按 plan 自己跑，设计系统串在同一条线上**。skill 从 10 个减到 7 个。

- 合并：`sync` 并入 `init`（已接入项目重跑 init = 升级；细节在 `skills/init/upgrade.md`）；
  `design-push` + `design-pull` 合成 `/flow:design push|pull`
- 删除：`catchup`（实现阶段 `/conductor:implement` 会从 plan.md 接上进度）
- `/flow:design-track` 变成 Lane A 立项一条龙：从 Claude Design 拉设计包 → 校验四件套 → 快照 →
  接着 new-track（复用已登记的 track，不重复建）→ spec review → 立项终点；设计包与 spec/plan 同一个立项 PR
- `/flow:triage`：二/三档立项明确走到立项终点（spec review → 登记 → 立项提交 → 三行交接 → 停）
- CLAUDE.md 按 token-router v2.1 的原则写：只写每个 session 都要知道、不写就会错的；按文件类型的规则进
  `.claude/rules/`（frontmatter 用 `paths:`）；领域陷阱进 domain-traps skill；测试钉住的压成「契约 + 测试名」
- CLAUDE.md 设计段加「美学方向归设计系统」（有设计输入时设计类 skill 的自由发挥条款失效）
- doctor：CLAUDE.md 过长提醒；rules 用了 `globs:`（Claude Code 只认 `paths:`，会被当成无条件规则）提醒
- TEAM_GUIDE 补 `/clear` 判断表、反模式表、内置命令

## 0.2.0 — 2026-09-26

设计模块：从 token-router 的 `design-system/` + `SYNC.md` 抽出，可选启用。

- `/flow:init` 对有 UI 的项目问「要不要用 Claude Design 管设计系统」；已接入的项目可走 E 路线补装
- `init-project.sh design`：设计目录骨架 `README.md` + 托管的 `SYNC.md`（多账号用 git 合流、
  push/pull 规矩、分批与核对、256 KiB 上限、SVG 重序列化、字体 push-only、多人协作、收尾动作）+
  文末项目补充 D1 目录职责 / D2 token 派生关系 / D3 已知缺口；gitignore `.project-id`；
  `finish` 自动登记 `flow.json` 的 `design.dir` 并软链 `.project-id` 进 worktree
- 新 skill（仅用户手动调用）：`/flow:design-push`（首次选/建自己的 Claude Design 设计系统项目，
  按 git 清单分批推送并核对）、`/flow:design-pull`（feature 包 / 指定文件 / 首次全量，走 worktree 开 PR）
- `/flow:sync` 同时托管设计目录的 `SYNC.md`；doctor 检查 `.project-id` 未进版本库
- 主 checkout 只读的 hook 不再拦被 gitignore 的本地文件（如 `.project-id`）；`.env` 仍由 protected_paths 保护
- workflow 托管区 / TEAM_GUIDE 的 Lane A 步骤接上 design-push / design-pull

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
