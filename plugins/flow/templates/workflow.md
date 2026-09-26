# Project Workflow

> 中文为正文语言，命令与术语保留英文。本文件是任务生命周期的**单一事实源**：plan.md 的「执行约定」
> 只写 track 特有的豁免与参数，通用规则一律以本文件为准，不得在 plan 里重新发明。
> **session 边界、停点、拆分守则也在本文件。**
>
> 本文件分两段：**托管区**（到 `flow:managed:end` 为止，所有项目一致，由 flow 插件下发，
> `/flow:sync` 整段覆盖）+ 文末**项目补充 P1–P6**（本项目的敏感域、层划分、命令、设计源、失败
> 基线、其他规则）。正文里写「P1」「P3」即指文末那一节。
>
> 设计依据：token-router workflow v2.1（2026-08-29 双镜头审计 + 事故复盘）+ 外部对照（Anthropic
> 官方 Claude Code 文档与团队实践、Superpowers 方法论、spec-kit）。一句话：**机制保留，尺寸分级**
> ——按风险三档决定流程重量，不做外部无人做的记账仪式。

## §0 停点表（合法的人工停点只有 5 处）

除此之外一律由 review agent 代拍板，不停下等人（auto mode 尤其）。

| # | 停点 | 形态 |
|---|---|---|
| 1 | **分诊卡** | 一次，三行：档位/车道 + 「做完这段用户能亲手用到什么」+ 本次允许的停点。用户一句话可否决 |
| 2 | **需求访谈** | 最多 3 问，只问用户没说清且会改变实现的；显而易见的不问 |
| 3 | **拍板清单** | 仅四类：设计稿与功能冲突 / 不同修法导向不同产品行为 / 改内核或已上线口径 / 改既有表列 |
| 4 | **立项终点（DoR）** | §3.3，停下汇报 |
| 5 | **敏感域 PR merge** | P1 列出的敏感域，PR 由用户显式合并；合并前建议跑 `/code-review ultra <PR#>` 取得实现 session 之外的独立视角 |

审计 / review agent 报回的 finding **直接修**，不要拿回来问；多个修法时自己选，把理由与被放弃的
选项写进 spec/plan。

## §1 指导原则

1. **Plan 是事实源**：所有工作在 `plan.md` 里跟踪，状态见 §7 的记账口径
2. **技术栈变更先记录**：偏离 `tech-stack.md` 的实现必须先更新文档再动手
3. **测试先行**：先写失败测试再写实现（Red 判定见 §4.2；适用范围与豁免见 §4.5）
4. **每条 AC 一条可跑的检查**：验收锚点是"能跑出通过/失败的东西"（测试、构建、脚本、截图对照），
   不是覆盖率百分比。新代码覆盖率可作参考，**不设阈值**
5. **用户体验优先**
6. **非交互 & CI 友好**：优先非交互命令；watch 型工具用 `CI=true` 保证单次执行

## §2 工作分级与路由

**先分档，再选车道。**档位决定流程重量，车道决定锚点形态。

### 2.1 三档（按风险与不确定性，不按工作量）

| | **一档 小明确** | **二档 中等** | **三档 高风险** |
|---|---|---|---|
| 判据 | 无敏感域；≤2 层（层划分见 P2）；schema 至多纯新增；行为一段话说得清；无视觉不确定 | 跨 ≥2 层或需要多 phase；新页面可按 §3.1 降级；无敏感域；schema 至多纯新增 | 敏感域（P1）、改既有表列、改已上线口径、跨仓契约、或视觉不确定（Lane A） |
| 入口 | `/flow:spec` 或直接修（Lane D） | `/conductor:new-track`（Lane B/C） | `/conductor:new-track`，或设计 → `/flow:design-track` → new-track（Lane A） |
| 产物 | `docs/specs/<x>.md` 一页 + 测试 + PR | spec（≤400 行）+ plan（≤3 phase）+ 基线指针 + 截图 | 全套：spec + plan + baseline + HANDOFF（含 canary）+ `phase<N>-verify/REPORT.md`（Lane A 另加 design/ 四件套） |
| session | 1 | 1（立项 + 实现，`/clear` 分隔；先输出 §3.3 三行交接并得到「继续」） | 立项与实现**分 session** |
| review | PR 前 1 次 code review agent（bug + AC 缺口） | spec 1 镜头；每个**行为** phase 1 次；记账/登记 phase 不审 | spec 2 镜头循环至 PASS（≤3 轮）；plan 1 镜头；每个行为 phase 2 镜头；Lane A 加 `/flow:visual-verify` |
| 验收 | AC 命令全绿；涉 UI 附截图矩阵（P4） | AC 全绿（基线外）；UI 用 `/flow:visual-verify` 模式②/③ | AC 全绿 + P6 要求的兼容性实测（涉 schema）+ HANDOFF canary 单台跑通 |
| 退出 | PR 合并 + worktree 删除 + spec 状态行更新 | + tracks.md `[x]` | + §6 收尾三连 + `blocked_by` 后继确认 + 设计回写（Lane A） |

