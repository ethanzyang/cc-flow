---
name: init
description: 把 flow 开发工作流接入当前仓库——生成 conductor/ 骨架、规则正文（托管区 + 项目补充）、CLAUDE.md 工作流段、.claude/flow.json 与 settings（插件自动安装 + 权限基线）。用户说「接入 flow」「初始化工作流」「flow init」、或在一个还没有 .claude/flow.json 的仓库里想用 /flow:* 时触发。
---

目标：一次 session 把一个仓库接入 flow，结束时 `doctor.sh` 全过、改动在一个 PR 里。
确定性的部分交给脚本（只建缺失文件、从不覆盖）；需要判断的部分（项目补充、CLAUDE.md、保护规则）
由你调研后用 Edit 填。脚本目录：`${CLAUDE_PLUGIN_ROOT}/scripts/`。

## 0. 前置

- 不在 git 仓库里 → 问用户是否 `git init`（这是唯一需要问的前置）。
- `command -v jq python3 gh`：缺 jq 就停下让用户装（flow hook 全靠它）；缺 python3 / gh 记进汇报。
- 已有 `.claude/flow.json` → 本仓库已接入，改跑 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"`
  报告体检结果，按需引导到 `/flow:sync`，结束。

## 1. 调研（subagent，别占主上下文）

派一个 Explore subagent 返回结论（不要大段代码）：

- **技术栈与命令**：语言/框架/包管理器（看 go.mod、package.json + 锁文件、pyproject、Cargo.toml、
  Makefile、CI 配置里实际跑的命令）→ 依赖 / 构建 / 测试 / lint / dev server / 格式化命令
- **层划分**：目录结构体现的层（如 handler/service/model/web），给判档「≤2 层」用
- **敏感域候选**：计费/支付/鉴权/权限/风控/数据迁移/调度等目录与文件（给出 glob）
- **保护候选**：生成文件、第三方校验文件、有重复键的 JSON（i18n 常见）、vendor 目录
- **UI**：有无前端、主题切换机制、有无设计系统目录
- **既有约定**：已有的 CLAUDE.md / AGENTS.md / .cursorrules / CONTRIBUTING 里的规则
- **主干名**：`git symbolic-ref refs/remotes/origin/HEAD` 或本地 main/master

## 2. 访谈（≤3 问，一次 AskUserQuestion 问完）

只问调研答不了、且会改变接入结果的：

1. **敏感域**：列出调研找到的候选让用户多选/补充（碰到即三档、PR 必须用户合并）——**必问**
2. **产品一句话 + 目标用户**（仓库里没有 README/产品说明时才问）
3. 其余真有歧义的（例如两个候选测试命令不知道用哪个）；没有就不问

## 3. 建工作区

- 仓库**还没有任何提交** → 就地做，最后作为首个提交。
- 已有提交 → `git fetch -q` 后用 **EnterWorktree（名为 adopt-flow）** 或
  `git worktree add -b chore/adopt-flow .claude/worktrees/adopt-flow origin/<主干>`，之后所有写入都在
  worktree 里。接入完成前 flow 的 hook 不会生效（`.claude/flow.json` 还没进主干），这是预期的。

## 4. 跑脚本生成骨架

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" "<工作目录>" --main <主干> \
  --allow 'Bash(<测试命令前缀>:*)' --allow 'Bash(<构建命令前缀>:*)'
```

`--allow` 只放**只读或本地无副作用**的常用命令（测试、构建、lint）。脚本输出每个文件是「已创建」
还是「已存在」；「无标记」「待插入」两类需要你处理（见第 5 步）。

## 5. 填内容（用 Edit，不整文件重写已有文件）

1. **`conductor/workflow.md` 文末 P1–P6**：P1 敏感域（名称 — 路径）、P2 层划分、P3 命令块、
   P4 UI（无 UI 就写「无 UI」）、P5 失败基线（在主干上把测试跑一遍，记下已知失败；全绿写「无」）、
   P6 项目规则（从既有约定里提炼**流程相关**的）。不留（待填）。
2. **`.claude/flow.json`**：
   - `sensitive_paths`：P1 对应的 glob（形如 `*/billing/*`，`*` 可跨目录）
   - `protected_paths`：模板已有 .env / CI；按调研补（每条带 `reason`，会原样回给模型）
   - `no_full_rewrite` / `json_dup_key_check`：有重复键或必须局部编辑的文件（如 i18n locale）；
     `json_dup_key_check.known` 填**当前已存在**的重复键（历史遗留不拦，只拦新增）
   - `format_on_edit`：`{"globs": ["*.go"], "cmd": "gofmt -w \"$FILE\""}`，cmd 在被改文件所属仓库
     根目录执行，文件路径在 `$FILE`
   - `worktree_links`：被 gitignore 但运行必需的本地文件（缺省 `.env`）
3. **CLAUDE.md**：新生成的 → 填 `{{NAME}}` `{{TAGLINE}}` `{{STACK}}` `{{BUILD}}` `{{TEST}}` `{{LINT}}`、
   关键目录、核心规则（从既有约定迁入高频编码规则）。已存在且「待插入」→ 把
   `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.flow-section.md` 的内容（`{{MAIN}}` 换成主干名）插到
   命令段之后，其余不动。
4. **`conductor/product.md` / `tech-stack.md` / `product-guidelines.md`**：按调研与访谈填实；
   没有 UI 的项目 product-guidelines 只写 Content Guidelines。
5. **语言风格指南**（可选）：conductor 插件自带 `templates/code_styleguides/<lang>.md`，
   `find ~/.claude/plugins -path '*conductor*/templates/code_styleguides/<lang>.md' | head -1`
   找得到就拷进 `conductor/code_styleguides/`。
6. 既有 `conductor/workflow.md` 报「无标记」→ 按 `/flow:sync` 第 3 节「旧项目第一次接入」迁移。

## 6. 验收

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" "<工作目录>"
```

必须「结论：通过」；△ 项能处理的处理掉，处理不了的写进汇报。再抽查一条 hook：把
`{"tool_name":"Edit","tool_input":{"file_path":"<主 checkout>/README.md"}}` 喂给
`CLAUDE_PROJECT_DIR=<工作目录> bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-edit.sh"`，
工作目录在主干上时应 exit 2（在 worktree 分支上则 exit 0，说明判定按分支走）。

## 7. 提交与交付

- 提交：`chore: adopt flow workflow`（描述英文）。
- 有 `origin` 且 `gh` 已登录 → 推分支、开 PR，PR 描述列出生成/修改的文件与 doctor 输出。
  没有远端 → 在主干上 `git merge --ff-only chore/adopt-flow` 后删 worktree（本地项目没有 PR 环节）。
- 合并后提醒：**主 checkout 从此只读**；队友 clone 后信任目录即会被提示安装 flow 与 conductor。

## 汇报（三行）

```
现在能用什么：本仓库已接入 flow——/flow:triage 分诊、主 checkout 只读、合并后 /flow:closeout；敏感域 <n> 条已登记
还缺什么：<doctor 的 △ 项 / 访谈里没定的 / 无>
需要你做什么：合并 PR #n（合并后新开一个 session，开场应看到「本仓库启用 flow 工作流」）
```
