#!/usr/bin/env bash
# /flow:init 的确定性部分：只建缺失的骨架文件、合并 settings、补 .gitignore，从不覆盖已有内容。
# 需要判断与填写的部分（项目补充、CLAUDE.md、flow.json 的规则）由 skill 驱动模型用 Edit 完成。
#
# 用法：init-project.sh <目标目录> [--main <主干名>] [--allow '<permissions.allow 条目>']...
set -u
. "$(dirname "$0")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "需要 jq（macOS: brew install jq）" >&2; exit 1; }

target=""
main=""
extra_allow="[]"
while [ $# -gt 0 ]; do
  case "$1" in
    --main) main="$2"; shift 2 ;;
    --allow) extra_allow=$(jq -c --arg a "$2" '. + [$a]' <<<"$extra_allow"); shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) target="$1"; shift ;;
  esac
done
[ -n "$target" ] || { echo "用法：init-project.sh <目标目录> [--main <主干>] [--allow <条目>]..." >&2; exit 64; }
target=$(cd "$target" && pwd) || exit 1
tpl="$FLOW_ROOT/templates"

if [ -z "$main" ]; then
  main=$(git -C "$target" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
fi
if [ -z "$main" ]; then
  for b in main master; do
    if git -C "$target" show-ref -q --verify "refs/heads/$b"; then main=$b; break; fi
  done
fi
main=${main:-main}

created() { echo "已创建  $1"; }
kept() { echo "已存在  $1（未改动）"; }

# 1) conductor 骨架（conductor 插件的 new-track/implement 要求 product.md / tech-stack.md / workflow.md 存在）
(cd "$tpl" && find conductor -type f) | while IFS= read -r rel; do
  if [ -e "$target/$rel" ]; then
    kept "$rel"
  else
    mkdir -p "$(dirname "$target/$rel")"
    cp "$tpl/$rel" "$target/$rel"
    created "$rel"
  fi
done

# 2) 托管文件：conductor/workflow.md（+ 项目补充骨架）与 dev-docs/TEAM_GUIDE.md
"$FLOW_ROOT/scripts/sync-managed.sh" --allow-main "$target" || true

# 3) CLAUDE.md：不存在才从模板生成（flow 段内联）；已存在则由模型插入 flow 段
if [ -e "$target/CLAUDE.md" ]; then
  if grep -q '/flow:triage' "$target/CLAUDE.md"; then
    kept "CLAUDE.md（已含 flow 段）"
  else
    echo "待插入  CLAUDE.md —— 已存在但没有 flow 段：把 templates/CLAUDE.flow-section.md 插到命令段之后（{{MAIN}} → ${main}）"
  fi
else
  secfile=$(mktemp)
  sed "s/{{MAIN}}/$main/g" "$tpl/CLAUDE.flow-section.md" >"$secfile"
  awk -v f="$secfile" '$0 == "{{FLOW_SECTION}}" { while ((getline l < f) > 0) print l; next } { print }' \
    "$tpl/CLAUDE.md" >"$target/CLAUDE.md"
  rm -f "$secfile"
  created "CLAUDE.md（含 {{NAME}} 等占位符，待填）"
fi

# 4) .gitignore
touch "$target/.gitignore"
for line in ".claude/worktrees/" ".claude/settings.local.json"; do
  if grep -qxF "$line" "$target/.gitignore"; then :; else
    printf '%s\n' "$line" >>"$target/.gitignore"
    echo "已追加  .gitignore: $line"
  fi
done

# 5) .claude/settings.json：插件自动安装 + 权限基线（合并，保序去重，不删用户已有条目）
mkdir -p "$target/.claude"
settings="$target/.claude/settings.json"
[ -s "$settings" ] || echo '{}' >"$settings"
tmp=$(mktemp)
jq --argjson extra "$extra_allow" '
  def addu($xs): reduce $xs[] as $x (.; if any(.[]; . == $x) then . else . + [$x] end);
  .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) + {
      "cc-flow": {source: {source: "github", repo: "ethanzyang/cc-flow"}},
      "conductor-cc": {source: {source: "git", url: "https://github.com/pilotparpikhodjaev/conductor_cc.git"}}
    })
  | .enabledPlugins = ((.enabledPlugins // {}) + {"flow@cc-flow": true, "conductor@conductor-cc": true})
  | .permissions = (.permissions // {})
  | .permissions.allow = ((.permissions.allow // []) | addu([
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git branch:*)",
      "Bash(git fetch:*)", "Bash(git worktree:*)", "Bash(git add:*)", "Bash(git commit:*)",
      "Bash(ls:*)"
    ] + $extra))
  | .permissions.deny = ((.permissions.deny // []) | addu([
      "Bash(rm -rf:*)", "Bash(DROP TABLE:*)", "Bash(TRUNCATE:*)", "Bash(git push --force:*)",
      "Read(./.env)", "Read(./.env.*)", "Edit(./.env)", "Edit(./.env.*)", "Edit(./.github/workflows/**)"
    ]))
' "$settings" >"$tmp" && cat "$tmp" >"$settings"
rm -f "$tmp"
echo "已合并  .claude/settings.json（extraKnownMarketplaces / enabledPlugins / permissions）"

# 6) .claude/flow.json 放最后：它一出现，flow 的 hook 就对这个仓库生效
if [ -e "$target/.claude/flow.json" ]; then
  kept ".claude/flow.json"
else
  jq --arg m "$main" '.main_branch = $m' "$tpl/flow.json" >"$target/.claude/flow.json"
  created ".claude/flow.json（main_branch=${main}）"
fi

echo
echo "主干：$main"
echo "下一步：填 conductor/workflow.md 文末 P1–P6、CLAUDE.md 占位符、conductor/{product,tech-stack}.md、.claude/flow.json 规则；然后跑 doctor.sh。"
