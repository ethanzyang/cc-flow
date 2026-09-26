#!/usr/bin/env bash
# 把插件里的托管模板同步进项目。托管区夹在两行标记之间，整段覆盖；标记之外（如 workflow.md 文末
# 「项目补充」）一字不动。目标文件不存在则新建（workflow.md 会附上项目补充骨架）。
#
# 用法：sync-managed.sh [--check] [--allow-main] [项目目录]
#   --check       只报告，不写。有任一文件缺失/落后/无标记 → 退出码 1
#   --allow-main  允许在主干上写（仅 /flow:init 首次接入时用；接入后改动一律走 worktree）
set -u
. "$(dirname "$0")/lib.sh"

check=0
allow_main=0
proj=""
for a in "$@"; do
  case "$a" in
    --check) check=1 ;;
    --allow-main) allow_main=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 64 ;;
    *) proj="$a" ;;
  esac
done
proj="${proj:-$FLOW_PROJECT}"
proj=$(cd "$proj" && pwd) || exit 1

ver=$(flow_plugin_version)
tpl_dir="$FLOW_ROOT/templates"
BEGIN_RE='<!-- flow:managed:begin'
END_LINE='<!-- flow:managed:end -->'

# 托管文件清单：模板|目标（相对项目根）|首次创建时追加的骨架（可空）
MANAGED="workflow.md|conductor/workflow.md|workflow.project.md
TEAM_GUIDE.md|dev-docs/TEAM_GUIDE.md|"

if [ "$check" = 0 ] && [ "$allow_main" = 0 ] && [ -f "$proj/.claude/flow.json" ]; then
  main=$(FLOW_CFG="$proj/.claude/flow.json" flow_main_branch)
  cur=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ "$cur" = "$main" ]; then
    echo "拒绝：$proj 当前在主干 $main 上。主 checkout 只读——先进 worktree 再同步（EnterWorktree）。" >&2
    exit 1
  fi
fi

render() { # $1 = 模板文件
  printf '<!-- flow:managed:begin v%s — 本区由 flow 插件托管（github.com/ethanzyang/cc-flow），/flow:sync 会整段覆盖。不要在此手改：通用改进提到插件仓库；本项目特有内容写在托管区之外。 -->\n' "$ver"
  cat "$1"
  printf '%s\n' "$END_LINE"
}

status=0
while IFS='|' read -r tpl target skel; do
  [ -z "$tpl" ] && continue
  src="$tpl_dir/$tpl"
  dst="$proj/$target"
  block=$(mktemp)
  render "$src" >"$block"

  if [ ! -f "$dst" ]; then
    if [ "$check" = 1 ]; then
      echo "缺失    $target"
      status=1
    else
      mkdir -p "$(dirname "$dst")"
      cp "$block" "$dst"
      if [ -n "$skel" ]; then cat "$tpl_dir/$skel" >>"$dst"; fi
      echo "已创建  $target (v$ver)"
    fi
    rm -f "$block"
    continue
  fi

  nb=$(grep -c "^$BEGIN_RE" "$dst" || true)
  ne=$(grep -cxF "$END_LINE" "$dst" || true)
  if [ "$nb" != 1 ] || [ "$ne" != 1 ]; then
    echo "无标记  $target —— 已存在但没有（或有多组）flow 托管标记，未改动。接入方法见 /flow:sync 说明。"
    status=1
    rm -f "$block"
    continue
  fi

  cur_ver=$(sed -n 's/.*flow:managed:begin v\([0-9][0-9.]*\).*/\1/p' "$dst" | head -1)
  current=$(mktemp)
  awk -v b="$BEGIN_RE" -v e="$END_LINE" '
    index($0, b) == 1 { on = 1 }
    on { print }
    $0 == e { on = 0 }
  ' "$dst" >"$current"

  if cmp -s "$block" "$current"; then
    echo "最新    $target (v$cur_ver)"
  elif [ "$check" = 1 ]; then
    echo "需同步  $target (v$cur_ver → v$ver)"
    status=1
  else
    out=$(mktemp)
    awk -v b="$BEGIN_RE" -v e="$END_LINE" -v blk="$block" '
      index($0, b) == 1 { while ((getline line < blk) > 0) print line; skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }
    ' "$dst" >"$out" && cat "$out" >"$dst"
    rm -f "$out"
    echo "已同步  $target (v$cur_ver → v$ver)"
  fi
  rm -f "$block" "$current"
done <<EOF
$MANAGED
EOF

exit "$status"
