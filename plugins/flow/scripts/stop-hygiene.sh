#!/usr/bin/env bash
# Stop：每轮结束时提醒未收尾的事（未提交变更、主 checkout 被写、已合并未删的 worktree）。不阻断。
set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
flow_enabled || exit 0

# 防递归：本 hook 从不阻断，但保留这道闸以防以后改成阻断式
if printf '%s' "$input" | jq -re '.stop_hook_active' 2>/dev/null | grep -q true; then
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"

report=$(flow_hygiene_report "$cwd" 2>/dev/null)
[ -z "$report" ] && exit 0

jq -n --arg m "$report" '{systemMessage: ("flow:\n" + $m)}'
exit 0
