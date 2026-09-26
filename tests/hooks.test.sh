#!/usr/bin/env bash
# flow hook 与 sync 脚本的回归测试：造临时 git 仓库，往脚本 stdin 喂 hook JSON，断言退出码/输出。
# 跑法：bash tests/hooks.test.sh   （依赖 git、jq、python3）
set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
S="$HERE/plugins/flow/scripts"
export CLAUDE_PLUGIN_ROOT="$HERE/plugins/flow"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { failn=$((failn + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# expect_exit <名称> <期望退出码> <脚本> <json>
expect_exit() {
  local name=$1 want=$2 script=$3 json=$4 got out
  out=$(printf '%s' "$json" | "$S/$script" 2>&1)
  got=$?
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name" "want exit $want, got $got: $out"; fi
}
# expect_out <名称> <脚本> <json> <输出里应含的子串>
expect_out() {
  local name=$1 script=$2 json=$3 needle=$4 out
  out=$(printf '%s' "$json" | "$S/$script" 2>&1)
  case "$out" in *"$needle"*) ok "$name" ;; *) bad "$name" "missing [$needle] in: $out" ;; esac
}
edit_json() { jq -nc --arg t "$1" --arg f "$2" '{tool_name:$t, tool_input:{file_path:$f}, session_id:"t1"}'; }
bash_json() { jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-test.XXXXXX")
trap 'rm -r -f "$TMP"' EXIT

# ---------- fixture：一个启用了 flow 的项目 + 一个 worktree + 一个无关仓库 ----------
P="$TMP/proj"
mkdir -p "$P/.claude" "$P/conductor" "$P/web/i18n"
git -C "$P" init -q -b main
git -C "$P" config user.email t@t
git -C "$P" config user.name t
cat >"$P/.claude/flow.json" <<'EOF'
{
  "version": 1,
  "main_branch": "main",
  "worktree_links": [".env"],
  "protected_paths": [{ "glob": "*/.env", "reason": ".env 禁止修改。" }],
  "no_full_rewrite": [{ "glob": "*/web/i18n/*.json", "reason": "locale 有重复键。" }],
  "sensitive_paths": ["*/billing/*"],
  "format_on_edit": [{ "globs": ["*.fmt"], "cmd": "echo formatted >> \"$FILE\"" }],
  "json_dup_key_check": [{ "glob": "*/web/i18n/*.json", "known": ["legacy"] }]
}
EOF
echo '{"a":1}' >"$P/web/i18n/en.json"
printf '# Project Tracks\n' >"$P/conductor/tracks.md"
echo SECRET=1 >"$P/.env"
printf '.env\n.claude/worktrees/\n' >"$P/.gitignore"
git -C "$P" add -A && git -C "$P" commit -qm init
git -C "$P" worktree add -q -b feat/x "$P/.claude/worktrees/x" main
W="$P/.claude/worktrees/x"

O="$TMP/other"
mkdir -p "$O" && git -C "$O" init -q -b main

N="$TMP/noflow"
mkdir -p "$N" && git -C "$N" init -q -b main

export CLAUDE_PROJECT_DIR="$P"

echo "guard-edit"
expect_exit "主 checkout 上改文件 → 拦" 2 guard-edit.sh "$(edit_json Edit "$P/src/a.go")"
expect_exit "worktree 里改文件 → 放行" 0 guard-edit.sh "$(edit_json Edit "$W/src/a.go")"
expect_exit "别的仓库在 main 上 → 不管" 0 guard-edit.sh "$(edit_json Edit "$O/a.go")"
expect_exit "非 git 目录 → 不管" 0 guard-edit.sh "$(edit_json Write "$TMP/loose/memo.md")"
expect_exit "design 快照 → 拦" 2 guard-edit.sh "$(edit_json Edit "$W/conductor/tracks/t_20260101/design/BRIEF.md")"
expect_exit "track 名含 design 但不是快照目录 → 放行" 0 guard-edit.sh "$(edit_json Edit "$W/conductor/tracks/redesign_20260101/spec.md")"
expect_exit "protected_paths → 拦" 2 guard-edit.sh "$(edit_json Edit "$W/.env")"
cp "$P/web/i18n/en.json" "$W/web/i18n/en.json" 2>/dev/null || true
expect_exit "no_full_rewrite：Write 已存在文件 → 拦" 2 guard-edit.sh "$(edit_json Write "$W/web/i18n/en.json")"
expect_exit "no_full_rewrite：Edit → 放行" 0 guard-edit.sh "$(edit_json Edit "$W/web/i18n/en.json")"
expect_exit "no_full_rewrite：Write 新文件 → 放行" 0 guard-edit.sh "$(edit_json Write "$W/web/i18n/fr.json")"
CLAUDE_PROJECT_DIR="$N" expect_exit "未启用 flow 的仓库 → 全放行" 0 guard-edit.sh "$(edit_json Edit "$N/a.go")"

echo "guard-bash"
expect_exit "rm -rf / → 拦" 2 guard-bash.sh "$(bash_json 'cd x && rm -rf /')"
expect_exit "git push --force → 拦" 2 guard-bash.sh "$(bash_json 'git push --force origin x')"
expect_exit "git reset --hard → 拦" 2 guard-bash.sh "$(bash_json 'git reset --hard HEAD~1')"
expect_exit "DROP TABLE → 拦" 2 guard-bash.sh "$(bash_json 'sqlite3 db "DROP TABLE users"')"
expect_exit "重定向写 locale → 拦" 2 guard-bash.sh "$(bash_json 'echo {} > web/i18n/en.json')"
expect_exit "读 locale → 放行" 0 guard-bash.sh "$(bash_json 'cat web/i18n/en.json')"
expect_exit "重定向写 design 快照 → 拦" 2 guard-bash.sh "$(bash_json 'echo x > conductor/tracks/t/design/a.md')"
expect_exit "普通命令 → 放行" 0 guard-bash.sh "$(bash_json 'git status && ls -la')"
expect_exit "rm -rf 普通目录 → 放行" 0 guard-bash.sh "$(bash_json 'rm -rf node_modules')"
CLAUDE_PROJECT_DIR="$N" expect_exit "未启用 flow → 放行" 0 guard-bash.sh "$(bash_json 'git push --force')"

echo "post-edit"
printf '# Project Tracks\n\n---\n\n## [ ] Track: a\n' >"$W/conductor/tracks.md"
expect_exit "tracks.md 合法 → 通过" 0 post-edit.sh "$(edit_json Edit "$W/conductor/tracks.md")"
printf '# Project Tracks\n\n---\n\n## [ ] Track: a\n\n## [x] Track: b\n' >"$W/conductor/tracks.md"
expect_exit "tracks.md 缺分隔符 → 报错" 2 post-edit.sh "$(edit_json Edit "$W/conductor/tracks.md")"
printf '# Project Tracks\n\n---\n\n## [planned] Track: a\n' >"$W/conductor/tracks.md"
expect_exit "tracks.md 非法状态标记 → 报错" 2 post-edit.sh "$(edit_json Edit "$W/conductor/tracks.md")"
printf '{"a":1,"a":2}\n' >"$W/web/i18n/en.json"
expect_exit "JSON 新增重复键 → 报错" 2 post-edit.sh "$(edit_json Edit "$W/web/i18n/en.json")"
printf '{"legacy":1,"legacy":2,"b":{"a":1},"a":1}\n' >"$W/web/i18n/en.json"
expect_exit "已知重复键 / 不同层级同名键 → 通过" 0 post-edit.sh "$(edit_json Edit "$W/web/i18n/en.json")"
printf '{"a":1,\n' >"$W/web/i18n/en.json"
expect_exit "非法 JSON → 报错" 2 post-edit.sh "$(edit_json Edit "$W/web/i18n/en.json")"
echo start >"$W/a.fmt"
printf '%s' "$(edit_json Edit "$W/a.fmt")" | "$S/post-edit.sh" >/dev/null 2>&1
if grep -q formatted "$W/a.fmt"; then ok "format_on_edit 命中 glob 时执行命令"; else bad "format_on_edit 命中 glob 时执行命令"; fi
mkdir -p "$W/billing" && echo x >"$W/billing/rate.go"
expect_out "敏感路径 → 注入 additionalContext" post-edit.sh "$(edit_json Edit "$W/billing/rate.go")" additionalContext
out=$(printf '%s' "$(edit_json Edit "$W/billing/rate.go")" | "$S/post-edit.sh" 2>&1)
if [ -z "$out" ]; then ok "敏感路径同 session 只提醒一次"; else bad "敏感路径同 session 只提醒一次" "$out"; fi
rm -f "${TMPDIR:-/tmp}/flow-sensitive-t1"

echo "link-worktree"
rm -f "$W/.env"
printf '%s' "$(jq -nc --arg c "$W" '{cwd:$c}')" | "$S/link-worktree.sh" 2>/dev/null
if [ -L "$W/.env" ]; then ok "worktree 自动软链 .env"; else bad "worktree 自动软链 .env"; fi
printf '%s' "$(jq -nc --arg c "$P" '{cwd:$c}')" | "$S/link-worktree.sh" 2>/dev/null
ok "主 checkout 不动（无报错）"

echo "sync-managed"
out=$(CLAUDE_PROJECT_DIR="$P" "$S/sync-managed.sh" --allow-main "$P" 2>&1)
case "$out" in *"已创建  conductor/workflow.md"*"已创建  dev-docs/TEAM_GUIDE.md"*) ok "首次 sync 创建两个托管文件" ;; *) bad "首次 sync 创建两个托管文件" "$out" ;; esac
grep -q '^# 项目补充' "$P/conductor/workflow.md" && ok "workflow.md 带项目补充骨架" || bad "workflow.md 带项目补充骨架"
"$S/sync-managed.sh" --check "$P" >/dev/null 2>&1 && ok "--check：最新 → 退出 0" || bad "--check：最新 → 退出 0"
# 模拟：项目补充里写了东西 + 托管区是旧版本
printf '\n- 自定义规则 XYZ\n' >>"$P/conductor/workflow.md"
sed -i.bak 's/flow:managed:begin v[0-9.]*/flow:managed:begin v0.0.1/; s/^## §0 停点表.*/## §0 旧标题/' "$P/conductor/workflow.md" && rm -f "$P/conductor/workflow.md.bak"
"$S/sync-managed.sh" --check "$P" >/dev/null 2>&1 && bad "--check：落后 → 退出 1" || ok "--check：落后 → 退出 1"
git -C "$P" add -A && git -C "$P" commit -qm sync
out=$("$S/sync-managed.sh" "$P" 2>&1)
case "$out" in *"拒绝"*) ok "已接入项目在主干上 sync → 拒绝" ;; *) bad "已接入项目在主干上 sync → 拒绝" "$out" ;; esac
git -C "$P" checkout -q -b chore/sync
out=$("$S/sync-managed.sh" "$P" 2>&1)
case "$out" in *"已同步  conductor/workflow.md (v0.0.1 → "*) ok "分支上 sync 覆盖托管区" ;; *) bad "分支上 sync 覆盖托管区" "$out" ;; esac
grep -q '自定义规则 XYZ' "$P/conductor/workflow.md" && ok "项目补充原样保留" || bad "项目补充原样保留"
grep -q '^## §0 停点表' "$P/conductor/workflow.md" && ok "托管区内容已恢复为模板" || bad "托管区内容已恢复为模板"
[ "$(grep -c 'flow:managed:begin' "$P/conductor/workflow.md")" = 1 ] && ok "托管标记仍只有一组" || bad "托管标记仍只有一组"
echo '# 手写的 workflow' >"$N/wf.md"
mkdir -p "$N/conductor" && cp "$N/wf.md" "$N/conductor/workflow.md"
out=$("$S/sync-managed.sh" --allow-main "$N" 2>&1)
case "$out" in *"无标记  conductor/workflow.md"*) ok "无标记的既有文件 → 不动" ;; *) bad "无标记的既有文件 → 不动" "$out" ;; esac
grep -qx '# 手写的 workflow' "$N/conductor/workflow.md" && ok "无标记文件内容未被改" || bad "无标记文件内容未被改"
git -C "$P" checkout -q main

