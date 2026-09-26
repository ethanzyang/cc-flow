---
name: design-push
description: 把仓库里的设计系统目录推到你自己的 Claude Design 设计系统项目（个人云端副本）；首次使用时帮你选/建项目并记下 .project-id。开画前、或设计改动合并后同步云端时由用户手动运行。
disable-model-invocation: true
---

仓库是设计的唯一真相源，云端项目只是个人副本。规矩全文在设计目录的 `SYNC.md`（§2 一次性设置、
§3 push），这里是执行步骤。

## 0. 前置

- 设计目录 = `.claude/flow.json` 的 `design.dir`（下文 `<D>`，路径相对**主 checkout**）。没有这个
  字段 → 本仓库还没启用设计模块，提示用户跑 `/flow:init` 补设计模块，结束。
- 在主 checkout 上 `git fetch -q && git pull --ff-only`（有远端时）——**别在旧版本上推**。推送只读
  磁盘，不改仓库，主 checkout 只读的规矩不受影响。
- DesignSync 报未授权 → 请用户跑 `/design-login` 后再来。

## 1. 确定目标项目

读 `<主 checkout>/<D>/.project-id`：

- **有** → `DesignSync(get_project, projectId)` 确认 `type` 是设计系统且 `canEdit`，继续。
- **没有（首次）** → `DesignSync(list_projects)` 列出用户可写的设计系统项目，让用户选一个，或新建：
  `DesignSync(create_project, name="<项目名> Design System")`（必须 create_project——类型创建时定死，
  普通项目事后改不成设计系统）。把 projectId 写进 `<D>/.project-id`（已 gitignore，**绝不提交**；
  flow 的 hook 对被 gitignore 的文件不做只读拦截）。

## 2. 列清单

```bash
git -C "<主 checkout>" ls-files "<D>" | grep -v "^<D>/SYNC.md$" | sed "s|^<D>/||"
```

以这份 git 清单为准，不手写目录。同时检查 `preview/*.html` 首行是不是 `<!-- @dsCard group="…" -->`，
缺的列出来提醒用户（不自动改）。

## 3. 定计划

`DesignSync(finalize_plan, projectId, localDir="<主 checkout>/<D>", writes=[...], deletes=[])`：
`writes` 放根目录文件的精确路径 + 每个顶层子目录一条 `"<子目录>/**"`（通配只是授权范围，实际上传
由 `write_files` 的 `files` 决定）。**不删云端文件**，除非用户明确要求清理。

## 4. 分批上传

- 每个文件 `{path: "<相对路径>", localPath: "<相对路径>"}`——**只用 localPath**，不用 inline data。
- 按文件大小分批（`wc -c`）：> 800KB 的（通常是字体）各自单独一批；其余凑成每批 < 1MB 且 ≤ 256 个。
- 同一个 `planId` 连续 `write_files`；某批报 `Proxy connection ended…` 就原样重试一次，仍失败记下来继续
  下一批，最后汇总。

## 5. 核对

`DesignSync(list_files, projectId)` 与第 2 步清单逐行比：git 有、云端没有 = 漏传 → 补传。云端多出的
`_ds_manifest.json` 等平台文件忽略。

## 汇报

```
已推送：<n> 个文件（<批数> 批）到 <项目名>；漏传 <0 | 清单>；预览卡片缺 @dsCard：<无 | 清单>
首次设置时再加一句：到 claude.ai/design 顶部 Design system 下拉选中它（在 Design systems 标签页，不在 Projects）
```
