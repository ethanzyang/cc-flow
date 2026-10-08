#!/usr/bin/env bash
# 流程度量（workflow §7）：最近 N 天主干上的提交与合并的 PR。只读，不改任何东西。
# 用法：stats.sh [项目目录] [--days 14]
#   git 能算的：只改文档的提交占比、feat 之后 48 小时内的 fix。
#   gh 已登录时再算：PR 从首个提交到合并的时长、非测试代码行数、审阅轮数（PR 评论里的 VERDICT 行数）。
set -u
. "$(dirname "$0")/lib.sh"

days=14
proj=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:?--days 后面要跟天数}"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) proj="$1"; shift ;;
  esac
done
proj="${proj:-$FLOW_PROJECT}"
proj=$(cd "$proj" && pwd) || exit 1
command -v jq >/dev/null 2>&1 || { echo "需要 jq（macOS: brew install jq）" >&2; exit 1; }
FLOW_CFG="$proj/.claude/flow.json"
main=$(flow_main_branch)

since=$(date -u -v-"${days}"d +%Y-%m-%d 2>/dev/null || date -u -d "$days days ago" +%Y-%m-%d)
ref="origin/$main"
git -C "$proj" rev-parse -q --verify "$ref" >/dev/null 2>&1 || ref="$main"

# 文档 / 记账类路径：只动这些的提交算「只改文档」
DOC_RE='(\.md$|^conductor/|^docs/|^dev-docs/)'

median() {
  sort -n | awk '{a[NR]=$1} END {
    if (NR == 0) { print "-"; exit }
    if (NR % 2) print a[(NR + 1) / 2]; else printf "%g\n", (a[NR / 2] + a[NR / 2 + 1]) / 2 }'
}

echo "flow 度量：$(basename "$proj")，最近 ${days} 天（自 ${since}，主干 ${ref}）"
echo

# ---------------------------------------------------------------- git
commits=$(git -C "$proj" log "$ref" --first-parent --since="$since" --format='%H %ct %s' 2>/dev/null)
total=0
doconly=0
fixes=0
fixes48=0
feat_times=$(printf '%s\n' "$commits" | awk '$3 ~ /^feat/ { print $2 }')
while read -r h t subj; do
  [ -n "$h" ] || continue
  total=$((total + 1))
  files=$(git -C "$proj" diff --name-only "$h^1" "$h" 2>/dev/null)
  if [ -n "$files" ] && [ -z "$(printf '%s\n' "$files" | grep -vE "$DOC_RE" | head -1)" ]; then
    doconly=$((doconly + 1))
  fi
  case "$subj" in
    fix*)
      fixes=$((fixes + 1))
      while read -r ft; do
        [ -n "$ft" ] || continue
        if [ "$t" -ge "$ft" ] && [ $((t - ft)) -le 172800 ]; then
          fixes48=$((fixes48 + 1))
          break
        fi
      done <<FT
$feat_times
FT
      ;;
  esac
done <<EOF
$commits
EOF

if [ "$total" -gt 0 ]; then
  pct=$((doconly * 100 / total))
  flag=$([ "$pct" -lt 15 ] && echo "✓" || echo "✗")
  echo "主干提交        ${total} 个；只改文档 ${doconly} 个（${pct}%）${flag}  目标 <15%"
  echo "上线后修复      fix 提交 ${fixes} 个，其中 ${fixes48} 个在某个 feat 之后 48 小时内"
else
  echo "主干提交        最近 ${days} 天没有提交"
fi

# ---------------------------------------------------------------- gh
if ! command -v gh >/dev/null 2>&1; then
  echo
  echo "（没装 gh：PR 时长 / 大小 / 审阅轮数不计）"
  exit 0
fi
# 先取编号再逐个取详情：一次 list 带 files / commits 会超出 GitHub GraphQL 的节点上限
nums=$(cd "$proj" && gh pr list --state merged --search "merged:>=$since" --limit 200 --json number --jq '.[].number' 2>/dev/null) || {
  echo
  echo "（gh 取不到 PR：没登录或没有远端，PR 时长 / 大小 / 审阅轮数不计）"
  exit 0
}
prs=$(printf '%s\n' "$nums" | grep . | (cd "$proj" && xargs -P 4 -I{} sh -c 'f=number,title,mergedAt,files,commits,comments; gh pr view "$1" --json "$f" 2>/dev/null || { sleep 2; gh pr view "$1" --json "$f" 2>/dev/null; }' _ {}) | jq -s '.')
[ -n "$prs" ] || prs='[]'
rows=$(printf '%s' "$prs" | jq -r --arg doc "$DOC_RE" '
  def iso: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  .[] | {
    n: .number,
    t: .title,
    lead: (if (.commits | length) > 0
           then (((.mergedAt | iso) - ([.commits[].authoredDate | iso] | min)) / 3600)
           else 0 end),
    code: ([.files[]? | select((.path | test($doc)) | not)
                      | select(.path | test("(\\.test\\.|\\.spec\\.|/__tests__/|(^|/)tests?/|(^|/)fixtures?/|\\.snap$|lock|/meta/[^/]*\\.json$|_snapshot\\.json$)"; "i") | not)
                      | .additions] | add // 0),
    rounds: ([.comments[]? | select(.body | test("VERDICT"))] | length)
  } | "\(.n)\t\(.lead * 10 | floor / 10)\t\(.code)\t\(.rounds)\t\(.t)"')

npr=$(printf '%s\n' "$rows" | grep -c . || true)
echo
if [ "$npr" = 0 ]; then
  echo "合并的 PR        最近 ${days} 天没有"
  exit 0
fi
lead_med=$(printf '%s\n' "$rows" | cut -f2 | median)
code_med=$(printf '%s\n' "$rows" | cut -f3 | median)
big=$(printf '%s\n' "$rows" | awk -F'\t' '$3 > 400' | grep -c . || true)
slow=$(printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k2,2nr | head -1)
largest=$(printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k3,3nr | head -1)
rounds_avg=$(printf '%s\n' "$rows" | awk -F'\t' '{s += $4} END { printf "%.1f", s / NR }')
norev=$(printf '%s\n' "$rows" | awk -F'\t' '$4 == 0' | grep -c . || true)
multi=$(printf '%s\n' "$rows" | awk -F'\t' '$4 > 1' | grep -c . || true)

echo "合并的 PR        ${npr} 个"
printf '  首提交→合并    中位 %s 小时；最慢 #%s %s 小时（%s）  目标：双向门当天\n' \
  "$lead_med" "$(printf '%s' "$slow" | cut -f1)" "$(printf '%s' "$slow" | cut -f2)" "$(printf '%s' "$slow" | cut -f5)"
printf '  非测试代码     中位 %s 行；超过 400 行的 %s 个；最大 #%s %s 行  目标 ≤400\n' \
  "$code_med" "$big" "$(printf '%s' "$largest" | cut -f1)" "$(printf '%s' "$largest" | cut -f3)"
printf '  审阅轮数       平均 %s；超过 1 轮的 %s 个；没留审阅记录的 %s 个  目标 ≤1\n' "$rounds_avg" "$multi" "$norev"