echo "session-start / stop"
expect_out "SessionStart 注入 flow 上下文" session-start.sh "$(jq -nc --arg c "$P" '{cwd:$c}')" "本仓库启用 flow 工作流"
sed -i.bak 's/flow:managed:begin v[0-9.]*/flow:managed:begin v0.0.1/' "$P/conductor/workflow.md" && rm -f "$P/conductor/workflow.md.bak"
expect_out "托管区落后 → 提示 /flow:sync" session-start.sh "$(jq -nc --arg c "$P" '{cwd:$c}')" "/flow:sync"
git -C "$P" checkout -q -- conductor/workflow.md 2>/dev/null || true
out=$(printf '{}' | CLAUDE_PROJECT_DIR="$N" "$S/session-start.sh")
[ -z "$out" ] && ok "未启用 flow → SessionStart 输出为空" || bad "未启用 flow → SessionStart 输出为空" "$out"
echo dirty >"$P/dirty.txt"
expect_out "主 checkout 脏 → Stop 提醒" stop-hygiene.sh "$(jq -nc --arg c "$P" '{cwd:$c}')" "主 checkout"
rm -f "$P/dirty.txt"
git -C "$W" commit -q --allow-empty -m wip
git -C "$P" merge -q --no-edit feat/x
expect_out "已合并未删的 worktree → Stop 提醒 closeout" stop-hygiene.sh "$(jq -nc --arg c "$P" '{cwd:$c}')" "/flow:closeout"
echo wip >"$W/wip.txt"
out=$(printf '%s' "$(jq -nc --arg c "$W" '{cwd:$c}')" | "$S/stop-hygiene.sh")
case "$out" in *"当前 worktree 有未提交"*) bad "Stop 不报干活中的 worktree 变更" "$out" ;; *) ok "Stop 不报干活中的 worktree 变更" ;; esac

