#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit)：把「靠自觉」的路径规则变成确定性拦截。
#   1) 主 checkout 只读：本项目仓库里、当前分支是主干的文件一律拦——改动走 worktree。
#      别的仓库、非 git 目录（如 ~/.claude 下的 memory）、被 gitignore 的本地文件不管。
#   2) conductor/tracks/*/design*/ 是只读立项快照（workflow §3.2）
#   3) flow.json protected_paths：永远不许改
#   4) flow.json no_full_rewrite：已存在的文件不许用 Write 整文件重写（只许 Edit 局部改）
# 退出码 2 = 阻断并把 stderr 喂回模型；0 = 放行。
set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
flow_enabled || exit 0

f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$f" ] && exit 0
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

# 1) 主 checkout 只读
main=$(flow_main_branch)
d=$(flow_existing_dir "$f")
file_root=$(flow_main_root "$d" 2>/dev/null || true)
proj_root=$(flow_main_root "$FLOW_PROJECT" 2>/dev/null || true)
if [ -n "$file_root" ] && [ "$file_root" = "$proj_root" ]; then
  branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  # 被 gitignore 的本地文件（如设计目录的 .project-id）不属于仓库改动，不受「只读」约束；
  # 需要保护的本地文件（.env 等）由下面的 protected_paths 管。
  if [ "$branch" = "$main" ] && ! git -C "$d" check-ignore -q "$f" 2>/dev/null; then
    flow_block "主 checkout 是只读基座（当前分支 ${main}）。请在 worktree 里改：EnterWorktree，或 git worktree add -b <branch> .claude/worktrees/<name> origin/$main"
  fi
fi

# 2) design 快照只读
case "$f" in
  */conductor/tracks/*/design*/*)
    flow_block "conductor/tracks/*/design/ 是只读立项快照（workflow §3.2）。要改设计请改设计真相源再重新 /flow:design-track。" ;;
esac

# 3) 保护路径
while IFS="$(printf '\t')" read -r glob reason; do
  [ -z "$glob" ] && continue
  if flow_match "$f" "$glob"; then
    flow_block "${reason}（.claude/flow.json protected_paths: ${glob}）"
  fi
done <<EOF
$(jq -r '.protected_paths[]? | [.glob, (.reason // "受保护路径，禁止修改。")] | @tsv' "$FLOW_CFG" 2>/dev/null)
EOF

# 4) 禁止整文件重写（新建文件放行）
if [ "$tool" = "Write" ] && [ -e "$f" ]; then
  while IFS="$(printf '\t')" read -r glob reason; do
    [ -z "$glob" ] && continue
    if flow_match "$f" "$glob"; then
      flow_block "$reason 请用 Edit 做局部修改（.claude/flow.json no_full_rewrite: ${glob}）"
    fi
  done <<EOF
$(jq -r '.no_full_rewrite[]? | [.glob, (.reason // "该文件禁止整文件重写。")] | @tsv' "$FLOW_CFG" 2>/dev/null)
EOF
fi

exit 0
