#!/usr/bin/env bash
# /flow:init 的确定性部分（flow 0.6：conductor 为底座），分三步，夹着 conductor 的 /conductor:setup 用：
#
#   status <目录>            只读体检：git 状态 / 新旧项目 / conductor 状态 / flow 状态（key=value）
#   seed   <目录> [--main X] [--allow '<permissions.allow 条目>']...
#                            conductor setup 之前：放 flow 的规则与接入配置——conductor/workflow.md（托管区 +
#                            项目补充骨架）、dev-docs/TEAM_GUIDE.md、conductor/backlog.md、CLAUDE.md（不存在时）、
#                            .gitignore、settings.json（flow + conductor 两个插件）。
#                            conductor/workflow.md 同内容放一份到 .conductor_templates/workflow.md（只在本地排除）
#                            ——conductor setup 2.5 会优先拷它，于是拷进去的是 flow 的规则。
#                            不建 product / tech-stack 等文档（那是 conductor 访谈的产物），不写 flow.json。
#   design <目录> [--dir design-system]
#                            设计模块：设计目录骨架（README）+ 托管的 SYNC.md（含项目补充 D1–D3）+
#                            gitignore .project-id；已有 flow.json 时顺带登记 design.dir。
#   finish <目录> [--rules <规则 JSON 文件>] [--main X]
#                            conductor setup 之后：清掉 .conductor_templates/，缺 tracks.md 则补空的，
#                            最后写 .claude/flow.json（模板 + 规则）——它一出现 flow 的 hook 就生效，
#                            所以必须是最后一步，且用脚本写（hook 生效后主干上的 Edit 会被拦）。
#
# 原则：只建缺失文件、从不覆盖；settings 合并保序去重、不删用户已有条目。
set -u
. "$(dirname "$0")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "需要 jq（macOS: brew install jq）" >&2; exit 1; }

cmd="${1:-}"
[ $# -gt 0 ] && shift
target=""
main=""
rules=""
design_dir=""
extra_allow="[]"
while [ $# -gt 0 ]; do
  case "$1" in
    --main) main="$2"; shift 2 ;;
    --rules) rules="$2"; shift 2 ;;
    --dir) design_dir="$2"; shift 2 ;;
    --allow) extra_allow=$(jq -c --arg a "$2" '. + [$a]' <<<"$extra_allow"); shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) target="$1"; shift ;;
  esac
done
usage() { echo "用法：init-project.sh status|seed|design|finish <目录> [选项]" >&2; exit 64; }
[ -n "$target" ] || usage
target=$(cd "$target" && pwd) || exit 1
tpl="$FLOW_ROOT/templates"

created() { echo "已创建  $1"; }
kept() { echo "已存在  $1（未改动）"; }

