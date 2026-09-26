## 设计系统

`{{DESIGN_DIR}}/` 是设计的**唯一真相源**（协作规范 `{{DESIGN_DIR}}/SYNC.md`）。

- 开画前 `/flow:design-push` 把最新版推到自己的 Claude Design 副本；改完**当天** `/flow:design-pull`
  拉回并开 PR——不拉回来等于没改
- token 文件的改动单独开 PR；实现侧镜像 token 的，同一个 commit 镜像（见 SYNC.md 项目补充 D2）
- `conductor/tracks/*/design*/` 是只读历史快照
