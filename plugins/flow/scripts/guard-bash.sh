#!/usr/bin/env bash
# PreToolUse(Bash)：危险命令与「绕过 Edit 工具的文件写入」拦截。
# 已知代价：危险命令是子串匹配，会误拦「命令文本里仅仅提到这些字符串」的场合（如写含示例的文档），
# 此时改用 Write/Edit 工具落盘即可——那条链路有自己的守卫（guard-edit.sh）。
# 残余缺口（有意接受）：cp/mv 落到保护路径无法区分读写方向，不拦；写入目标靠正则抽取，
# 变量展开出来的路径（> "$f"）认不出。
# 退出码 2 = 阻断并把 stderr 喂回模型；0 = 放行。
set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
flow_enabled || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# 1) 危险命令（子串匹配，防 `cd x && ...` 前缀绕过）。
# `.git` 只匹配目录本体/其内部（`.git` 结尾、`.git/`、`.git `），不误伤 `.github/...`。
case "$cmd" in
  *'rm -rf /'* | *'rm -rf ~'* | *'rm -rf $HOME'* | *'rm -rf *'* | *'rm -rf .git/'* | *'rm -rf .git '* | *'rm -rf .git')
    flow_block "危险命令（rm -rf 高危目标）: $cmd" ;;
  *'DROP TABLE'* | *'DROP DATABASE'* | *'TRUNCATE'*)
    flow_block "危险命令（破坏性 SQL）: $cmd" ;;
  *'push --force'* | *'push -f '* | *'push -f' | *'reset --hard'*)
    flow_block "危险命令（改写历史）: ${cmd}。确需执行请让用户在提示符里用 ! 前缀自己跑。" ;;
esac

# 2) Bash 写入受保护文件。写入指示器覆盖重定向与常见管道写入器（tee/dd/sponge/sed -i）。
writeish=0
case "$cmd" in
  *'>'* | 'tee '* | *' tee '* | *'|tee'* | 'dd '* | *' dd '* | *'sponge'* | *'sed -i'*) writeish=1 ;;
esac
[ "$writeish" = 1 ] || exit 0

# 只判「写入目标」，不对整条命令做子串匹配：目标 = 重定向目标、tee/sponge 的参数、dd 的 of=、
# sed -i 的参数；相对路径再按命令里出现过的每个 cd 目录各补全一次。
# 整条命令子串匹配会把 `2>/dev/null`、commit 尾注 `<noreply@…>` 里的 `>` 当成写入，
# 再撞上命令里任意位置的 design / 受保护路径字样就拦——读快照、git add 快照、提 PR 全被误拦。
write_targets() {
  printf '%s\n' "$1" | grep -oE '>>?\|?[[:space:]]*[^[:space:];&|<>()]+' | sed -E 's/^>>?\|?[[:space:]]*//'
  printf '%s\n' "$1" | grep -oE '(^|[^[:alnum:]_-])(tee|sponge)([[:space:]]+[^[:space:];&|<>()]+)+' |
    sed -E 's/^[^[:alnum:]]*(tee|sponge)//' | tr ' \t' '\n\n'
  printf '%s\n' "$1" | grep -oE '(^|[[:space:]])of=[^[:space:];&|<>()]+' | sed -E 's/.*of=//'
  printf '%s\n' "$1" | grep -oE '(^|[^[:alnum:]_-])sed[[:space:]][^;&|<>()]*' |
    grep -E '[[:space:]](-[a-zA-Z]*i|--in-place)' | sed -E 's/^[^[:alnum:]]*sed//' | tr ' \t' '\n\n'
}

# conductor/tracks/<id>/design*/<…> → 0。track 目录下名叫 design-input.md 之类的文件、
# 名字里带 design 的 track（redesign_x/spec.md）都不算快照。
snapshot_path() {
  local rem rest seg
  case "$1" in *conductor/tracks/*) ;; *) return 1 ;; esac
  rem=${1#*conductor/tracks/}
  rest=${rem#*/}
  [ "$rest" = "$rem" ] && return 1
  seg=${rest%%/*}
  [ "$seg" = "$rest" ] && return 1
  case "$seg" in design*) return 0 ;; esac
  return 1
}

cds=$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_-])cd[[:space:]]+[^[:space:];&|<>()]+' | sed -E 's/^.*cd[[:space:]]+//')
nfr=$(jq -r '.no_full_rewrite[]? | [.glob, (.reason // "该文件禁止整文件重写。")] | @tsv' "$FLOW_CFG" 2>/dev/null)

while IFS= read -r t; do
  t=${t//\"/}
  t=${t//\'/}
  case "$t" in '' | -* | '&'* | /dev/*) continue ;; esac
  cands=$t
  case "$t" in
    /* | '~'*) ;;
    *)
      while IFS= read -r d; do
        [ -n "$d" ] && cands="$cands
${d%/}/$t"
      done <<CDS
$cds
CDS
      ;;
  esac
  while IFS= read -r p; do
    if snapshot_path "$p"; then
      flow_block "conductor/tracks/*/design/ 是只读立项快照，禁止用 Bash 写入（目标：${p}）。"
    fi
    # no_full_rewrite 的文件同样不许用 Bash 写（整文件重写的另一条路）。
    # glob 去掉开头的 `*/` 再补前缀 `*`：*/web/i18n/*.json → *web/i18n/*.json（相对路径也能命中）
    while IFS="$(printf '\t')" read -r glob reason; do
      [ -z "$glob" ] && continue
      if flow_match "$p" "*${glob#\*/}"; then
        flow_block "疑似用 Bash 写入 ${glob}（目标：${p}）。${reason} 请用 Edit 工具做局部修改。"
      fi
    done <<NFR
$nfr
NFR
  done <<CANDS
$cands
CANDS
done <<TGT
$(write_targets "$cmd")
TGT

exit 0
