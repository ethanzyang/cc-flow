#!/usr/bin/env bash
# 体检：一个仓库的 flow 接入是否完整。✗ = 会让流程或 hook 失效；△ = 建议处理。任一 ✗ → 退出码 1。
# 用法：doctor.sh [项目目录]
set -u
. "$(dirname "$0")/lib.sh"

proj="${1:-$FLOW_PROJECT}"
proj=$(cd "$proj" && pwd) || exit 1
bad=0
y() { echo "  ✓ $1"; }
n() { echo "  ✗ $1"; bad=1; }
w() { echo "  △ $1"; }

echo "工具"
for t in git jq; do command -v "$t" >/dev/null 2>&1 && y "$t" || n "$t 未安装（flow hook 依赖它）"; done
command -v python3 >/dev/null 2>&1 && y python3 || w "python3 未安装：JSON 重复键检查不生效"
command -v gh >/dev/null 2>&1 && y gh || w "gh 未安装：/flow:closeout 的 PR 操作要手工做"

echo "配置 .claude/flow.json"
cfg="$proj/.claude/flow.json"
if [ ! -f "$cfg" ]; then
  n "不存在（flow hook 对本仓库不生效）"
elif ! jq -e . "$cfg" >/dev/null 2>&1; then
  n "不是合法 JSON"
else
  y "合法 JSON，main_branch=$(jq -r '.main_branch // "main"' "$cfg")"
  jq -e '
    ([.protected_paths, .no_full_rewrite, .json_dup_key_check][] // [] | type == "array")
    and ((.sensitive_paths // []) | type == "array")
    and ((.format_on_edit // []) | type == "array")
    and ((.worktree_links // []) | type == "array")
  ' "$cfg" >/dev/null 2>&1 && y "字段类型正确" || n "字段类型不对：protected_paths / no_full_rewrite / sensitive_paths / format_on_edit / json_dup_key_check / worktree_links 都应是数组"
  jq -e '[.protected_paths[]?, .no_full_rewrite[]?, .json_dup_key_check[]?] | all(has("glob"))' "$cfg" >/dev/null 2>&1 ||
    n "protected_paths / no_full_rewrite / json_dup_key_check 的每项都要有 glob"
  jq -e '[.format_on_edit[]?] | all(has("globs") and has("cmd"))' "$cfg" >/dev/null 2>&1 ||
    n "format_on_edit 的每项都要有 globs（数组）与 cmd"
  [ "$(jq '(.sensitive_paths // []) | length' "$cfg")" -gt 0 ] || w "sensitive_paths 为空：碰到敏感域文件不会有机械提醒（没有敏感域可忽略）"
fi

echo "conductor 前置文件"
for f in conductor/product.md conductor/tech-stack.md conductor/workflow.md conductor/tracks.md; do
  [ -f "$proj/$f" ] && y "$f" || n "$f 缺失（conductor 的 new-track / implement 会直接中止）"
done

echo "托管区"
"$FLOW_ROOT/scripts/sync-managed.sh" --check "$proj" | sed 's/^/  /'
[ "${PIPESTATUS[0]}" = 0 ] || n "托管文件缺失或落后：跑 /flow:sync"
if [ -f "$proj/conductor/workflow.md" ] && grep -q '（待填）' "$proj/conductor/workflow.md"; then
  w "workflow.md「项目补充」还有（待填）项：$(grep -c '（待填）' "$proj/conductor/workflow.md") 处"
fi

echo "接入"
st="$proj/.claude/settings.json"
if [ -f "$st" ] && jq -e '.enabledPlugins["flow@cc-flow"] == true' "$st" >/dev/null 2>&1; then
  y "settings.json 启用 flow@cc-flow"
else
  n "settings.json 没启用 flow@cc-flow（队友 clone 后不会被提示安装）"
fi
if [ -f "$st" ] && jq -e '.enabledPlugins["conductor@conductor-cc"] == true' "$st" >/dev/null 2>&1; then
  y "settings.json 启用 conductor@conductor-cc"
else
  w "settings.json 没启用 conductor@conductor-cc"
fi
grep -qxF '.claude/worktrees/' "$proj/.gitignore" 2>/dev/null && y ".gitignore 忽略 .claude/worktrees/" || n ".gitignore 缺 .claude/worktrees/（worktree 会被当成未跟踪文件）"
grep -q '/flow:triage' "$proj/CLAUDE.md" 2>/dev/null && y "CLAUDE.md 含 flow 段" || w "CLAUDE.md 没有 flow 段（模型不知道先分诊）"
if [ -f "$proj/CLAUDE.md" ] && grep -q '{{' "$proj/CLAUDE.md"; then
  w "CLAUDE.md 还有 {{占位符}} 未填"
fi

echo
[ "$bad" = 0 ] && echo "结论：通过" || echo "结论：有 ✗ 项需要处理"
exit "$bad"
