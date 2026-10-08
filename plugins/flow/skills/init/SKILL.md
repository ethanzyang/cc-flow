---
name: init
description: 把 flow 开发工作流接入当前仓库。编排：先放 flow 的规则 → 跑完整的 /conductor:setup 产品定义访谈（产品 / 规范 / 技术栈 / 代码规范 / 首个 track）→ 补 flow 自己那层（单向门、上线、命令、hook 规则）→ 最后激活 hook。用户说「接入 flow」「初始化工作流」「flow init」、或在还没有 .claude/flow.json 的仓库里想用 /flow:* 时触发；也用于：插件升级后同步托管区（含从 0.4 / 0.5 升级到 0.6）、给已接入项目补设计模块、补做 conductor 访谈。
---

你是编排者：**产品定义交给 conductor 的完整 setup 访谈**，flow 只负责放规则、补自己那层、最后激活 hook。
确定性步骤交给脚本 `${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh`（`status` / `seed` / `design` / `finish`）。
接入本身是双向门：一个 PR，doctor 通过即可合并。

## 0. 摸底（写任何文件之前）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" status "$(pwd)"
```

- 可用 skill 里没有 `conductor:setup` → 停下，请用户先装 conductor：
  `/plugin marketplace add https://github.com/pilotparpikhodjaev/conductor_cc.git` +
  `/plugin install conductor@conductor-cc`。flow 的二 / 三档靠它的 `new-track` / `implement`。
- 没有 `jq` → 停下请用户安装（flow 的 hook 全靠它）。
- 记下 `maturity`（greenfield 新项目 / brownfield 已有代码）——这是 flow 在放任何文件**之前**的判定，第 3 步要
  原样交给 conductor。
- `workflow=managed:v<旧>`（托管区落后）→ 先读 `upgrade.md` 第 1 节照做，再按下表走。

| status | 路线 |
|---|---|
| `flow=none` + `conductor=none` | **A 完整接入** |
| `flow=none` + `conductor=real` | **B 已有 conductor**：跳过第 3 步；`workflow=unmarked` 时先按 `upgrade.md` 第 2 节把它迁成托管版 |
| `conductor=partial:<step>` | **C 续跑**：第 3 步从断点继续（conductor 自己会 resume），其余同 A |
| `conductor=flow-seeded`，或 `flow=adopted` + `conductor=none` | **D 补做产品定义**：flow 0.1.0 把 setup 直接标成了完成、或 0.5 接入时没跑 conductor——访谈没跑过 |
| `flow=adopted` + `conductor=real` | 已接入：跑 `doctor.sh` 汇报；用户要**补设计模块** → **E 路线**；否则结束 |

**E 补设计模块**（已接入的项目）：EnterWorktree（`design-module`）→ 第 4 步的「设计模块」小节 → `doctor.sh` →
提交 `chore: add flow design module`、开 PR。其余步骤跳过。

## 1. 工作区

- `git=none` → 问用户是否 `git init -b main`（唯一的前置问题），然后就地做。
- `git=unborn` → 就地做。
- `git=commits` → `git fetch -q`（有远端时）后 **EnterWorktree**（A/B/C 名为 `adopt-flow`，D 名为
  `redo-product-definition`）。必须用 EnterWorktree 切换 session 的工作目录——conductor setup 按当前目录写文件，
  只 `git worktree add` 不切目录会写进主 checkout。

**D 路线额外一步**（`conductor=flow-seeded` 时，在 worktree 里）：把 0.1.0 生成的薄文档与伪造状态清掉，单独提交，
让 conductor 面对干净工作区：

```bash
git rm -q conductor/setup_state.json conductor/product.md conductor/product-guidelines.md conductor/tech-stack.md
git rm -q -r conductor/code_styleguides      # 存在才删
git commit -q -m "chore: reset flow-seeded conductor setup"
```

`conductor/workflow.md`（含已填的项目补充 P1–P6）、`conductor/tracks.md`、`CLAUDE.md`、`.claude/` **保留**。