### 2.2 车道（锚点形态）

- **Q1 不确定性在哪？** 只有「长什么样才对」→ Lane A；只有「怎么改才对」→ Lane B/C；
  都没有（diff 一句话说得清）→ Lane D 直接修。
- **两种都有**（行为/账务要收敛 + 视觉也没定）→ **默认一个 track 分 phase**：先用 Lane B/C 的
  phase 在代码侧收敛并冻结行为，UI phase 排在其后、以已冻结的行为为设计输入。
  **只有当 §2.3 的拆分守则全部满足**（第一段端到端自洽、且第一段本身就交付一条用户可见能力）
  **才拆成两个 track，并且同时立项**。
  > 「行为先做、UI 随后」如果默认必拆、又不规定第二段何时立项，结果就是引擎交付了、用户看得见
  > 的那半截无人认领（真实事故）。所以拆不拆由 §2.3 判定，与"有没有 UI"无关。
- **Lane A 由「视觉不确定」触发，不由「有没有新页面」触发**（降级条款见 §3.1）。

| 车道 | 适用 | 锚点（spec 形态） | 验收 |
|---|---|---|---|
| **A 视觉不确定** | 新交互模式 / 需要先看长什么样才能定 | 设计原型 + design/ 四件套（§3.2） | INVENTORY 逐条 + `/flow:visual-verify` 模式① |
| **B 功能调整** | 行为要变（含新页面按 §3.1 降级、UI 微调） | DELTA 规格：现状 → 目标行为 → **明确不改清单** | TDD + phase gate；UI 用 `/flow:visual-verify` 模式②/③ |
| **C 重构** | 行为不变，结构要变 | 不变量声明 + 测试基线；覆盖薄处 Phase 0 先补 characterization tests | 基线外全绿；涉 UI 时截图 diff 为零 |
| **D 小 bug** | 单点缺陷 | 不开 track：复现测试（Red）→ 修（Green）→ 回归 | 复现测试转绿 + 全量回归 |

### 2.3 拆分守则（任何拆分适用）

1. **先答一句**「做完第一段，用户能亲手用到什么」——答不出、或答案里没有需求原话的主入口 →
   **不拆**，改成一个 track 分 phase。
2. **第一段必须端到端自洽**：从入口（含未登录访客）到目标动作走通。**不得把自洽所需的桥接件**
   （转发路由、意图落盘、回跳等）**删到第二段**。
3. **拆分即同时立项**：拆出的每一段在同一次立项里各建目录、各登记 tracks.md（后者 `[ ]`）。
   **不进 backlog.md**（那是未立项待办池，无人认领）。被阻塞的那段，描述行**以
   `⛔ blocked_by: <前一段 track_id>` 开头**。
   > `blocked_by` 是**人读/模型读的文本约定，conductor 插件不解析它**。因此两条纪律：
   > ① `/conductor:implement` 自动选题时（"取第一个非 `[x]` 的 track"）**必须跳过**描述行以 `⛔`
   > 开头且其前置 track 尚未 `[x]` 的条目；② 解除由**前一段的 `/flow:closeout`** 负责——收尾时把
   > 后继条目描述行的 `⛔ blocked_by: …` 整段删掉（§6 第 2 步），删了才算收尾完成。