echo "init-project status"
st() { "$S/init-project.sh" status "$1" 2>/dev/null | sed -n "s/^$2=//p"; }
G="$TMP/green"
mkdir -p "$G" && echo "# idea" >"$G/README.md"
[ "$(st "$G" git)" = none ] && ok "没有 git → git=none" || bad "没有 git → git=none" "$(st "$G" git)"
[ "$(st "$G" maturity)" = greenfield ] && ok "只有 README → greenfield" || bad "只有 README → greenfield"
git -C "$G" init -q -b main
mkdir -p "$G/.claude" "$G/conductor" "$G/dev-docs"
echo x >"$G/CLAUDE.md" && echo x >"$G/conductor/workflow.md" && echo x >"$G/dev-docs/TEAM_GUIDE.md" && echo '{}' >"$G/.claude/settings.json"
[ "$(st "$G" maturity)" = greenfield ] && ok "git init + flow 自己的文件不会把空项目判成 brownfield" || bad "git init + flow 自己的文件不会把空项目判成 brownfield"
[ "$(st "$G" git)" = unborn ] && ok "还没提交 → git=unborn" || bad "还没提交 → git=unborn"
Bn="$TMP/brown"
mkdir -p "$Bn" && git -C "$Bn" init -q -b trunk && echo 'module x' >"$Bn/go.mod"
[ "$(st "$Bn" maturity)" = brownfield ] && ok "有 go.mod → brownfield" || bad "有 go.mod → brownfield"
[ "$(st "$Bn" main)" = trunk ] && ok "未提交仓库的主干取 HEAD 指向（trunk）" || bad "未提交仓库的主干取 HEAD 指向" "$(st "$Bn" main)"
F="$TMP/seeded"
mkdir -p "$F/conductor" && git -C "$F" init -q -b main && git -C "$F" config user.email t@t && git -C "$F" config user.name t
printf '{"last_successful_step": "3.3_initial_track_generated"}\n' >"$F/conductor/setup_state.json"
git -C "$F" add -A && git -C "$F" commit -qm "chore: adopt flow workflow"
[ "$(st "$F" conductor)" = flow-seeded ] && ok "0.1.0 伪造的 setup 状态 → flow-seeded" || bad "0.1.0 伪造的 setup 状态 → flow-seeded" "$(st "$F" conductor)"
git -C "$F" commit -q --allow-empty -m "conductor(setup): Add conductor set up files"
[ "$(st "$F" conductor)" = real ] && ok "有 conductor(setup) 提交 → real" || bad "有 conductor(setup) 提交 → real"
printf '{"last_successful_step": "2.3_tech_stack"}\n' >"$F/conductor/setup_state.json"
[ "$(st "$F" conductor)" = "partial:2.3_tech_stack" ] && ok "没跑完 → partial:<step>" || bad "没跑完 → partial:<step>" "$(st "$F" conductor)"

