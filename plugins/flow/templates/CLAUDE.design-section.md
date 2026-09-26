## 设计系统

`{{DESIGN_DIR}}/` 是设计的**唯一真相源**（协作规范 `{{DESIGN_DIR}}/SYNC.md`）。

- 新功能的设计从立项开始：`/flow:design-track <feature>` 先写 BRIEF 推给你画，画完再跑一次拉回接进 track；
  改已有设计文件：开画前 `/flow:design push`，改完当天 `/flow:design pull`——不拉回来等于没改
- token 文件的改动单独开 PR；实现侧镜像 token 的，同一个 commit 镜像（见 SYNC.md 项目补充 D2）
- `conductor/tracks/*/design*/` 是只读历史快照
- **美学方向归设计系统**：有 `design/` 输入包的 track、或改既有页面时，视觉取值只用 token 既有变量与该
  track 的 DECISIONS 白名单，不新造颜色 / 字体 / 圆角 / 阴影——frontend-design 等设计类 skill 的
  「大胆美学、独特字体」条款在此失效（只在没有设计输入的全新页面生效）