## 2. 放规则（seed）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" seed "<工作目录>" --main <主干>
```

它会：生成 `conductor/workflow.md`（托管区 + 项目补充骨架；已存在则同步托管区）与 `dev-docs/TEAM_GUIDE.md`；把
workflow.md 同内容放一份到 `.conductor_templates/workflow.md`（conductor setup 2.5 会优先拷这个，于是拷进去的就是
flow 的规则；该目录只在本地 git 排除、不进提交）；建 `conductor/backlog.md`、`CLAUDE.md`（不存在时）、合并
`.claude/settings.json`（flow + conductor 两个插件 + 权限基线）、补 `.gitignore`。**不写** product / tech-stack 等文档，
**不写** `.claude/flow.json`。

输出里「无标记」→ 按 `upgrade.md` 第 2 节迁移后重跑 seed；「待插入 / 待替换」→ 第 4 步处理。

## 3. 完整跑 conductor setup（B 路线跳过）

先告诉用户一句：「接下来是 conductor 的产品定义访谈：产品、产品规范、技术栈、代码规范，每节最多 5 问，每题都可以
选 E 让它自动生成后再审；新项目还有需求访谈和第一个 track 的提议。」

然后调用 skill `conductor:setup`，**完整执行它的协议**，只按下面几条覆盖（本 skill 是编排者；workflow §7.3 已声明
conductor 与 flow 冲突时以 flow 为准）：

1. **新旧项目判定**：用第 0 步的 `maturity`，不要重判——`.git`、`.claude/`、`CLAUDE.md`、`conductor/workflow.md`、
   `dev-docs/`、`.conductor_templates/` 都是 flow 刚放的。greenfield 就走「What do you want to build?」和 3.1 需求访谈。
2. **greenfield 的 git init**：已在第 1 步做过，跳过。
3. **「uncommitted changes」警告**：flow seed 的文件未提交属预期，提示一句即可，不必停。
4. **2.5 workflow**：**不问** default / customize——它描述的「80% 覆盖率、每任务提交、git notes」是它自带的模板。
   flow 已定：不设覆盖率阈值；任务勾选与代码同一个提交；不用 git notes；不做检查点提交、不回填 SHA（workflow §4.1、
   §5、§7.2）。按它的第 1 步从 `.conductor_templates/workflow.md` 拷到 `conductor/workflow.md`（内容相同），写 state
   `2.5_workflow`，继续。
5. **3.2 提议首个 track**：在提议里附上分诊（档位 / 车道 / 设计输入，按 `/flow:triage` 的判据）。brownfield 且用户
   没有明确的下一件事 → 允许「暂不建 track」：写 state `3.3_initial_track_generated`，直接到 3.4。首个 track 判为
   「设计包 · 设计先行」→ 同样不在这里生成 spec / plan（设计还没画）：写 state 后到 3.4，汇报里写明「首个 track 从
   `/flow:design-track <feature>` 开始」（需要设计模块，第 4 步会问）；「设计包 · 行为先冻结」→ 照常生成，plan 里 UI 片
   的第一个任务写成 `/flow:design-track <feature> --track <本 track>`。
6. **3.3 首个 track**：`conductor/tracks.md` 已存在时**不要重建**，在末尾追加（前置 `---`）。spec ≤200 行（只写不变量、
   公式、失败模式、对外契约等该逐字的，实现细节写「实现方自选」）；plan 按 workflow §3.1 排：**phase = 能单独上线的
   竖切小片**（一个 phase 一个 PR、非测试代码约 400 行以内、第一片先走通骨架、phase 末是 conductor 格式的 meta-task），
   不按层切。**只有三档**才派 `flow:spec-reviewer` 审一次，BLOCKER 修进 spec（复审只核对 BLOCKER、最多一次）。
7. **3.4**：提交照做（`conductor(setup): Add conductor set up files`——`status` 靠这条提交判断访谈跑过，别改写）。它最后
   那句「现在跑 /conductor:implement」**不要照说**——回到本 skill 第 4 步。首个 track 的文件随接入 PR 一起合并。

conductor 的访谈是一次性的项目定义，不受 workflow §1 停点 2「≤3 问」限制（那条管单个需求）。

## 4. 补 flow 自己那层

D 路线：P1–P6 与 hook 规则都已填过——只按新的产品 / 技术栈定义补改有变化的项，已答过的不再问。

先读刚产出的 `conductor/product.md`、`tech-stack.md`；brownfield 再派一个 Explore subagent 返回：check 能用的
typecheck / lint / test 命令、dev / 格式化命令、部署方式、**会动钱或不可逆的代码路径**（给 glob，列到真正做判定、写库的
代码，不只是入口）、UI 与主题切换方式、既有约定（AGENTS.md / .cursorrules / CONTRIBUTING）。

**问用户（一次 AskUserQuestion，没有歧义的不问）**：

1. **单向门**（必问）：列候选（「错了 revert 重发也收不回来」的：动钱、记账口径、密钥权限、改既有表列 / 数据迁移、
   审批与状态机守卫、对外发出就收不回的动作），并给「无」选项。措辞如实：「这些改动走三档：spec 审一次、先行测试、
   合并前审一次、PR 由你合并」。
2. **上线**：合并后怎么部署、模型能不能自己跑部署命令、冒烟看什么、怎么回滚（没有部署环境选「无」）。
3. **设计系统**（项目有 UI 时才问；D 路线已答过不问）：「要不要用 Claude Design 管设计系统？——建 `design-system/`
   作为设计唯一真相源 + 协作规范，之后用 `/flow:design push` / `pull` 在仓库和你的 Claude Design 之间同步；视觉没定的
   需求（A 车道）靠它出设计包」。选项：要 / 暂不要（以后可补）。
4. 真有歧义的命令或约定（没有就不问）。

**填写（用 Edit；此时 hook 尚未激活）**：

- `conductor/workflow.md` 文末项目补充：
  - **P1 单向门清单**：按后果写「后果 — 典型路径」；「无」就写无。
  - **P2 上线**：部署命令、谁来跑（模型 / 用户）、冒烟检查、回滚；三档涉及资金的 testnet / dry-run 怎么跑。
  - **P3 命令**：**一条 `check` 命令**跑完 typecheck / lint / test（没有就在仓库里加一个脚本），再加 dev server、单个测试。
  - **P4 UI**：截图方式与主题切换；无 UI 写「无 UI」。
  - **P5 失败基线**：主干上跑一遍 check 记下已知失败；全绿或新项目还没代码写「无」。
  - **P6 项目规则**。技术还没定的项写「首个 track 定技术后补」，不留（待填）。
- **CLAUDE.md**——每个 session 都常驻，只写「每个 session 都要知道、不写 Claude 就会做错」的，祈使句：
  - 分流：碰某类文件才相关 → `.claude/rules/<名>.md`（frontmatter 用 **`paths:`** 列 glob；写成 `globs:` 会被当成无条件
    规则每次都加载）；某个高危领域的陷阱全文 → 项目 skill `.claude/skills/domain-traps/SKILL.md`（description 列出触发的
    文件名和关键词），CLAUDE.md 每域只留 ≤3 行契约 + 指针；已有测试钉住的约束 → 压成「契约 + 测试名」一行；流程 →
    workflow.md；能机械强制的 → `flow.json` / `permissions.deny`。
  - 结构：一句话定位（+ 文案红线，细节指向 `conductor/product.md`）/ 命令 / 工作流段 / 分支与并行段 / 设计段（启用时）/
    关键目录 / 核心规则（编号；陷阱类附一句为什么）/ 已知陷阱 / 当你不确定时。目标 ≤100 行。
  - 新生成的：填实模板里的 `{{NAME}}` `{{TAGLINE}}` `{{STACK}}` 等，不留占位符；没有规则可写就空着「核心规则」，
    **不编造**——规则来自之后每次 Claude 犯错。
  - 已存在的：「待插入」→ 把 `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.flow-section.md`（`{{MAIN}}` 换成主干名）插到命令段
    之后；「待替换」→ 用它替换旧的工作流段与分支段。原文超过约 150 行、或混着只对某类文件有效的规则 / 大段领域陷阱时，
    按上面的分流挪出去（**语义一条不丢**），挪了什么列进 PR 描述。
- **`.claude/rules/`**：只为既有约定里**明确写着**的、按文件类型成立的规则建，每份 5–10 条，frontmatter `paths:`；没有就
  不建，不从通用最佳实践里凑。
- **设计模块**（选了「要」，或 E 路线）：
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" design "<工作目录>" [--dir design-system]
  ```
  生成设计目录的 `README.md` 骨架与托管的 `SYNC.md`，gitignore `.project-id`。然后填：`SYNC.md` 文末 D1 目录职责、
  D2 token 派生关系（实现侧镜像 token 的写清源 → 镜像与钉住它的测试；没有写「无」）、D3；workflow.md P4（设计真相源
  目录 / 协作文档 = `<目录>/SYNC.md`）；CLAUDE.md 插入 `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.design-section.md`
  （`{{DESIGN_DIR}}` 换成目录名）。`finish` 会把 `design.dir` 登记进 flow.json（E 路线由 `design` 子命令直接登记）。