4. **派生 track 免重走采访**：第二段的 spec 允许「契约引用型骨架」——依据 = 前一段 spec §FR-x
   （**引用不复制**）+ 本段自己的 FR / AC / 明确不改清单。需求只采集一次；前一段合并后只核对
   被引用 FR 的 Rev 号有无变化。
5. **拆分声明**：第一段 spec 必须含一节 `合并后用户能做：…（至少一条用户可见能力）/ 还不能做：…
   （由 <第二段> 交付）`，并在每次汇报里重复这两行。

**Lane D 三条纪律**：
- **one-shot first**：先试一把全自动；连改两轮改不动 → 重开会话重述问题，胜过继续修补。
- **敏感域**：P1 列出的领域——任何车道碰到都要 review agent 过目，且 **PR 由用户显式合并**
  （§0 停点 5）。不要求人工在线盯着（auto mode 下不可执行）。
- **升级判据（D→B）**：跨 ≥2 层、涉 schema、或发现是类别性问题 → 升级开 track。**文件数不作判据。**

**教训归档顺序**（修完之后）：
- **代码类**：能进 **hook** 就进 hook（确定性强制）——本项目的保护路径 / 禁止整文件重写 / 敏感
  路径 / 保存即格式化写进 `.claude/flow.json`，flow 的 hook 会读；硬禁止用 `permissions.deny`
  → 其次 **skill**（项目 `.claude/skills/`，如高危域陷阱全文放 `domain-traps`）→ 最后才 CLAUDE.md
  （高频规则）；错字级不留痕。
- **流程类**：**所有项目都适用的** → 提到 flow 插件仓库（改托管区模板，发版后各项目 `/flow:sync`）；
  **只属于本项目的** → 本文件「项目补充」。memory 只留指针，不留正文。

> ⚠ **改项目自己的 hook / settings.json 的人必读**：`.claude/settings.json` 与
> `${CLAUDE_PROJECT_DIR}` 锚定 **session 启动时的目录**（走 `EnterWorktree` 就是主 checkout），
> 进 worktree 后不跟着走。所以在 worktree 分支上新增/修改的项目 hook 脚本**在合并前不生效**，
> 合并进 main 后对所有新 session 一次性全量生效。**因此：hook 改动必须在分支上手工喂 stdin JSON
> 验证**（正例 + 反例各一），把命令与输出贴进 PR 描述；合并后第一个 session 里再复验一次真实触发。
> flow 插件自带的 hook 不受此影响（随插件版本生效），但它读的 `.claude/flow.json` 同样取自
> session 启动目录。

## §3 Track 生命周期

```
[Lane A] /flow:design-push → 在自己的 Claude Design 副本里画 → /flow:design-pull <feature> 拉回设计真相源（P4）
       → /flow:design-track 快照入仓 → /conductor:new-track → §3.3 立项终点
       → /conductor:implement → phase gate（review agent + /flow:visual-verify）→ §6 收尾
[Lane B/C] spec 先行 → /conductor:new-track → 同上（无设计输入，或 §3.1 降级形态）
```

### 3.1 设计输入的适用与降级

track 含**视觉不确定**的 UI → Lane A 全量四件套（§3.2）。其余两种降级形态：

- **新页面降级（Lane B）**——三条**同时**满足：① 视觉只用设计真相源（P4）既有 token 与既有
  组件语法，零新造颜色/字体/圆角/阴影；② 无新交互模式（无多步向导、拖拽、表单状态机）；
  ③ 页面结构与文案能在 spec 里逐字给出。满足则 **spec 内嵌「结构清单 + 逐字文案 + 状态」代替
  四件套**，验收 = `/flow:visual-verify` 模式③。分诊卡里写明降级理由，用户一句话可否决。
  典型：营销落地页、文档型内容页、复用既有表格语言的只读管理页。
- **UI 微调降级**：线上现状截图当 baseline（**动手前**截）+ DELTA 说明，验收 `/flow:visual-verify` 模式②。

纯后端 track 豁免设计输入。

### 3.2 Design Input Stage（Lane A）

- **来源**：设计真相源目录（P4；flow 设计模块默认 `design-system/`）。多人协作、云端 push/pull、
  token 派生关系一律见该目录的 `SYNC.md`，本文件不重复；同步用 `/flow:design-push` /
  `/flow:design-pull`。P4 为「无」的项目：四件套直接写在一个临时目录，用
  `/flow:design-track --from <dir>` 快照（要长期用设计系统就 `/flow:init` 补设计模块）。
