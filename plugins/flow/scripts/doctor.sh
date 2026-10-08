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
  [ "$(jq '(.sensitive_paths // []) | length' "$cfg")" -gt 0 ] || w "sensitive_paths 为空：碰到单向门相关文件不会有机械提醒（没有单向门可忽略）"
fi

echo "规则正文"
[ -f "$proj/conductor/workflow.md" ] && y "conductor/workflow.md" || n "conductor/workflow.md 缺失（flow 规则正文）：跑 /flow:init"
[ -d "$proj/.conductor_templates" ] && w ".conductor_templates/ 还在（旧版接入时的临时模板）：init-project.sh finish 会删掉它"
if [ -f "$proj/conductor/workflow.md" ] && grep -q '^### P2 层划分' "$proj/conductor/workflow.md"; then
  w "项目补充还是 0.4 的结构（P2 层划分）：0.5 起 P1 = 单向门清单、P2 = 上线，见 /flow:init 的 upgrade.md"
fi

echo "托管区"
"$FLOW_ROOT/scripts/sync-managed.sh" --check "$proj" | sed 's/^/  /'
[ "${PIPESTATUS[0]}" = 0 ] || n "托管文件缺失或落后：跑 /flow:init"
if [ -f "$proj/conductor/workflow.md" ] && grep -q '（待填）' "$proj/conductor/workflow.md"; then
  w "workflow.md「项目补充」还有（待填）项：$(grep -c '（待填）' "$proj/conductor/workflow.md") 处"
fi

ddir=$(jq -r '.design.dir // empty' "$cfg" 2>/dev/null)
if [ -n "$ddir" ]; then
  echo "设计模块（$ddir/）"
  [ -f "$proj/$ddir/SYNC.md" ] && y "$ddir/SYNC.md" || n "缺 $ddir/SYNC.md：跑 /flow:init"
  grep -qxF "$ddir/.project-id" "$proj/.gitignore" 2>/dev/null && y ".gitignore 忽略 $ddir/.project-id" ||
    n ".gitignore 缺 $ddir/.project-id（每人的 Claude Design 项目 id 不同，不能提交）"
  [ -z "$(git -C "$proj" ls-files "$ddir/.project-id" 2>/dev/null)" ] && y ".project-id 未进版本库" ||
    n "$ddir/.project-id 被提交了：git rm --cached 移出版本库"
  grep -q '/flow:design push' "$proj/CLAUDE.md" 2>/dev/null && y "CLAUDE.md 含设计段" || w "CLAUDE.md 没有设计段"
  if grep -q '（待补' "$proj/$ddir/SYNC.md" 2>/dev/null; then w "$ddir/SYNC.md 项目补充 D1 还有（待补）"; fi
fi

echo "接入"
st="$proj/.claude/settings.json"
if [ -f "$st" ] && jq -e '.enabledPlugins["flow@cc-flow"] == true' "$st" >/dev/null 2>&1; then
  y "settings.json 启用 flow@cc-flow"
else
  n "settings.json 没启用 flow@cc-flow（队友 clone 后不会被提示安装）"
fi
grep -qxF '.claude/worktrees/' "$proj/.gitignore" 2>/dev/null && y ".gitignore 忽略 .claude/worktrees/" || n ".gitignore 缺 .claude/worktrees/（worktree 会被当成未跟踪文件）"
if grep -q '/flow:shape' "$proj/CLAUDE.md" 2>/dev/null; then
  y "CLAUDE.md 含 flow 段"
elif grep -q '/flow:triage\|/triage' "$proj/CLAUDE.md" 2>/dev/null; then
  w "CLAUDE.md 还是旧版 flow 段（分诊 / 三档）：换成 templates/CLAUDE.flow-section.md"
else
  w "CLAUDE.md 没有 flow 段（模型不知道先定形）"
fi
if [ -f "$proj/CLAUDE.md" ]; then
  lines=$(wc -l <"$proj/CLAUDE.md" | tr -d ' ')
  [ "$lines" -le 150 ] || w "CLAUDE.md ${lines} 行（每个 session 常驻；把只对某类文件成立的挪进 .claude/rules/、领域陷阱挪进 skill）"
fi
for r in "$proj"/.claude/rules/*.md; do
  [ -f "$r" ] || continue
  if grep -q '^globs:' "$r" && ! grep -q '^paths:' "$r"; then
    w "$(basename "$r") 用的是 globs:——Claude Code 只认 paths:，这条规则现在每个 session 都无条件加载"
  fi
done
if [ -f "$proj/CLAUDE.md" ] && grep -q '{{' "$proj/CLAUDE.md"; then
  w "CLAUDE.md 还有 {{占位符}} 未填"
fi

echo
echo "度量：bash \"\$CLAUDE_PLUGIN_ROOT/scripts/stats.sh\" <项目目录>（或 /flow:stats）"
[ "$bad" = 0 ] && echo "结论：通过" || echo "结论：有 ✗ 项需要处理"
exit "$bad"
