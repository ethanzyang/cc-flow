# shellcheck shell=bash
# flow hook 共享函数。约定：没有 .claude/flow.json 的仓库 = 没启用 flow，所有 hook 静默放行。
# 这样插件装在用户级也不会干扰别的仓库。
# 只用 bash 3.2 语法（macOS 自带 bash）：不用关联数组、mapfile、${x,,}。

FLOW_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FLOW_PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
FLOW_CFG="$FLOW_PROJECT/.claude/flow.json"

# 已启用 flow 且 jq 可用 → 0；否则 1（调用方据此 exit 0 放行）
flow_enabled() {
  [ -f "$FLOW_CFG" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  return 0
}

# flow_cfg <jq 表达式>：读配置；缺省输出空串
flow_cfg() { jq -r "($1) // empty" "$FLOW_CFG" 2>/dev/null; }

flow_main_branch() {
  local b
  b=$(flow_cfg '.main_branch')
  printf '%s' "${b:-main}"
}

flow_plugin_version() {
  jq -r '.version // "0.0.0"' "$FLOW_ROOT/.claude-plugin/plugin.json" 2>/dev/null
}

# 向上找到第一个存在的目录（Write 新文件时父目录可能还不存在）
flow_existing_dir() {
  local d
  d=$(dirname "$1")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do d=$(dirname "$d"); done
  printf '%s' "$d"
}

# 主仓库根目录：在 worktree 里也返回主 checkout（--git-common-dir 指向主 .git）
flow_main_root() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  printf '%s' "${common%/.git}"
}

# flow_match <字符串> <glob>：case 语义，* 可以跨 /
flow_match() {
  # shellcheck disable=SC2254
  case "$1" in $2) return 0 ;; esac
  return 1
}

flow_block() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 2
}

# semver 比较：输出 -1 / 0 / 1
flow_ver_cmp() {
  local IFS=.
  # shellcheck disable=SC2206
  local a=($1) b=($2) i x y
  for i in 0 1 2; do
    x=${a[$i]:-0}
    y=${b[$i]:-0}
    if [ "$x" -lt "$y" ] 2>/dev/null; then echo -1; return; fi
    if [ "$x" -gt "$y" ] 2>/dev/null; then echo 1; return; fi
  done
  echo 0
}

# 未收尾提醒（Stop 与 SessionStart 共用），每条一行；没有则无输出。
# flow_hygiene_report <当前工作目录> [full]
#   full：连当前 worktree 的未提交变更也报（SessionStart 用）；Stop 每轮都跑，干活中途有未提交
#   变更是常态，不报，只报真正的「没收尾」。
# 覆盖 workflow §7.1 收尾与「主 checkout 只读」的 Bash 绕过面（Edit 有 hook 拦，Bash 重定向没有）。
flow_hygiene_report() {
  local cwd="${1:-$PWD}" mode="${2:-}" root main base changes merged gone basesha stale cur
  main=$(flow_main_branch)
  root=$(flow_main_root "$cwd") || return 0
  [ -n "$root" ] || return 0

  # 1) 主 checkout：应停在干净的主干上
  cur=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" != "HEAD" ] && [ "$cur" != "$main" ]; then
    echo "⚠️  主 checkout 停在 $cur 而不是 ${main}（主 checkout 应永远停在 ${main}，改动走 worktree）。"
  fi
  changes=$(git -C "$root" status --porcelain 2>/dev/null | head -5)
  if [ -n "$changes" ]; then
    echo "⚠️  主 checkout ($root) 有未提交的改动——它应是只读基座:"
    printf '%s\n' "$changes" | sed 's/^/    /'
  fi

  # 2) 当前 worktree 的未提交变更（不是主 checkout 时才单独报）
  local top
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ "$mode" = full ] && [ -n "$top" ] && [ "$top" != "$root" ]; then
    changes=$(git -C "$top" status --porcelain 2>/dev/null | head -5)
    if [ -n "$changes" ]; then
      echo "⚠️  当前 worktree 有未提交的变更:"
      printf '%s\n' "$changes" | sed 's/^/    /'
    fi
  fi

  # 3) 分支已并入主干却仍存在的 worktree。刚切出、还没提交的新分支 tip 等于主干，也满足
  #    --merged，但那是正在干活的工作区，不算待清理。
  if git -C "$root" rev-parse -q --verify "origin/$main" >/dev/null 2>&1; then
    base="origin/$main"
  else
    base="$main"
  fi
  merged=$(git -C "$root" branch --merged "$base" --format='%(refname:short)' 2>/dev/null)
  # squash 合并的分支永远不是主干的祖先：远端分支已删（upstream 显示 [gone]）也算已并入
  gone=$(git -C "$root" for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads 2>/dev/null |
    awk -F'\t' '$2 == "[gone]" { print $1 }')
  merged=$(printf '%s\n%s\n' "$merged" "$gone" | grep . || true)
  basesha=$(git -C "$root" rev-parse "$base" 2>/dev/null)
  [ -n "$merged" ] || return 0
  stale=$(git -C "$root" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{w=substr($0,10)} /^branch /{b=$2; sub("refs/heads/","",b); print w"\t"b}' |
    while IFS="$(printf '\t')" read -r wt br; do
      [ "$wt" = "$root" ] && continue
      printf '%s\n' "$merged" | grep -qx "$br" || continue
      [ "$(git -C "$root" rev-parse "$br" 2>/dev/null)" = "$basesha" ] && continue
      printf '    %s (%s)\n' "$wt" "$br"
    done)
  if [ -n "$stale" ]; then
    echo "⚠️  分支已并入 ${base}（或远端分支已删）但 worktree 未删（workflow §7.1 收尾，跑 /flow:closeout）:"
    printf '%s\n' "$stale"
  fi
  return 0
}