- **行为已先冻结时的设计输入**（同一 track 的前序 phase，或按 §2.3 拆出的前一段 track）：把已冻结
  的行为做成 **spec 投影**当 BRIEF「输入材料表」——页面/模块清单、字段清单 + 真实示例数据、状态
  矩阵、交互规则、硬约束与「明确不设计」清单；交给设计者。已冻结的业务规则预填进 DECISIONS，
  设计阶段只收敛「长什么样」；稿子与规则冲突 → 停下列清单等拍板（§0 停点 3）。
- **四件套**（缺一不立项，`/flow:design-track` 强制校验）：
  - `BRIEF.md` — 背景 + 输入材料表 + 实现约束 + 审计标准
  - `SPEC.md` — 完整设计规格
  - `INVENTORY.md` — 功能穷举；**铁律：全部条目进 spec.md 的 Acceptance Criteria**
  - `DECISIONS.md` — 编号设计决策，实现不得违反
- **随附件**：`tokens.css` + 高保真稿（`.dc.html` 或 `screen-*.html`）+ `assets/`
- 目录名固定 `design/`；入仓后即为**只读立项快照**（flow hook 强制），实现后不回改。

### 3.3 Session 边界与立项终点（DoR）

**立项终点 = spec/plan review PASS + tracks.md 登记 + 立项提交 + 三行交接。** 到此**停下汇报**，
不进 Phase 0。三行交接：

```
现在能用什么：<按需求原话逐条对号；未做的写「未做」>
还缺什么：<含拆分留到下一段的项>
需要你做什么：<拍板 / 部署 / 合并；无则写「无」>
```

**实现在哪个 session：**
- **必须新 session**：敏感域、或 plan ≥ 4 phase、或 spec ≥ 400 行。新 session 从零上下文只靠
  spec/plan 开工——这同时是对 spec 独立可执行性的检验。
- **可同 session**：其余情况，但先输出上面三行并得到用户一句「继续」；汇报里注明「按 §3.3 同 session」。

**spec 体积上限 400 行**：超了说明该拆 phase 或拆 track，不是写更长。spec review **轮数上限 3**，
第 3 轮仍 FAIL → 把冲突清单交用户（§0 停点 3）。「逐字精确」的要求只适用于**用户可见文案、
账务公式、API 契约**；内部实现细节写「实现方自选，写进 plan」。

## §4 标准任务流

### 4.1 生命周期（每个任务）

1. **选任务**：按 plan.md 顺序取下一个可做任务
2. **标记进行中**：`[ ]` → `[~]`
3. **写失败测试（Red）**：运行并确认失败后才继续
4. **实现到通过（Green）**：写最小实现让测试转绿
5. **重构**（可选）：测试保护下清理，重跑保持绿
6. **记录偏离**：实现偏离 tech-stack.md → 停手，先更新文档（附日期说明）再继续
7. **提交代码**：conventional commit（§8.3），描述用英文；**任务勾 `[x]` 与代码同一提交**
8. **phase 末一次记账**：该 phase 全部任务的 SHA 一次回填 + 一条 `conductor(plan):` 提交

> 不做逐任务 `git notes`、不做逐任务单独记账提交（无消费者：`/flow:catchup`、
> `/conductor:implement`、review agent 都不读 notes；检查点报告的正式载体是
> `phase<N>-verify/REPORT.md`）。想附摘要就写进 commit body。

### 4.2 Red 判定（成文规则）

**编译失败与断言失败任一即为有效 Red**——新函数尚不存在时编译/类型检查报错（如 Go 的 build
failure、TypeScript 的类型错误）而非断言失败，同样算 Red。禁止为了"看到断言失败"先写空实现。

### 4.3 失败基线（成文规则）

**二/三档（track）**：立项时把 `origin/main` 上的既有失败测试记进 `baseline.md`（命令 + 失败
清单），plan「执行约定」写指针即可。

