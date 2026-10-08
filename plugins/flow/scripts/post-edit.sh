#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit)：保存后的确定性处理，其余一律放行。
#   1) flow.json format_on_edit：按 glob 跑格式化命令（失败不阻断）
#   2) conductor/tracks.md 不变量：^## 计数 == ^--- 计数；状态标记只许 [ ]/[~]/[x]（workflow §7.2）
#   3) flow.json json_dup_key_check：JSON 合法 + 同一对象内无新增重复键
#      （有重复键的文件经 json.load/dump 往返会被静默折叠成最后一次出现的值）
#   4) flow.json sensitive_paths：碰到单向门提醒路径上的文件时往模型上下文里注入一次提醒（不阻断）
# 退出码 2 = 把 stderr 回喂给模型；0 = 通过。
set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
flow_enabled || exit 0

f=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

fail() {
  printf 'FLOW CHECK: %s\n' "$1" >&2
  exit 2
}

# 1) 保存即格式化。命令在被改文件所属仓库的根目录执行（主 checkout 与 worktree 都对），
#    文件路径通过环境变量 FILE 传入。
repo_top=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null || dirname "$f")
n=$(jq '.format_on_edit | length' "$FLOW_CFG" 2>/dev/null || echo 0)
i=0
while [ "$i" -lt "${n:-0}" ]; do
  hit=0
  while IFS= read -r g; do
    [ -n "$g" ] && flow_match "$f" "$g" && hit=1
  done <<EOF
$(jq -r ".format_on_edit[$i].globs[]?" "$FLOW_CFG" 2>/dev/null)
EOF
  if [ "$hit" = 1 ]; then
    fcmd=$(jq -r ".format_on_edit[$i].cmd // empty" "$FLOW_CFG" 2>/dev/null)
    [ -n "$fcmd" ] && (cd "$repo_top" && FILE="$f" bash -c "$fcmd") >/dev/null 2>&1
  fi
  i=$((i + 1))
done

# 2) tracks.md 不变量
case "$f" in
  */conductor/tracks.md)
    h=$(grep -c '^## ' "$f" || true)
    d=$(grep -c '^---$' "$f" || true)
    if [ "$h" != "$d" ]; then
      fail "tracks.md 不变量破坏：'^## ' 有 ${h} 个，'^---\$' 有 ${d} 个（每节前必须一个 --- 分隔符，含首节；workflow §7.2）。缺分隔符会破坏 /conductor:implement 的解析。"
    fi
    if grep -qE '^## \[[^] ~x]' "$f"; then
      fail "tracks.md 状态标记只允许 [ ]/[~]/[x]（workflow §7.2）。未立项条目放 conductor/backlog.md；superseded 用 [x] + 描述行注明。"
    fi
    ;;
esac

# 3) JSON 重复键
while IFS="$(printf '\t')" read -r glob known; do
  [ -z "$glob" ] && continue
  flow_match "$f" "$glob" || continue
  command -v python3 >/dev/null 2>&1 || break
  python3 - "$f" "$known" <<'PY' || exit 2
import json, sys
p, known = sys.argv[1], sys.argv[2]
KNOWN = set(json.loads(known)) if known else set()
dups = []
def hook(pairs):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            dups.append(k)
        seen.add(k)
    return dict(pairs)
try:
    with open(p, encoding="utf-8") as fh:
        json.load(fh, object_pairs_hook=hook)
except Exception as e:
    print(f"FLOW CHECK: {p} 不是合法 JSON：{e}", file=sys.stderr)
    sys.exit(2)
new = sorted(set(dups) - KNOWN)
if new:
    print(f"FLOW CHECK: {p} 同一对象内新增重复键 {new[:5]}（共 {len(new)} 个）。重复键在 json 往返时会被"
          "静默折叠成最后一次出现的值——请删掉本次新增的重复项。", file=sys.stderr)
    sys.exit(2)
PY
done <<EOF
$(jq -r '.json_dup_key_check[]? | [.glob, ((.known // []) | tojson)] | @tsv' "$FLOW_CFG" 2>/dev/null)
EOF

# 4) 单向门提醒：同一 session 同一文件只提醒一次
hit=""
while IFS= read -r glob; do
  [ -n "$glob" ] && flow_match "$f" "$glob" && hit="$glob" && break
done <<EOF
$(jq -r '.sensitive_paths[]?' "$FLOW_CFG" 2>/dev/null)
EOF
if [ -n "$hit" ]; then
  sid=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
  mark="${TMPDIR:-/tmp}/flow-sensitive-$sid"
  if ! grep -qxF "$f" "$mark" 2>/dev/null; then
    printf '%s\n' "$f" >>"$mark" 2>/dev/null
    msg="flow: ${f} 在单向门提醒路径上（sensitive_paths: ${hit}）。先判断这次改动错了能否 revert 了事（workflow §2.1）：不能 → 三档：spec 审一次、先行测试不改断言（§4.5）、这一片合并前审一次、由用户合并（§6 / §1 停点 4）。"
    jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
  fi
fi

exit 0
