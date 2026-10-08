#!/usr/bin/env bash
# PreToolUse(Bash)：只拦致命、不可逆的命令（删根 / 家目录 / 主 checkout、非测试库 DROP、强推主干、
# 抹盘、删不入库的本地文件……）。判断在 guard-bash.py：按 shell 词法切词、只看真正会执行的命令，
# commit message / heredoc 正文里「提到」的命令不拦。拦截清单见该文件开头。
# 这里只做两件事：未启用 flow 即放行；没有 python3 也放行（守卫是兜底，不该挡住工作）。
# 退出码 2 = 阻断并把 stderr 喂回模型；0 = 放行。
set -u
. "$(dirname "$0")/lib.sh"

flow_enabled || { cat >/dev/null; exit 0; }
command -v python3 >/dev/null 2>&1 || { cat >/dev/null; exit 0; }
exec python3 -I "$(dirname "$0")/guard-bash.py"