echo "init-project seed / finish / doctor"
I="$TMP/newproj"
mkdir -p "$I/.claude" && git -C "$I" init -q -b main
git -C "$I" config user.email t@t && git -C "$I" config user.name t
echo '{"permissions":{"allow":["Bash(make:*)"],"deny":["Bash(git push --force:*)"]},"model":"x"}' >"$I/.claude/settings.json"
printf 'node_modules/\n' >"$I/.gitignore"
out=$("$S/init-project.sh" seed "$I" --allow 'Bash(go test:*)' 2>&1)
for f in conductor/workflow.md dev-docs/TEAM_GUIDE.md conductor/backlog.md CLAUDE.md .conductor_templates/workflow.md; do
  [ -f "$I/$f" ] && ok "seed 生成 $f" || bad "seed 生成 $f" "$out"
done
for f in conductor/product.md conductor/tech-stack.md conductor/product-guidelines.md conductor/setup_state.json conductor/tracks.md .claude/flow.json; do
  [ -e "$I/$f" ] && bad "seed 不生成 ${f}（留给 conductor / finish）" || ok "seed 不生成 ${f}（留给 conductor / finish）"
done
cmp -s "$I/conductor/workflow.md" "$I/.conductor_templates/workflow.md" && ok ".conductor_templates/workflow.md 与 flow 规则同内容" || bad ".conductor_templates/workflow.md 与 flow 规则同内容"
git -C "$I" status --porcelain | grep -q conductor_templates && bad ".conductor_templates/ 不进提交（本地排除）" || ok ".conductor_templates/ 不进提交（本地排除）"
grep -q '.conductor_templates' "$I/.gitignore" && bad ".conductor_templates 不写进 .gitignore" || ok ".conductor_templates 不写进 .gitignore"
grep -q '/flow:triage' "$I/CLAUDE.md" && ok "CLAUDE.md 内联了 flow 段" || bad "CLAUDE.md 内联了 flow 段"
grep -q '{{FLOW_SECTION}}\|{{MAIN}}' "$I/CLAUDE.md" && bad "CLAUDE.md 不残留 FLOW_SECTION/MAIN 占位符" || ok "CLAUDE.md 不残留 FLOW_SECTION/MAIN 占位符"
jq -e '.model == "x" and (.permissions.allow | index("Bash(make:*)") == 0) and (.permissions.allow | index("Bash(go test:*)") != null)
  and ([.permissions.deny[] | select(. == "Bash(git push --force:*)")] | length == 1)
  and .enabledPlugins["flow@cc-flow"] and .extraKnownMarketplaces["cc-flow"].source.repo == "ethanzyang/cc-flow"' \
  "$I/.claude/settings.json" >/dev/null && ok "settings 合并：保留已有键、保序去重、加插件" || bad "settings 合并" "$(cat "$I/.claude/settings.json")"
