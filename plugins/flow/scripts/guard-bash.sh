#!/usr/bin/env bash
# PreToolUse(Bash)：危险命令与「绕过 Edit 工具的文件写入」拦截。
# 已知代价：子串匹配会误拦「命令文本里仅仅提到这些字符串」的场合（如写含示例的文档），
# 此时改用 Write/Edit 工具落盘即可——那条链路有自己的守卫（guard-edit.sh）。
# 残余缺口（有意接受）：cp/mv 落到保护路径无法用子串区分读写方向，不拦。
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

case "$cmd" in
  *conductor/tracks/*design*)
    flow_block "conductor/tracks/*/design/ 是只读立项快照，禁止用 Bash 写入。" ;;
esac

# no_full_rewrite 的文件同样不许用 Bash 写（整文件重写的另一条路）。
# 路径 glob 去掉开头的 `*/` 后当子串模式用：*/web/i18n/*.json → *web/i18n/*.json*
while IFS="$(printf '\t')" read -r glob reason; do
  [ -z "$glob" ] && continue
  pat="*${glob#\*/}*"
  if flow_match "$cmd" "$pat"; then
    flow_block "疑似用 Bash 写入 ${glob}。$reason 请用 Edit 工具做局部修改。"
  fi
done <<EOF
$(jq -r '.no_full_rewrite[]? | [.glob, (.reason // "该文件禁止整文件重写。")] | @tsv' "$FLOW_CFG" 2>/dev/null)
EOF

exit 0
