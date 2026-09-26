#!/usr/bin/env bash
# CwdChanged / SessionStart：把主 checkout 里被 gitignore 的本地文件（默认 .env）软链进新 worktree。
# `git worktree add` 不会带上这些文件，新 worktree 里应用起不来，得手工拷——这里自动补。
# 软链而不是复制：改真身即全体生效，密钥始终只有一份。
# 两个事件都不能阻断任何东西，失败的代价只是没链上。
set -uo pipefail
. "$(dirname "$0")/lib.sh"

input=$(cat)
flow_enabled || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

# 只在 worktree 里动手（Claude Code 的 EnterWorktree 与 flow 约定都放在 .claude/worktrees/ 下）
case "$cwd" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
root=$(flow_main_root "$cwd") || exit 0
[ -n "$root" ] && [ "$root" != "$top" ] || exit 0

links=$(jq -r '(.worktree_links // [".env"])[]?' "$FLOW_CFG" 2>/dev/null)
while IFS= read -r name; do
  [ -z "$name" ] && continue
  # 已存在（真文件或软链，活的死的都算）就不动
  if [ -e "$top/$name" ] || [ -L "$top/$name" ]; then continue; fi
  [ -e "$root/$name" ] || continue
  mkdir -p "$(dirname "$top/$name")" 2>/dev/null
  ln -s "$root/$name" "$top/$name" 2>/dev/null &&
    echo "flow: linked $name from main checkout into $(basename "$top")" >&2
done <<EOF
$links
EOF

exit 0
