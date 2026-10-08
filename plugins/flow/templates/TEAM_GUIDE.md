# 开发指南（flow 工作流）

> 5 分钟上手。本文是**导览**，规则原文在 **`conductor/workflow.md`**（托管区 + 文末「项目补充」），冲突时以它为准。

## 0. 装好工具

- clone 仓库后用 Claude Code 打开并**信任该目录**，会提示安装 `flow@cc-flow` 与 `conductor@conductor-cc` 两个插件——
  都装上（flow 插件仓库是私有的，本机 `gh auth login` 过即可）。
- 依赖：`jq`（缺了 flow 的 hook 全部失效，SessionStart 会提示）、`python3`（Bash 守卫与 JSON 检查）、`gh`。
- 截图用浏览器自动化（Playwright MCP 或 Claude in Chrome）。
- 启用了设计模块（有 `design-system/SYNC.md`）：一次性 `/design-login` + `/flow:design push`。

## 1. 一张图

```
你的想法 ──/flow:triage──▶ 分诊卡 ──你说「做」──┬─ 一档：/flow:spec ── 一个 PR ──────────────┐
                │                               │                                        │
          讨论模式只出方案                        └─ 二/三档：/conductor:new-track（spec + plan）│
                                                     → 立项确认 → /conductor:implement       │
                                                     一片一个 PR：测试先行 → check → PR       │
                                                                                            ▼
                  合并（三档的单向门片由你合并）─▶ /flow:closeout 部署 + 冒烟 + 清理 ─▶ 你去试 ─▶ 下一片
```

- **分诊卡**：档位 / 车道与设计输入 / 第一片做完你能 / 切片 / 这次不做 / 胃口（值得花多少时间）/ 怎么验收。
- **三档**：错了 revert 就没事、一个 PR 做得完 → 一档；要多片 → 二档；收不回来的（动钱、记账口径、密钥、数据迁移、
  审批守卫，见 workflow P1）→ 三档。不按层数、文件数分。
- **一片**：plan 的一个 phase = 一个 PR，非测试代码约 ≤400 行，从入口到结果端到端能用，能单独上线。不按层切。
- **审阅**：一档有逻辑的审 1 次；二档整个 track 做完审 1 次；三档写代码前审 spec 1 次 + 动钱那片合并前审 1 次。
  只有 BLOCKER（按后果定）必须修。

## 2. 命令速查

| 命令 | 用途 |
|---|---|
| `/flow:triage` | 出分诊卡；也用于「我要方案 / 先研究」 |
| `/flow:spec` | 一档：一页规格 → 实现 → PR |
| `/conductor:new-track` | 二/三档立项：spec + plan（phase = 能上线的片） |
| `/conductor:implement` | 按 plan 一片一片做（任务流与 phase 收尾按 workflow §4 / §5） |
| `/flow:closeout` | 每片合并后：部署 + 冒烟 + 清理 + 请你试；track 最后一片触发整体审阅 |
| `/flow:catchup` | `/clear` 或新会话后接上进度 |
| `/flow:design-track` | 视觉没定的新界面：写 BRIEF 给你画 → 拉回设计包、接进立项 |
| `/flow:design push` / `pull` | 仓库设计系统 ⇄ 自己的 Claude Design 副本 |
| `/flow:visual-verify` | 截图矩阵验收（对设计稿 / 对现状 / 对 spec 清单），按需 |
| `/flow:stats` | 看度量：PR 时长、大小、审阅次数、文档提交占比 |
| `/flow:init` | 接入新项目（含 conductor 产品定义访谈）；插件升级后同步托管区 |

审阅代理：`flow:phase-gate-reviewer`（代码审阅，按 workflow §6 的次数）、`flow:spec-reviewer`（三档写代码前审 spec）；
`flow:security-reviewer`、`flow:architecture-reviewer` 点名时才用。

Claude Code 内置：`/code-review`、`/simplify`、`/rewind`、`/context`、`/clear`。

## 3. 什么时候 `/clear`

| 场景 | 做法 |
|---|---|
| 换一个不相关的任务 | `/clear` |
| 同一个 track 连续做 | 不用清；上下文吃紧时 `/clear` + `/flow:catchup` |
| 同一问题纠正两次仍不对 | `/clear`，带着教训写一个更具体的开头重来 |
| 三档开始实现 | 新 session（或新 agent）只拿 spec / plan 开工 |

## 4. 反模式

| 反模式 | 正确做法 |
|---|---|
| 你在问方案，模型先改了代码 | 讨论模式只出方案，以分诊卡收尾 |
| plan 按层切（先 core、再 api、最后页面） | 竖切：第一片就让你能用上一点 |
| 每个 phase 都审、审到 PASS 为止 | 一个改动审一次；只修 BLOCKER |
| spec 写几百行、逐条核实行号 | spec ≤200 行；三档只写不变量、公式、失败模式与契约 |
| 立项单独开 PR、做完再开记账 PR | 立项文件跟第一片的 PR，`[x]` 跟最后一片 |
| 手写推测的外部接口 fixture | 从真实只读接口 / testnet 录制 |
| 停在某个点上等你，却不通知 | 等你就发通知 |
| 你说「太慢」，模型只记进 memory | 当天改 workflow.md（流程类教训的唯一去处） |
| 在主 checkout 上直接改 | 走 worktree（hook 会拦） |

## 5. 常见坑

| 坑 | 一句话 |
|---|---|
| 在 main 上改文件被拦 | 设计如此：先 `EnterWorktree`；要改保护规则去 `.claude/flow.json` |
| check 有一个红，跟我无关 | 在主干上复跑确认是既有失败，写进 PR 描述（P5） |
| tracks.md 改完被 hook 报错 | 每节前一个 `---`（含首节），状态只许 `[ ]` / `[~]` / `[x]` |
| 改了项目 hook 却不生效 | 项目 settings / hook 锚定 session 启动目录，worktree 分支上的改动合并后才生效 |
| workflow.md 托管区想改 | 别在项目里改——提到 flow 插件仓库发版，再 `/flow:init` |
| 截图主题不对 | 页面默认跟系统偏好，首张截图前显式设置主题 |
| Claude Design 显示 "This design system is empty" | `preview/*.html` 首行缺 `<!-- @dsCard group="…" -->` |

## 6. 新人 checklist

- [ ] 装好两个插件，开一个新 session，确认开场提示「本仓库启用 flow 工作流」
- [ ] 读 `conductor/workflow.md`，重点看文末项目补充（P1 单向门、P2 上线、P3 命令）与 `conductor/product.md`
- [ ] 在 worktree 里跑通一次 P3 的 check
- [ ] 拿一个小需求走一遍：`/flow:triage` → `/flow:spec` → `/flow:closeout`