detect_main() {
  [ -n "$main" ] && { printf '%s' "$main"; return; }
  local m b
  m=$(git -C "$target" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  if [ -z "$m" ]; then
    for b in main master; do
      if git -C "$target" show-ref -q --verify "refs/heads/$b"; then m=$b; break; fi
    done
  fi
  # 还没有任何提交的仓库：HEAD 指向的就是将来的主干
  if [ -z "$m" ] && ! git -C "$target" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    m=$(git -C "$target" symbolic-ref --short HEAD 2>/dev/null)
  fi
  printf '%s' "${m:-main}"
}

# ---------------------------------------------------------------- status
do_status() {
  local git_state maturity cstate flow wf_state wf_ver files code
  if ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    git_state=none
  elif git -C "$target" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    git_state=commits
  else
    git_state=unborn
  fi

  # 新/旧项目：忽略 flow 与 conductor 自己生成的东西和通用文档，剩下有依赖清单或源码就算旧项目。
  # （conductor 自己的判定把「有 .git」就当旧项目，会让刚 git init 的空目录跳过「你想做什么」
  #  与需求访谈——所以由 flow 先判、再明确告诉 conductor。）
  if [ "$git_state" = none ]; then
    files=$(cd "$target" && find . -type f -not -path './.git/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's#^\./##')
  else
    files=$(git -C "$target" ls-files -co --exclude-standard 2>/dev/null)
  fi
  code=$(printf '%s\n' "$files" | grep -vE '^(\.claude/|\.conductor_templates/|conductor/|dev-docs/|docs/specs/|CLAUDE\.md$|AGENTS\.md$|README[^/]*$|LICENSE[^/]*$|\.gitignore$|\.gitattributes$|\.editorconfig$)' |
    grep -E '(^|/)(package\.json|go\.mod|requirements\.txt|pyproject\.toml|Cargo\.toml|pom\.xml|build\.gradle(\.kts)?|Gemfile|composer\.json|pubspec\.yaml|Package\.swift)$|\.(go|py|js|jsx|ts|tsx|mjs|cjs|rs|java|kt|rb|php|swift|dart|c|cc|cpp|h|hpp|cs|vue|svelte|scala|ex|exs|sh)$' | head -1)
  if [ -n "$code" ]; then maturity=brownfield; else maturity=greenfield; fi

  # conductor setup 状态：none / partial:<step> / real / flow-seeded
  # flow-seeded = flow 0.1.0 直接写了「已完成」、其实没跑过访谈（setup_state 由 adopt 提交引入，
  # 且历史里没有 conductor(setup) 提交）
  local st="$target/conductor/setup_state.json" step added
  if [ ! -f "$st" ]; then
    cstate=none
  else
    step=$(jq -r '.last_successful_step // ""' "$st" 2>/dev/null)
    if [ "$step" != "3.3_initial_track_generated" ]; then
      cstate="partial:$step"
    else
      cstate=real
      if [ "$git_state" = commits ]; then
        added=$(git -C "$target" log --diff-filter=A --format=%s -- conductor/setup_state.json 2>/dev/null | tail -1)
        if [ "$added" = "chore: adopt flow workflow" ] &&
          ! git -C "$target" log --format=%s 2>/dev/null | grep -q '^conductor(setup)'; then
          cstate=flow-seeded
        fi
      fi
    fi
  fi

  if [ -f "$target/.claude/flow.json" ]; then flow=adopted; else flow=none; fi

  local wf="$target/conductor/workflow.md"
  if [ ! -f "$wf" ]; then
    wf_state=none
  else
    wf_ver=$(sed -n 's/.*flow:managed:begin v\([0-9][0-9.]*\).*/\1/p' "$wf" | head -1)
    if [ -n "$wf_ver" ]; then wf_state="managed:v$wf_ver"; else wf_state=unmarked; fi
  fi

  echo "git=$git_state"
  echo "maturity=$maturity"
  echo "conductor=$cstate"
  echo "flow=$flow"
  echo "workflow=$wf_state"
  echo "main=$(detect_main)"
  echo "plugin=v$(flow_plugin_version)"
}

# ---------------------------------------------------------------- seed
do_seed() {
  main=$(detect_main)

  # 1) 托管文件：conductor/workflow.md（+ 项目补充骨架）与 dev-docs/TEAM_GUIDE.md
  "$FLOW_ROOT/scripts/sync-managed.sh" --allow-main "$target" || true

  # 2) 给 conductor setup 2.5 用的模板：同内容；只在本地排除，不进提交
  if [ -f "$target/conductor/workflow.md" ] && grep -q 'flow:managed:begin' "$target/conductor/workflow.md"; then
    mkdir -p "$target/.conductor_templates"
    cp "$target/conductor/workflow.md" "$target/.conductor_templates/workflow.md"
    created ".conductor_templates/workflow.md（给 conductor setup 2.5 拷贝；finish 时删除）"
    local excl
    excl=$(git -C "$target" rev-parse --git-path info/exclude 2>/dev/null)
    if [ -n "$excl" ]; then
      case "$excl" in /*) ;; *) excl="$target/$excl" ;; esac
      mkdir -p "$(dirname "$excl")"
      grep -qxF '.conductor_templates/' "$excl" 2>/dev/null || printf '%s\n' '.conductor_templates/' >>"$excl"
    fi
  fi

  # 3) conductor/backlog.md（flow 的概念，conductor 不建）
  if [ -e "$target/conductor/backlog.md" ]; then kept "conductor/backlog.md"; else
    mkdir -p "$target/conductor"
    cp "$tpl/conductor/backlog.md" "$target/conductor/backlog.md"
    created "conductor/backlog.md"
  fi

  # 4) CLAUDE.md：不存在才从模板生成（flow 段内联）；已存在则由模型插入 / 替换 flow 段
  if [ -e "$target/CLAUDE.md" ]; then
    if grep -q '/flow:triage' "$target/CLAUDE.md"; then
      kept "CLAUDE.md（已含 flow 段）"
    elif grep -q '/flow:shape' "$target/CLAUDE.md"; then
      echo "待替换  CLAUDE.md —— 含 0.5 的 flow 段（定形 / build）：用 templates/CLAUDE.flow-section.md 替换工作流段与分支段（{{MAIN}} → ${main}）"
    else
      echo "待插入  CLAUDE.md —— 已存在但没有 flow 段：把 templates/CLAUDE.flow-section.md 插到命令段之后（{{MAIN}} → ${main}）"
    fi
  else
    local secfile
    secfile=$(mktemp)
    sed "s/{{MAIN}}/$main/g" "$tpl/CLAUDE.flow-section.md" >"$secfile"
    awk -v f="$secfile" '$0 == "{{FLOW_SECTION}}" { while ((getline l < f) > 0) print l; next } { print }' \
      "$tpl/CLAUDE.md" >"$target/CLAUDE.md"
    rm -f "$secfile"
    created "CLAUDE.md（含 {{NAME}} 等占位符，待填）"
  fi

  # 5) .gitignore
  touch "$target/.gitignore"
  local line
  for line in ".claude/worktrees/" ".claude/settings.local.json"; do
    if ! grep -qxF "$line" "$target/.gitignore"; then
      printf '%s\n' "$line" >>"$target/.gitignore"
      echo "已追加  .gitignore: $line"
    fi
  done

  # 6) .claude/settings.json：插件自动安装（flow + conductor）+ 权限基线（已有条目不删）。
  #    deny 基线只拒读改 .env 与 CI 配置；致命命令交给 flow 的 Bash 守卫按词法判（前缀 deny 误拦太多）。
  mkdir -p "$target/.claude"
  local settings="$target/.claude/settings.json" tmp
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
        "Read(./.env)", "Read(./.env.*)", "Edit(./.env)", "Edit(./.env.*)", "Edit(./.github/workflows/**)"
      ]))
  ' "$settings" >"$tmp" && cat "$tmp" >"$settings"
  rm -f "$tmp"
  echo "已合并  .claude/settings.json（extraKnownMarketplaces / enabledPlugins / permissions）"

  echo
  echo "主干：$main"
  echo "下一步：跑 /conductor:setup（按 /flow:init 的覆盖约定），完成后填项目补充 P1–P6，再 finish。"
}

# ---------------------------------------------------------------- design
do_design() {
  local d="${design_dir:-design-system}" main_ line
  main_=$(detect_main)
  mkdir -p "$target/$d"

  if [ -e "$target/$d/README.md" ]; then kept "$d/README.md"; else
    cp "$tpl/design/README.md" "$target/$d/README.md"
    created "$d/README.md（骨架，{{NAME}} 等待填；首次从 Claude Design 全量拉回时会被替换）"
  fi

  "$FLOW_ROOT/scripts/sync-managed.sh" --allow-main --design "$d" "$target" | grep -F "$d/SYNC.md" || true

  touch "$target/.gitignore"
  line="$d/.project-id"
  if ! grep -qxF "$line" "$target/.gitignore"; then
    printf '%s\n' "$line" >>"$target/.gitignore"
    echo "已追加  .gitignore: $line"
  fi

  if [ -f "$target/CLAUDE.md" ] && grep -q '/flow:design push' "$target/CLAUDE.md"; then
    kept "CLAUDE.md（已含设计段）"
  else
    echo "待插入  CLAUDE.md 设计段：templates/CLAUDE.design-section.md（{{DESIGN_DIR}} → ${d}），放在工作流段之后"
  fi

  # 已接入的项目：直接登记进 flow.json；首次接入的由 finish 自动识别
  local cfg="$target/.claude/flow.json" tmp
  if [ -f "$cfg" ]; then
    tmp=$(mktemp)
    jq --arg d "$d" '
      def addu($xs): reduce $xs[] as $x (.; if any(.[]; . == $x) then . else . + [$x] end);
      .design = {dir: $d} | .worktree_links = ((.worktree_links // [".env"]) | addu([$d + "/.project-id"]))
    ' "$cfg" >"$tmp" && cat "$tmp" >"$cfg"
    rm -f "$tmp"
    echo "已登记  .claude/flow.json: design.dir=$d"
  fi
  echo
  echo "主干：${main_}；下一步：填 $d/SYNC.md 项目补充 D1–D3、workflow.md P4；各成员首次用 /flow:design push 建自己的云端副本。"
}

# ---------------------------------------------------------------- finish
do_finish() {
  main=$(detect_main)

  # 1) 清掉给 conductor setup 用的模板
  if [ -d "$target/.conductor_templates" ]; then
    rm -f "$target/.conductor_templates/workflow.md"
    rmdir "$target/.conductor_templates" 2>/dev/null ||
      echo "注意    .conductor_templates/ 里还有别的文件，未删除（不是 flow 放的）"
    [ -d "$target/.conductor_templates" ] || echo "已删除  .conductor_templates/"
  fi

  # 2) workflow.md 必须带托管标记：conductor 2.5 若没拷 flow 的模板而用了自带的、或是手写的旧文件，
  #    都会丢标记——兜底报出来，不激活
  if [ ! -f "$target/conductor/workflow.md" ] || ! grep -q 'flow:managed:begin' "$target/conductor/workflow.md"; then
    echo "异常    conductor/workflow.md 缺失或没有 flow 托管标记（conductor setup 可能用了自带模板覆盖）。" >&2
    echo "        处理：改名为 workflow.pre-flow.md 后重跑 seed，再把项目补充填回去。" >&2
    return 1
  fi

  # 3) 首个 track 没建时，tracks.md 可能不存在
  if [ -e "$target/conductor/tracks.md" ]; then kept "conductor/tracks.md"; else
    cp "$tpl/conductor/tracks.md" "$target/conductor/tracks.md"
    created "conductor/tracks.md（空）"
  fi

  # 4) 最后写 flow.json
  if [ -e "$target/.claude/flow.json" ]; then
    kept ".claude/flow.json"
    [ -n "$rules" ] && echo "注意    已有 flow.json，--rules 未应用；要改规则请在 worktree 里编辑它。"
  else
    local r='{}' s dd
    if [ -n "$rules" ]; then
      r=$(jq -c . "$rules") || { echo "--rules 不是合法 JSON：$rules" >&2; return 1; }
    fi
    # 设计模块：rules 没写 design 时，按托管的 <目录>/SYNC.md 自动识别
    if ! jq -e '.design' >/dev/null 2>&1 <<<"$r"; then
      for s in "$target"/*/SYNC.md; do
        [ -f "$s" ] && grep -q 'flow:managed:begin' "$s" || continue
        dd=$(basename "$(dirname "$s")")
        r=$(jq -c --arg d "$dd" '. + {design: {dir: $d}, worktree_links: ((.worktree_links // []) + [$d + "/.project-id"])}' <<<"$r")
        break
      done
    fi
    mkdir -p "$target/.claude"
    # 数组字段：模板默认项 + 规则追加（去重）；标量字段：规则覆盖
    jq --arg m "$main" --argjson r "$r" '
      def addu($xs): reduce $xs[] as $x (.; if any(.[]; . == $x) then . else . + [$x] end);
      .main_branch = $m
      | reduce ($r | to_entries[]) as $e (.;
          if ($e.value | type) == "array" then .[$e.key] = ((.[$e.key] // []) | addu($e.value))
          else .[$e.key] = $e.value end)
    ' "$tpl/flow.json" >"$target/.claude/flow.json" || return 1
    created ".claude/flow.json（main_branch=${main}；flow 的 hook 自此对本仓库生效）"
  fi
}

case "$cmd" in
  status) do_status ;;
  seed) do_seed ;;
  design) do_design ;;
  finish) do_finish ;;
  *) usage ;;
esac
