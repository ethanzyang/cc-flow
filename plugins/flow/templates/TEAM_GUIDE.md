# 开发指南（flow 工作流）

> 5 分钟上手。本文是**导览**，规则原文在 **`conductor/workflow.md`**（托管区 + 文末「项目补充」），冲突时以它为准。

## 0. 装好工具

- clone 仓库后用 Claude Code 打开并**信任该目录**，会提示安装 `flow@cc-flow` 插件——装上（插件仓库私有的，
  本机 `gh auth login` 过即可）。
- 依赖：`jq`（缺了 flow 的 hook 全部失效，SessionStart 会提示）、`python3`（Bash 守卫与 JSON 检查）、`gh`。
- 截图用浏览器自动化（Playwright MCP 或 Claude in Chrome）。
- 启用了设计模块（有 `design-system/SYNC.md`）：一次性 `/design-login` + `/flow:design push`。

## 1. 一张图

```
你的想法 ──/flow:shape──▶ 定形卡（≤15 行）──你说「做」──▶ /flow:build 一片
                             │                                   │
                       讨论模式只出方案                 测试先行 → check 全绿 → 一轮审阅 → PR
                                                                 │
                     双向门：模型合并 ─▶ /flow:closeout 部署 + 冒烟 + 清理 ─▶ 你去试 ─▶ 下一片
                     单向门：你合并 ──┘
```

- **定形卡**：目标 / 第一片做完你能 / 这次不做 / 胃口（值得花多少时间）/ 门 / 怎么验收 / 切片。
- **一片**：一个 PR，非测试代码约 ≤400 行，从入口到结果端到端能用，能单独上线。不按层切。
- **两类门**：错了 revert 重发就没事 → 双向门（快）；收不回来（动钱、记账口径、密钥、数据迁移、审批守卫，
  见 workflow P1）→ 单向门（spec + 写代码前一轮风险审阅 + PR 终审加安全审阅 + 你合并）。

## 2. 命令速查

| 命令 | 用途 |
|---|---|
| `/flow:shape` | 出定形卡；也用于「我要方案 / 先研究」 |
| `/flow:build` | 实现一片：worktree → 测试先行 → check → 审阅 → PR →（双向门）合并 |
| `/flow:closeout` | 合并后：部署 + 冒烟 + 清理 + 请你试 |
| `/flow:stats` | 看度量：PR 时长、大小、审阅轮数、文档提交占比 |
| `/flow:visual-verify` | 按需的截图矩阵验收（对设计稿 / 对现状 / 对定形卡） |
| `/flow:design-track` | 视觉没定的新界面：写 BRIEF 给你画 → 拉回设计包 |
| `/flow:design push` / `pull` | 仓库设计系统 ⇄ 自己的 Claude Design 副本 |
| `/flow:init` | 接入新项目；插件升级后同步托管区 |

审阅代理：`flow:pr-reviewer`（每个 PR 一轮）、`flow:risk-reviewer`（单向门写代码前一轮）、
`flow:security-reviewer`（单向门 PR 加一轮）。只有 BLOCKER（按后果定）挡合并。

Claude Code 内置：`/code-review`、`/simplify`、`/rewind`、`/context`、`/clear`。

## 3. 什么时候 `/clear`

| 场景 | 做法 |
|---|---|
| 换一个不相关的任务 | `/clear` |
| 同一片连续做 | 不用清 |
| 同一问题纠正两次仍不对 | `/clear`，带着教训写一个更具体的开头重来 |
| 一片很大或是单向门 | 交给一个新 agent / 新 session 做，主会话只收结论 |

## 4. 反模式

| 反模式 | 正确做法 |
|---|---|
| 你在问方案，模型先改了代码 | 讨论模式只出方案，以定形卡收尾 |
| 按层切（先 core、再 api、最后页面） | 竖切：第一片就让你能用上一点 |
| 每段都审、审到 PASS 为止 | 每个 PR 一轮；只修 BLOCKER |
| spec 写几百行、逐条核实行号 | 双向门不写 spec；单向门 spec ≤150 行，只写不变量与失败模式 |
| 手写推测的外部接口 fixture | 从真实只读接口 / testnet 录制 |
| 停在某个点上等你，却不通知 | 等你就发通知 |
| 你说「太慢」，模型只记进 memory | 当天改 workflow.md（流程类教训的唯一去处） |
| 在主 checkout 上直接改 | 走 worktree（hook 会拦） |

## 5. 常见坑

| 坑 | 一句话 |
|---|---|
| 在 main 上改文件被拦 | 设计如此：先 `EnterWorktree`；要改保护规则去 `.claude/flow.json` |
| check 有一个红，跟我无关 | 在主干上复跑确认是既有失败，写进 PR 描述（P5） |
| 改了项目 hook 却不生效 | 项目 settings / hook 锚定 session 启动目录，worktree 分支上的改动合并后才生效 |
| workflow.md 托管区想改 | 别在项目里改——提到 flow 插件仓库发版，再 `/flow:init` |
| 截图主题不对 | 页面默认跟系统偏好，首张截图前显式设置主题 |
| Claude Design 显示 "This design system is empty" | `preview/*.html` 首行缺 `<!-- @dsCard group="…" -->` |

## 6. 新人 checklist

- [ ] 装好插件，开一个新 session，确认开场提示「本仓库启用 flow 工作流」
- [ ] 读 `conductor/workflow.md`，重点看文末项目补充（P1 单向门、P2 上线、P3 命令）
- [ ] 在 worktree 里跑通一次 P3 的 check
- [ ] 拿一个小需求走一遍：`/flow:shape` → `/flow:build` → `/flow:closeout`