grep -qxF '.claude/worktrees/' "$I/.gitignore" && grep -qxF 'node_modules/' "$I/.gitignore" && ok ".gitignore 追加且保留原内容" || bad ".gitignore 追加且保留原内容"
"$S/init-project.sh" seed "$I" >/dev/null 2>&1
[ "$(jq '.permissions.deny | length' "$I/.claude/settings.json")" = 9 ] && ok "重跑 seed settings 幂等" || bad "重跑 seed settings 幂等"
"$S/doctor.sh" "$I" >/dev/null 2>&1 && bad "conductor setup 没跑 → doctor 不通过" || ok "conductor setup 没跑 → doctor 不通过"

# 模拟 conductor setup：2.5 从 .conductor_templates 拷 workflow，其余各节产出文档，3.4 提交（git add -A）
cp "$I/.conductor_templates/workflow.md" "$I/conductor/workflow.md"
echo "# Product Guide" >"$I/conductor/product.md"
echo "# Technology Stack" >"$I/conductor/tech-stack.md"
printf '{"last_successful_step": "3.3_initial_track_generated"}\n' >"$I/conductor/setup_state.json"
git -C "$I" add -A && git -C "$I" commit -qm "conductor(setup): Add conductor set up files"
git -C "$I" show --stat HEAD | grep -q conductor_templates && bad "conductor 的 git add -A 不会带上 .conductor_templates/" || ok "conductor 的 git add -A 不会带上 .conductor_templates/"

