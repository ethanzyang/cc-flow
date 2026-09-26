# 设计系统协作规范

> Claude Design 的设计系统项目是**账号私有**的，不同账号之间无法共享。所以用 git 当合流点：
> **本目录是唯一真相源，每个人的 Claude Design 项目只是个人工作副本。**
> 推送 / 拉回用 `/flow:design push` / `/flow:design pull`，本文是它们背后的规矩。
> 本项目特有的内容（目录职责、token 派生关系、已知缺口）在文末「项目补充 D1–D3」。

## 0. 一句话规矩

**在 Claude Design 里改的东西，当天必须拉回本目录并开 PR。没拉回来的改动等于没发生。**

云端项目不是备份：账号里的项目会丢（真实事故：整个共享设计系统项目从账号里消失，只活在云端的
预览卡片和改版前快照永久丢失，能救回来的只有当初拉回仓库的那部分）。

---

## 1. 谁是真相源

| 层 | 位置 | 谁能改 |
|---|---|---|
| **设计真相源** | 本目录 | 设计改动只在这里落地 |
| 个人工作副本 | 各自的 Claude Design 设计系统项目 | 随便画，但改完要拉回来 |
| 生产实现 | 见 D2 | 从真相源派生，不反向定义 |
| 历史快照 | `conductor/tracks/*/design*/` | **只读**（flow hook 强制）——回答"当时按哪版稿实现的" |

---

## 2. 一次性设置（每人各做一遍）

> **只能你本人在自己电脑上、用自己的账号做。** DesignSync 用当前机器上登录的账号、从本机磁盘读
> 文件上传——别人没法替你把设计系统推进你的账号，也没有"共享给同事"的入口。

1. **授权**：Claude Code 里跑 `/design-login`（给 DesignSync 工具授权，不用另配 MCP）。
2. **跑 `/flow:design push`**：首次会列出你账号下可写的设计系统项目，让你选一个或新建。
   新建必须用 `create_project`——设计系统类型在创建时定死，普通项目事后改不成设计系统。
   projectId 写进本目录的 `.project-id`（已 gitignore，因人而异，**绝不提交**），然后全量推送。
3. 在 claude.ai/design 顶部的 `Design system` 下拉里选中它——之后新建的设计项目会自动套这套 token。

> 建好的设计系统在 **Design systems** 标签页，不在 `Projects` 里——后者一直是空的，别以为没建成功。

---

## 3. Push：仓库 → 自己的云端副本（`/flow:design push`）

- **开工前先拉最新主干**，别在旧版本上画。
- **传哪些文件以 git 为准**：`git ls-files <本目录>`，排除 `SYNC.md`（仓库协作规范，不进云端）；
  `.project-id` 被 gitignore，天然不在列表里。不手写目录清单——手写清单会随新设计包过时。
- **用 `localPath` 从磁盘上传**，不用 inline `data`——字体动辄几 MB，走 inline 会撑爆上下文。
- **分批**：单次请求超过约 1MB 常失败（`Proxy connection ended before receiving CONNECT response`）。
  大文件（字体）各自单独一批，其余凑成每批 < 1MB、≤ 256 个文件；失败原样重试一次通常就过。
  一个 `planId` 可复用于多次 `write_files`，拆批不用重新 finalize。
- **预览卡片**：`preview/*.html` 每个文件**首行**必须是 `<!-- @dsCard group="…" -->`，
  Design System 面板靠它建卡片索引；缺了面板会显示 "This design system is empty"。
- **传完核对**：`list_files` 与 git 列表逐行比对。git 有、云端没有 = 漏传，补传；云端多出
  `_ds_manifest.json` 之类平台自动生成的文件，忽略。

---

## 4. Pull：云端副本 → 仓库（`/flow:design pull`）

**只拉你实际改过的文件，不要整树同步。** 写回走 worktree 分支 + PR（主 checkout 只读）。

### 4.1 拉回一个 feature 设计包（由 `/flow:design-track <feature>` 在立项时完成）

1. **命名约定**：云端项目里的 feature 文件夹名 = 本目录下的 `<feature>/`（小写下划线，如
   `usage_export`）。**在云端开画时就按这个名字建文件夹**，拉回时零改名。
2. **齐装** = 四件套（`BRIEF.md` / `SPEC.md` / `INVENTORY.md` / `DECISIONS.md`）+ `tokens.css` +
   高保真稿（`*.dc.html` 或 `screen-*.html`）+ `assets/`。四件套缺件的先在云端补齐——
   `/flow:design-track` 会拒绝缺件的包。
3. 设计包与 track 快照、spec/plan 进**同一个立项 PR**；设计过程动了公共 token 就按 §5 先拆出单独 PR。

### 4.2 硬限制

- **`get_file` 单文件上限 256 KiB**，超过的拉不回来。高保真稿超限 → 让云端把单文件稿拆成多个
  `screen-*.html`（顺带更利于 review），或走 claude.ai 的项目导出 ZIP 只补这一个文件。
- **字体与二进制资源是 push-only 的**——仓库对它们永远权威，不要从云端拉回。首次在云端生成的
  二进制资源（logo、字体）用 claude.ai 项目导出 ZIP 解压进本目录。
- **没有批量导出**，一次一个文件——所以"改完立刻拉回"比"月底整体同步"现实得多。

### 4.3 SVG 会被重新序列化

平台的解析器会把自闭合标签展开（`<rect …/>` → `<rect …></rect>`），拉回来的 SVG 会比原文件大
十几字节，**语义完全相同**。diff 只有这个就丢弃这次改动，别提交噪音。

---

## 5. 多人怎么不打架

- **合流点是 git，不是云端。** 各人 push 到自己的项目，谁都不会覆盖对方——冲突只会在 PR 里出现，
  由 git 正常解决。
- **开工前拉最新主干再 push 到自己的项目。** 跳过这步就是在旧版本上画，拉回来时会把别人的改动覆盖掉。
- **同一个文件别多人同时改。** 设计稿是大段 HTML，git 自动合并的结果通常没法看。动手前打个招呼。
- **改 token 影响所有人**：token 文件（D1 里标出的）的改动单独开 PR，不要夹在页面改动里。

---

## 6. Track 收尾时的设计侧动作（对接 workflow §6）

1. **token / 组件演化随实现 PR 落回本目录**——不是收尾后补。有 token 镜像测试的项目（D2）会直接
   拦住漂移；页面稿 / 组件类的演化没有测试钉住，靠 review 时对照 PR diff 检查本目录是否同步。
2. **merge 后各人 `/flow:design push`** 把更新推到自己的云端副本——否则下次在旧稿上画，拉回来会
   覆盖别人的改动（§5 第 2 条的事故路径）。
