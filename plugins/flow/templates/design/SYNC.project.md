
# 项目补充（本段属于本项目，`/flow:sync` 不会改动）

### D1 目录职责

| 路径 | 内容 |
|---|---|
| `README.md` | 设计系统总纲，同时是喂给 Claude Design 的 guide 原文——改它等于改 AI 的设计行为，慎重 |
| `SYNC.md` | 本文（仓库协作规范，不进云端） |
| `.project-id` | 你自己的 Claude Design 项目 id（gitignore，因人而异） |
| （待补：token 文件、`fonts/`、`assets/`、`preview/`、各 feature 设计包） | |

### D2 token 派生关系

<!-- 实现侧若镜像本目录的 token（如 web/src/styles/tokens.css），写清：源文件 → 镜像文件、唯一允许
     的差异（如字体路径前缀）、钉住它的测试、需要从格式化里豁免的文件（否则格式化会破坏字符级一致）。
     建议给镜像加一条字符级比对测试：改一边不改另一边会红。没有镜像就写「无」。 -->
- 无

### D3 已知缺口

- 无