RULES="$TMP/flow-rules.json"
echo '{"sensitive_paths":["*/billing/*"],"protected_paths":[{"glob":"*/gen/*","reason":"生成文件。"}],"format_on_edit":[{"globs":["*.go"],"cmd":"gofmt -w \"$FILE\""}]}' >"$RULES"
out=$("$S/init-project.sh" finish "$I" --rules "$RULES" 2>&1)
[ -d "$I/.conductor_templates" ] && bad "finish 删掉 .conductor_templates/" "$out" || ok "finish 删掉 .conductor_templates/"
[ -f "$I/conductor/tracks.md" ] && ok "没建首个 track → finish 补空 tracks.md" || bad "没建首个 track → finish 补空 tracks.md"
jq -e '.main_branch == "main" and .sensitive_paths == ["*/billing/*"] and (.protected_paths | length == 5)
  and (.protected_paths | map(.glob) | index("*/.env") != null) and (.format_on_edit | length == 1)' "$I/.claude/flow.json" >/dev/null &&
  ok "flow.json = 模板默认项 + 规则（数组合并）" || bad "flow.json = 模板默认项 + 规则" "$(cat "$I/.claude/flow.json" 2>/dev/null)"
out=$("$S/init-project.sh" finish "$I" --rules "$RULES" 2>&1)
case "$out" in *"已存在  .claude/flow.json"*"--rules 未应用"*) ok "重跑 finish 不覆盖已有 flow.json" ;; *) bad "重跑 finish 不覆盖已有 flow.json" "$out" ;; esac
"$S/doctor.sh" "$I" >/dev/null 2>&1 && ok "完整接入后 doctor 通过" || bad "完整接入后 doctor 通过" "$("$S/doctor.sh" "$I" 2>&1 | grep '✗')"
echo '{"protected_paths": {"glob": "x"}}' >"$I/.claude/flow.json"
"$S/doctor.sh" "$I" >/dev/null 2>&1 && bad "doctor 发现字段类型错误" || ok "doctor 发现字段类型错误"

# 已有提交的项目：seed 在 worktree 里做，排除同样生效
git -C "$I" checkout -q -- .claude/flow.json 2>/dev/null || true
git -C "$I" add -A && git -C "$I" commit -qm "chore: adopt flow workflow"
git -C "$I" worktree add -q -b redo "$I/.claude/worktrees/redo" main
"$S/init-project.sh" seed "$I/.claude/worktrees/redo" >/dev/null 2>&1
[ -f "$I/.claude/worktrees/redo/.conductor_templates/workflow.md" ] && ok "worktree 里 seed 放模板" || bad "worktree 里 seed 放模板"
git -C "$I/.claude/worktrees/redo" status --porcelain | grep -q conductor_templates && bad "worktree 里 .conductor_templates/ 同样被排除" || ok "worktree 里 .conductor_templates/ 同样被排除"

# conductor 2.5 没用 flow 模板、拿自带的覆盖了 → finish 报异常且不激活
J="$TMP/clobbered"
mkdir -p "$J" && git -C "$J" init -q -b main
"$S/init-project.sh" seed "$J" >/dev/null 2>&1
echo "# Conductor default workflow" >"$J/conductor/workflow.md"
"$S/init-project.sh" finish "$J" >/dev/null 2>&1 && bad "workflow.md 被覆盖 → finish 失败" || ok "workflow.md 被覆盖 → finish 失败"
[ -e "$J/.claude/flow.json" ] && bad "workflow.md 被覆盖 → 不写 flow.json" || ok "workflow.md 被覆盖 → 不写 flow.json"

echo
echo "passed: $pass  failed: $failn"
[ "$failn" = 0 ]