- **hook 规则**写进 scratch 目录下的 `flow-rules.json`（**不要**写进仓库），只放非空字段：
  ```json
  {
    "sensitive_paths": ["*/billing/*"],
    "protected_paths": [{ "glob": "*/generated/*", "reason": "生成文件，改源再生成。" }],
    "no_full_rewrite": [{ "glob": "*/locales/*.json", "reason": "有重复键。" }],
    "json_dup_key_check": [{ "glob": "*/locales/*.json", "known": ["已存在的重复键"] }],
    "format_on_edit": [{ "globs": ["*.go"], "cmd": "gofmt -w \"$FILE\"" }],
    "worktree_links": [".env"],
    "bash_guard": { "test_db_pattern": "(^|_)test(_|$)" }
  }
  ```
  glob 用 shell `case` 语义（`*` 可跨目录）；`format_on_edit.cmd` 在被改文件所属仓库根执行，路径在 `$FILE`；数组字段会
  与模板默认项（.env、CI 保护）合并。`sensitive_paths` 填 P1 里需要机械提醒的路径——它只是提醒，单向门的判据是后果。
  `bash_guard.test_db_pattern` 是 Bash 守卫判「测试库」的库名正则（删库 / 清表只在测试库上放行），按项目的库名改。

## 5. 激活并体检

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" finish "<工作目录>" --rules "<scratch>/flow-rules.json"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" "<工作目录>"
```

`finish` 删掉 `.conductor_templates/`、缺 `tracks.md` 就补空的、**最后**写 `.claude/flow.json`——它一出现，flow 的
hook 就对仓库生效；就地接入的项目此后主干上的 Edit 会被「主 checkout 只读」拦下。所以**所有填写必须在 finish 之前
做完**；doctor 报出要改的，就地项目开 worktree 改，worktree 项目直接改。D 路线已有 flow.json，finish 只做清理与检查。

doctor 必须「结论：通过」；△ 项能处理的处理掉，处理不了的写进汇报。

## 6. 提交与交付

- 提交：A/B/C `chore: adopt flow workflow`；D `docs(conductor): redo product definition via conductor setup`。
- 在 worktree 里且有 `origin` + `gh` 已登录 → 推分支、开 PR，描述列出生成 / 修改的文件与 doctor 输出；合并按 workflow §5
  第 5 步（有 `Bash(gh pr merge:*)` 权限由模型合并，否则把命令交给用户并发通知）。worktree 但没有远端 → 主 checkout
  `git merge --ff-only <分支>` 后删 worktree。就地接入 → 提交即完成。
- 合并后提醒：主 checkout 从此只读；队友 clone 后信任目录即会被提示安装 flow 与 conductor。

## 汇报（三行）

```
现在能用什么：本仓库已接入 flow + conductor——产品 / 技术栈文档已定，<首个 track <id> 已立项 ｜ 未建首个 track>；新需求 /flow:triage，合并后 /flow:closeout
还缺什么：<doctor 的 △ 项 / 技术未定的 P3 命令 / 无>
需要你做什么：<合并 PR #n ｜ 确认上线方式 ｜ 无>；首个 track：<二档：说「做」即在本会话 /conductor:implement ｜ 三档：在 <第一片 worktree 路径> 开新 session（或先 /flow:catchup）跑 /conductor:implement ｜ 设计先行：/flow:design-track <feature>>
```

启用了设计模块时再加两行：每个成员首次 `/design-login` + `/flow:design push`（选或建自己的 Claude Design 设计系统
项目并全量推送）；还没有设计系统的，在 claude.ai/design 生成后跑 `/flow:design pull --all` 全量拉回。

## 升级 / 接入旧 workflow.md

托管区落后（升级，含 0.4 / 0.5 → 0.6 的结构调整）或 seed 报「无标记」（旧项目手写过 workflow.md）时，读
`${CLAUDE_PLUGIN_ROOT}/skills/init/upgrade.md` 照做。