**一档（`/flow:spec` 或 Lane D）**：不建 `baseline.md`，但同样适用基线豁免——动手前在 `origin/main`
（或分支起点）跑一次相关测试命令，把当时的失败清单贴进 PR 描述或规格的 AC 段；没跑就默认沿用
P5 记录的常驻失败基线。

此后所有"全绿"= **基线外全绿**；基线是唯一豁免项，不负责修复基线内失败（除非目标就是修它）。
基线为空时明写"基线：无"。

### 4.4 纯文档/流程任务豁免

无行为变更的任务（文档、注释、记账）**不套 RED-GREEN**，但必须在 plan 执行约定里声明，
且验收标准可执行（能跑的命令、能核对的清单）。

### 4.5 TDD 适用范围与豁免（成文规则）

**先写失败测试是默认**，以下三类可豁免，但每类都必须换成一个**别的**可跑检查——豁免的是
RED-GREEN 的节奏，不是"不用验证"（§1.4）：

| 情形 | 豁免什么 | 换成什么 |
|---|---|---|
| 纯展示型前端（页面布局、文案、样式，无新逻辑分支） | 不要求先写失败测试 | `/flow:visual-verify` 截图矩阵（模式②/③）+ 已有组件测试不劣化 |
| 配置 / 常量 / 迁移登记（新增 option、注册路由、迁移列表） | 不要求先写失败测试 | 一条断言"注册后可读到"的冒烟测试，或明确的手工核对命令 |
| 纯文档 / 记账（§4.4） | 整个 RED-GREEN | 可执行清单 |

**不得豁免**：任何计算、判定、状态流转、账务、鉴权、数据读写——哪怕只有三行。拿不准就写测试。
豁免要在 plan 的「执行约定」里逐条声明（一档写进规格的 AC 段）。

### 4.6 敏感域测试冻结（成文规则）

敏感域 track 的 RED 测试由**立项 session** 写好并随立项提交（断言集即冻结）；实现 session
只让其转绿，**不得修改既有断言**——确需改动（含放松匹配、删断言、跳过用例）必须在 §3.3
汇报里单列理由并等确认。依据：「写代码的 agent 同时在改自己的关卡」是 agent 产码的高频
作弊面（放松断言 / 吞错误 / no-op 修复）；三档本就立项/实现分 session（§3.3），此规则边际
成本≈0。非敏感域不强制。

## §5 Phase 完成协议

**适用范围：只有含行为变更的 phase 走 review agent。** 判据是**这个 phase 有没有产出代码或测试**：

- **免审**：只做记账/登记的 phase——存档失败基线（`baseline.md`）、tracks.md 登记、建 worktree、
  开 PR。用可执行清单自检即可。
- **必审**：任何写了代码或测试的 phase，**包括 Lane C 用来钉住现状的 characterization tests
  Phase 0**——它是重构车道唯一的安全网，恰恰不能跳过（别因为它也叫"Phase 0 基线"就归进免审）。
- **并入相邻 phase 审**：纯文档 / HANDOFF 属无测试区域，必须审，但并进相邻实现 phase 的同一次
  review，不单开。

1. **圈定范围**：`git diff --name-only <上一检查点SHA>..HEAD`（首个 phase 用 track 起点）
2. **自动化门禁**：范围内测试全绿（基线外）+ lint，最多 2 轮修复尝试
3. **review agent 验收**：独立上下文，输入 = spec 的 FR/AC + phase diff。
   **只报影响正确性或 spec 明列要求的缺口**；风格意见、记账格式（SHA/notes/措辞）**不在范围内**
   ——一个被要求找问题的 reviewer 总能找到问题，追每一条会导致过度工程。
   verdict 以 `(review agent PASS)` 或 `(review agent FAIL→fix <sha>→PASS)` 内联留痕在 plan.md
   的 meta-task 行；报告存 `phase<N>-verify/REPORT.md`。用 `flow:phase-gate-reviewer` 这个
   agent（镜头与判据已固定，不要每次手写 prompt）；spec/plan 审阅用 `flow:spec-reviewer`。
   **复核轮只在 MAJOR 未闭环时进行**；MINOR 修完直接 PASS 留痕。
4. **UI phase 附加**：`/flow:visual-verify`（模式见该 skill）。**verdict=needs_work 阻断 phase 完成**，
   与 review agent 同级
