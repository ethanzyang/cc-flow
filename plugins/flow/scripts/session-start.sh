#!/usr/bin/env bash
# SessionStart：给模型一句「本仓库走 flow」的开场上下文 + 未收尾提醒 + 版本漂移检查，
# 顺手把 .env 等本地文件软链进 worktree。开场提醒比收场更可能被执行。不阻断。
set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
[ -f "$FLOW_CFG" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"flow: 本仓库启用了 flow 工作流，但本机没装 jq，flow 的全部 hook（主 checkout 只读、保护路径、记账校验）都失效了。请先安装 jq（macOS: brew install jq）。"}'
  exit 0
fi

printf '%s' "$input" | "$(dirname "$0")/link-worktree.sh" >/dev/null 2>&1 || true

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$FLOW_PROJECT"

warn=""
add() { warn="${warn}${1}
"; }

# 版本漂移：项目里的托管区版本 vs 本机插件版本
pv=$(flow_plugin_version)
wf="$FLOW_PROJECT/conductor/workflow.md"
if [ -f "$wf" ]; then
  mv=$(sed -n 's/.*flow:managed:begin v\([0-9][0-9.]*\).*/\1/p' "$wf" | head -1)
  if [ -z "$mv" ]; then
    add "⚠️  conductor/workflow.md 没有 flow 托管标记——跑 /flow:init 查看如何接入。"
  else
    case $(flow_ver_cmp "$mv" "$pv") in
      -1) add "⚠️  conductor/workflow.md 托管区是 v${mv}，本机 flow 插件已是 v${pv}：在 worktree 里跑 /flow:init 同步。" ;;
      1) add "⚠️  conductor/workflow.md 托管区是 v${mv}，比本机 flow 插件 v$pv 新：先 /plugin marketplace update cc-flow 再 /plugin update flow。" ;;
    esac
  fi
else
  add "⚠️  缺 conductor/workflow.md（flow 规则正文）：跑 /flow:init。"
fi

command -v python3 >/dev/null 2>&1 || add "⚠️  本机没装 python3，flow 的 JSON 重复键检查不会生效。"

hyg=$(flow_hygiene_report "$cwd" full 2>/dev/null)
[ -n "$hyg" ] && add "$hyg"

ctx="本仓库启用 flow 工作流（插件 v${pv}）：按后果分级，以上线为终点。规则正文 conductor/workflow.md（托管区 + 文末「项目补充」P1–P6）。新需求先 /flow:shape 出定形卡（用户在问方案时只出方案、不写代码）；用户说「做」后 /flow:build 一片一片做；合并后 /flow:closeout 上线。主 checkout 只读、改动走 worktree。流程类教训当天改 workflow.md，不要只记 memory。"
if [ -n "$warn" ]; then
  ctx="$ctx
$warn"
fi

jq -n --arg ctx "$ctx" --arg msg "$warn" '
  {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}
  + (if $msg == "" then {} else {systemMessage: ("flow:\n" + $msg)} end)'
exit 0
