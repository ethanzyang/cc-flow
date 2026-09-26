# cc-flow — flow 工作流插件的源码仓库

一个 marketplace（`.claude-plugin/marketplace.json`）+ 一个插件（`plugins/flow/`）。使用说明见 README。

## 命令

- 测试：`bash tests/lint.sh && bash tests/hooks.test.sh`
- 校验：`claude plugin validate ./plugins/flow && claude plugin validate .`
- 本地加载：`claude --plugin-dir ./plugins/flow`

## 规则

1. **改了 `plugins/flow/` 下任何会被用户拿到的东西就要发版**：`plugin.json` 的 `version` 加一 +
   `plugins/flow/CHANGELOG.md` 一条。不加 version，已安装的项目拿不到。
2. `templates/workflow.md` 是所有项目的规则正文（托管区）。只放**所有项目都适用**的规则；项目特有的
   东西一律用「P1–P6」指针指向项目补充，不许把某个项目的路径、命令、事故细节写进来。
3. hook 脚本只用 bash 3.2 语法（macOS 自带）：不用关联数组 / `mapfile` / `${x,,}`。
   **`$var` 后面紧跟中文必须写成 `${var}`**——bash 3.2 会把中文字节当成变量名的一部分，
   `set -u` 下直接 unbound variable（`tests/lint.sh` 会查）。
4. hook 必须「未启用即放行」：没有 `.claude/flow.json` 的仓库一律 `exit 0`、无输出。
5. 改 hook 行为 → 在 `tests/hooks.test.sh` 加正例 + 反例；循环里要 `exit` 的用 heredoc 喂数据，
   不用管道（管道开子 shell，exit 出不去）。
6. `init-project.sh` 只建缺失文件、从不覆盖；settings 合并保序去重、不删用户已有条目。