5. **检查点提交**：verdict PASS 后 commit，plan.md 记检查点 SHA
6. **汇报**：每个 phase gate 后按 §3.3 的三行格式向用户汇报（能用什么 / 缺什么 / 需要你做什么）。
   SHA、Rev、review 轮次只进 plan.md 与报告文件，**不进汇报正文**。

**review 预算**（与 §2.1 一致，超了说明 phase 切太碎或 spec 太长）：二档 = spec 1 次 + 每个行为
phase 1 次；三档 = spec ≤3 轮 + plan 1 次 + 每个行为 phase 2 镜头。**复核轮只算未闭环 MAJOR 的那次**，
MINOR-only 的复核不做也不计。

## §6 Track 收尾协议

merge 后**立刻**执行，不留尾巴（可用 `/flow:closeout`）：

1. `gh pr merge --delete-branch` + `git worktree remove <path>` + `git branch -d <branch>`
   （worktree 不删会堆积依赖目录；停在已合并分支上继续干活会堆出孤儿改动）
2. tracks.md 该条目 → `[x]`；**若有条目的描述行以 `⛔ blocked_by: <本 track>` 开头，把这段前缀
   删掉**（它现在可以被 `/conductor:implement` 选中了）。删了才算收尾完成
3. **叠链 PR**：开始合并前先把后续 PR 全部 `gh pr edit --base main`——否则删 base 分支时
   GitHub 会直接**关闭**（而非重定向）叠在上面的 PR
4. **UI track 附加——设计回写**：实现过程中发生的 token / 组件演化必须已在**同一 PR** 里落回
   设计真相源（P4）；收尾时提醒各协作者 `/flow:design-push` 把更新同步到各自云端副本
5. 归档决策：track 目录保留原地（默认）；superseded 时在 metadata 记 `superseded_by`
6. **合并后汇报**：§3.3 三行格式

## §7 Bookkeeping 口径

- **状态真相源 = tracks.md 的 `[ ]/[~]/[x]` + plan.md 复选框计数**，仅此两处。
- **metadata.json 的 `status` 字段不维护、不读取**。metadata 只承载 track_id / decisions /
  supersedes 等不随进度变化的元数据。
- **tracks.md 只登记有目录 + spec/plan 的 track**（派生 track 的骨架 spec/plan 满足此条件）；
  想做但未立项的条目进 `conductor/backlog.md`（不被 implement/status 解析）。状态标记只允许
  `[ ]/[~]/[x]`，superseded 用 `[x]` + 描述行注明（flow hook 强制）。
- tracks.md 每节前置一个 `---` 分隔符（含首节）：`^## ` 计数 == `^---$` 计数（flow hook 强制）。
- **插件覆盖声明**（conductor 插件与本文件冲突时以本文件为准）：忽略 `implement` 的
  archive/delete 归档提示；`metadata.status` 只写不读；plan 里的 phase meta-task 一律写作
  `Task: Conductor - User Manual Verification '<Phase>'`（保持插件可解析），语义按 §5 执行。

## §8 质量门禁、命令与提交规范

### 8.1 质量门禁（任务完成前逐项核对）

- [ ] 测试全绿（基线外）
- [ ] 每条 AC 至少一条具名测试或可跑检查
- [ ] 符合 `conductor/code_styleguides/` 与 `.claude/rules/`
- [ ] 公开函数有文档
- [ ] 无 lint / 静态分析错误
- [ ] 相关文档已更新
- [ ] 无新增安全隐患

### 8.2 常用命令

见 **P3**（依赖 / 构建 / 测试 / lint / dev server / 提交前预检）。

### 8.3 提交规范

`<type>(<scope>): <description>`，type ∈ feat / fix / docs / style / refactor / test / chore，
描述用英文。conductor 记账提交用 `conductor(plan):` / `conductor(track):` 前缀。

### 8.4 Definition of Done

1. 代码按 spec 实现完毕
2. 单测就位且通过（或 §4.4 豁免已声明）
3. 每条 AC 有具名测试或可跑检查
4. lint / 静态分析通过
5. plan.md 有实现备注与 SHA 回填（phase 级）
6. 提交信息规范
7. 按 §3.3 三行格式汇报过
