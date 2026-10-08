#!/usr/bin/env python3
"""guard-bash.py 的表驱动用例：`python3 tests/guard-bash.test.py`（依赖 git）。

造临时 git 仓库 + flow.json 当 fixture，往守卫 stdin 喂 hook JSON（只解析、从不执行命令），断言退出码。
每一类拦截都有正例与反例；ALLOW 开头几组是旧版按子串匹配的 guard-bash.sh 误拦过的命令——
「只是提到、不会执行」的文本（commit message、heredoc 正文、grep 的模式）以及 `2>/dev/null`、`2>&1`，
改守卫时它们必须继续放行。
"""
import atexit
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "..", "plugins", "flow", "scripts", "guard-bash.py")


def sh(*args, cwd=None):
    subprocess.run(list(args), cwd=cwd, check=True, capture_output=True)


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def git_repo(path, branch="main"):
    os.makedirs(path, exist_ok=True)
    sh("git", "init", "-q", "-b", branch, path)
    sh("git", "-C", path, "config", "user.email", "t@t")
    sh("git", "-C", path, "config", "user.name", "t")
    sh("git", "-C", path, "config", "core.hooksPath", "/dev/null")


def commit_all(path):
    sh("git", "-C", path, "add", "-A")
    sh("git", "-C", path, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init")


TMP = os.path.realpath(tempfile.mkdtemp(prefix="flow-guard-bash."))
atexit.register(shutil.rmtree, TMP, True)

# ---------- MAIN：启用了 flow 的项目（主 checkout 停在 main）+ 一个内嵌 worktree + 一个放在外面的 worktree ----------
MAIN = os.path.join(TMP, "proj")
git_repo(MAIN)
write(os.path.join(MAIN, ".claude/flow.json"), json.dumps({
    "version": 1,
    "main_branch": "main",
    "worktree_links": [".env", "design-system/.project-id"],
    "protected_paths": [
        {"glob": "*/.env", "reason": ".env 禁止修改。"},
        {"glob": "*/.github/workflows/*", "reason": "CI 配置禁止修改。"},
    ],
    "no_full_rewrite": [{"glob": "*/web/i18n/*.json", "reason": "locale 有重复键。"}],
}))
write(os.path.join(MAIN, ".gitignore"), ".env\n.claude/worktrees/\ndesign-system/.project-id\n")
write(os.path.join(MAIN, ".env"), "SECRET=1\n")
write(os.path.join(MAIN, "design-system/.project-id"), "uuid\n")
write(os.path.join(MAIN, "design-system/README.md"), "# ds\n")
write(os.path.join(MAIN, "web/i18n/en.json"), '{"a":1}\n')
write(os.path.join(MAIN, ".github/workflows/ci.yml"), "on: push\n")
write(os.path.join(MAIN, "conductor/tracks/t1/design/a.md"), "# snapshot\n")
write(os.path.join(MAIN, "conductor/tracks/t1/design-r2/notes.md"), "# notes\n")
write(os.path.join(MAIN, "conductor/tracks/t1/spec.md"), "# spec\n")
write(os.path.join(MAIN, "ok.sh"), "set -e\nls -la\nrm -rf ./dist\n")
write(os.path.join(MAIN, "bad.sh"), "set -e\nrm -rf ~/\n")
# 项目自己的脚本：写受保护的本地文件、回改快照是它的本职（只查通用致命项）；按参数删目录
write(os.path.join(MAIN, "deploy.sh"), "set -e\necho KEY=1 >> .env\nsed -i '' s/a/b/ conductor/tracks/t1/design/a.md\n"
      "rm -rf \"${1:-./dist}/\"\n")
write(os.path.join(MAIN, "rmarg.sh"), "set -e\nrm -rf \"$1/\"\n")
# 测试脚本式的文件：引号里「提到」危险命令与 <<'SQL'，注释里有撇号——都不会执行
write(os.path.join(MAIN, "mentions.sh"), """# don't panic: 下面只是正反例的文字
gb "heredoc 喂给 psql 的 DROP → 拦" 2 "$W" "psql -d app <<'SQL'
DROP TABLE users;
SQL"
gb "rm -rf / → 拦" 2 "$W" 'cd x && rm -rf /'
echo "git push --force origin main"
""")
commit_all(MAIN)
WORKTREE = os.path.join(MAIN, ".claude/worktrees/some-track")
sh("git", "-C", MAIN, "worktree", "add", "-q", "-b", "feat/x", WORKTREE, "main")
os.symlink(os.path.join(MAIN, ".env"), os.path.join(WORKTREE, ".env"))  # link-worktree.sh 的产物
SIBLING = os.path.join(TMP, "proj-sib")
sh("git", "-C", MAIN, "worktree", "add", "-q", "-b", "feat/sib", SIBLING, "main")

# ---------- OUTSIDE：仓库外的目录，里面有同名的 .env / design 快照 / locale ----------
OUTSIDE = os.path.join(TMP, "outside")
write(os.path.join(OUTSIDE, ".env"), "X=1\n")
write(os.path.join(OUTSIDE, "conductor/tracks/t1/design/a.md"), "# x\n")
write(os.path.join(OUTSIDE, "web/i18n/en.json"), "{}\n")

# ---------- DEV：主干叫 develop、测试库口径改成 scratch_* 的项目 ----------
DEV = os.path.join(TMP, "dev")
git_repo(DEV, "develop")
write(os.path.join(DEV, ".claude/flow.json"), json.dumps({
    "main_branch": "develop", "bash_guard": {"test_db_pattern": "^scratch_"}}))
commit_all(DEV)

# ---------- 未启用 flow / flow.json 坏掉的仓库 ----------
NOFLOW = os.path.join(TMP, "noflow")
git_repo(NOFLOW)
write(os.path.join(NOFLOW, ".env"), "X=1\n")
BROKEN = os.path.join(TMP, "broken")
git_repo(BROKEN)
write(os.path.join(BROKEN, ".claude/flow.json"), "{ not json")

# (命令, 命令执行时的 cwd[, CLAUDE_PROJECT_DIR，缺省 MAIN])
ALLOW = [
    # 旧版误拦：2>/dev/null、2>&1 不是写文件；正文 / 参数里「提到」的命令不会执行
    ("ls conductor/tracks/t1 2>/dev/null", MAIN),
    ("ls -la .env 2>&1", MAIN),
    ("cat .env 2>/dev/null | head -1", MAIN),
    ("echo hi 2>&1 >/dev/null", WORKTREE),
    ('gh pr create --body "守卫会拦 push --force 和 rm -rf ~"', WORKTREE),
    ('git commit -m "guard: block TRUNCATE, DROP TABLE and rm -rf / in hook"', WORKTREE),
    ('git commit -m "$(cat <<\'EOF\'\nfix: don\'t rm -rf / or DROP TABLE trades\nTRUNCATE audit_log\nEOF\n)"', WORKTREE),
    ("cat > notes.md <<'EOF'\nDROP TABLE users;\nTRUNCATE trades;\nrm -rf /\ngit push --force origin main\nEOF", WORKTREE),
    ("cat >> conductor/tracks.md <<'EOF'\n详见 conductor/tracks/t1/design/a.md\nEOF", WORKTREE),
    ("cd conductor/tracks/t1 && ls -R | head -60; wc -l *.md 2>/dev/null", WORKTREE),
    ("S=/tmp/x; cat > $S/close-pr.md <<'EOF'\nconductor/tracks/t1/design\nEOF", WORKTREE),
    ("cat conductor/tracks/t1/design/a.md 2>/dev/null | head", WORKTREE),
    ("cd conductor/tracks/t1 && find design -type f 2>&1 | head", WORKTREE),
    ('git add conductor/tracks/t1/design && git commit -m "design(t1): pull\nCo-Authored-By: C <noreply@example.com>"', WORKTREE),
    ("sed -i '' s/a/b/ conductor/tracks/t1/spec.md && git add conductor/tracks/t1/design-input.md", WORKTREE),
    ("cat web/i18n/en.json 2>&1 | jq .", WORKTREE),
    ("grep -rn 'DROP TABLE' packages/db", MAIN),
    ("grep -rn dropdb packages apps", MAIN),
    ("rg -n 'TRUNCATE' packages", MAIN),
    ("git grep -n dropdb -- packages", MAIN),
    ("which dropdb psql mysql sqlite3", MAIN),
    # shlex 解析不了的引号：退化切词后也不能误拦
    ("grep -rhoE \"[\\`'\\\"]/(accounts|audit)[^\\`'\\\" ?]*\" apps", MAIN),
    # rm / find：普通目录、worktree 里、带 ${VAR:?} 守护
    ("rm -rf node_modules dist", WORKTREE),
    ("rm -rf node_modules", MAIN),
    ("rm -rf .claude/worktrees/foo", MAIN),
    ("S=/tmp/scratch; rm -rf $S/out", MAIN),
    ('rm -rf "${OUT_DIR:?}/"', MAIN),
    ("for d in a b; do rm -rf $d; done", WORKTREE),
    ("rm -rf *", WORKTREE),
    ("rm -rf *", SIBLING),
    ("rm -rf .", WORKTREE),
    ("rm -rf design-system", WORKTREE),
    ("find . -name '*.log' -delete", MAIN),
    ("find dist -delete", WORKTREE),
    # git：功能分支随便推；reset --hard 能从 reflog 找回，不拦；worktree 里 clean -x 只删 worktree 自己的东西
    ("git push -u origin chore/x", WORKTREE),
    ("git push --force origin x", WORKTREE),
    ("git push --force-with-lease origin chore/x", WORKTREE),
    ("git push -f", WORKTREE),  # worktree 停在 feat/x
    ("git -c http.proxyAuthMethod=basic push origin HEAD", MAIN),
    ("git push origin main", WORKTREE),
    ("git reset --hard origin/main", WORKTREE),
    ("git reset --hard HEAD~1", MAIN),
    ("git clean -fdx", WORKTREE),
    ("git clean -fdx", SIBLING),
    ("git clean -fd", MAIN),
    # SQL：测试库随便删；只读查询；MySQL 的 TRUNCATE() 是数值函数
    ("docker exec pg dropdb -U app app_test && echo dropped", MAIN),
    ('docker exec pg psql -U app -d app_test -c "TRUNCATE trades"', MAIN),
    ('docker exec pg psql -U app -d postgres -Atc "select datname from pg_database"', MAIN),
    ("psql postgres://u:p@localhost:5432/app_test -c 'drop schema public cascade'", MAIN),
    ("cat <<'SQL' | docker exec -i pg psql -U app -d app\nselect count(*) from trades;\nSQL", MAIN),
    ('mysql -u root -D app_test -e "DROP TABLE users"', MAIN),
    ('mysql -uroot -psecret app -e "SELECT TRUNCATE(price, 2) FROM t"', MAIN),
    ("mysqladmin -u root drop test_scratch", MAIN),
    ('sqlite3 app_test.db "DROP TABLE users"', MAIN),
    ('sqlite3 :memory: "DROP TABLE x"', MAIN),
    ('sqlite3 app.db "select * from users"', MAIN),
    # docker：停服务、删容器、测试项目的卷
    ("docker rm -f some-redis >/dev/null", MAIN),
    ("docker compose -f infra/docker-compose.yml down", MAIN),
    ("timeout 120 docker compose -f infra/docker-compose.yml down", MAIN),
    ("docker compose -p app_test -f infra/docker-compose.yml down -v", MAIN),
    # 本地文件：同名但不受保护、worktree 里的软链、仓库外的同名文件、空位上建软链
    ("echo X >> .env.example", MAIN),
    ("mv .env.example.new .env.example", MAIN),
    ("echo DATABASE_URL=x > apps/api/.env.test", WORKTREE),
    ("rm .env", WORKTREE),
    ("rm .env", OUTSIDE),
    ("echo X=2 > .env", OUTSIDE),
    ("cp .env.example /tmp/x/.env", WORKTREE),
    ("ln -s ../../../.env .claude/worktrees/new/.env", MAIN),
    # design 快照：新建可以；仓库外的不归守卫管
    ("echo new > conductor/tracks/t1/design/b.md", WORKTREE),
    ("echo x > conductor/tracks/redesign_1/spec.md", WORKTREE),
    ("echo x > conductor/tracks/t1/design/a.md", OUTSIDE),
    # no_full_rewrite：读放行、Edit 那条路不归这里；仓库外不管
    ("echo {} > web/i18n/en.json", OUTSIDE),
    # 抹盘：写 /dev/null 不算
    ("dd if=/dev/zero of=/dev/null bs=1m count=10", MAIN),
    # 喂给 shell 的无害脚本
    ("bash <<'EOF'\nls -la\nEOF", MAIN),
    ("bash ok.sh", MAIN),
    ("bash mentions.sh", MAIN),
    ("bash -n bad.sh", MAIN),  # 只查语法、不执行
    ("sh -n rmarg.sh", MAIN),
    ("bash deploy.sh", MAIN),
    ("bash < deploy.sh", MAIN),
    ("cat deploy.sh | bash", MAIN),
    (f"bash {os.path.join(HERE, 'hooks.test.sh')}", MAIN),
    ("echo foo # don't rm -rf ~", MAIN),
    # X=$(cmd) 的值未知但非空，不能当成字面路径拼进项目里
    ('T=$(mktemp -d); echo {} > "$T/web/i18n/en.json"', MAIN),
    ('T="$(mktemp -d)"; rm -rf "$T/"', MAIN),
    ("export OUT=$(mktemp -d); rm -rf $OUT/", MAIN),
    ("git status # TRUNCATE 只是注释", MAIN),
    # 配置：主干改名后 main 以外的分支照推；测试库口径可配
    ("git push -f origin feature", DEV, DEV),
    ("dropdb scratch_1", DEV, DEV),
    # 未启用 flow / flow.json 坏掉 → 全放行（fail-open）
    ("rm -rf ~", NOFLOW, NOFLOW),
    ("git push --force origin main", NOFLOW, NOFLOW),
    ("echo X > .env", NOFLOW, NOFLOW),
    ("rm -rf ~", BROKEN, BROKEN),
]

BLOCK = [
    # 1. rm -r 删根 / 家目录 / 主 checkout 及其上级；删 .git；空变量展开成 /
    ("rm -rf ~", MAIN),
    ("rm -rf ~/", MAIN),
    ('rm -rf "$HOME"', MAIN),
    ("rm -rf /", MAIN),
    ("rm -rf /*", MAIN),
    ("cd x && rm -rf /", WORKTREE),
    ("cd / && rm -rf *", MAIN),
    ("rm -rf *", MAIN),
    ("rm -rf .", MAIN),
    ("rm -rf ..", MAIN),
    (f"rm -rf {MAIN}", OUTSIDE),
    (f"rm -rf {TMP}", OUTSIDE),
    ("rm -rf $(pwd)", MAIN),
    ('rm -rf "$PWD"', MAIN),
    ("rm -rf $SOME_UNSET_VAR_XYZ/", WORKTREE),
    ("cd $SOME_UNSET_VAR_XYZ && rm -rf *", WORKTREE),
    ("rm -rf .git", MAIN),
    ("rm -rf .git/*", MAIN),
    ('bash -c "rm -rf ~"', MAIN),
    ('echo "$(rm -rf ~)"', MAIN),
    ("eval 'rm -rf ~'", MAIN),
    ("sudo rm -rf /", MAIN),
    ("sudo -u root rm -rf /", MAIN),
    ("nice -n 10 rm -rf ~", MAIN),
    ("grep -oE \"[\\`'\\\"]x\" f; rm -rf ~", MAIN),
    ("find ~ -mindepth 1 -delete", MAIN),
    ("find ~ -type f -exec rm {} +", MAIN),
    # 2. 非测试库的破坏性 SQL
    ("docker exec pg dropdb -U app app", MAIN),
    ("dropdb app_latest", MAIN),
    ('docker exec pg psql -U app -c "DROP TABLE trades"', MAIN),
    ("psql \"$DATABASE_URL\" -c 'TRUNCATE audit_log'", MAIN),
    ("psql postgres://u:p@localhost:5432/app -c 'drop schema public cascade'", MAIN),
    ("psql -d app_test -c 'DROP DATABASE app'", MAIN),
    ("docker exec -i pg psql -U app -d app <<'SQL'\nDROP SCHEMA public CASCADE;\nSQL", MAIN),
    ("echo 'DROP TABLE trades;' | docker exec -i pg psql -U app -d app", MAIN),
    ("cat <<'SQL' | docker exec -i pg psql -U app -d app\nTRUNCATE trades;\nSQL", MAIN),
    ("docker exec -i pg psql -U app -d app <<< 'TRUNCATE trades'", MAIN),
    ("docker compose -f infra/docker-compose.yml exec -T postgres psql -U app -c 'drop table trades'", MAIN),
    ("docker exec -i pg sh <<'EOF'\ndropdb -U app app\nEOF", MAIN),
    ('mysql -u root -D app -e "DROP TABLE users"', MAIN),
    ('mysql -uroot -psecret -e "DROP DATABASE app"', MAIN),
    ("echo 'TRUNCATE TABLE users' | mysql app", MAIN),
    ("mysqladmin -u root -psecret drop app", MAIN),
    ('sqlite3 app.db "DROP TABLE users"', MAIN),
    ("echo 'DROP TABLE users;' | sqlite3 data.sqlite", MAIN),
    ("dropdb app_test", DEV, DEV),  # 测试库口径改成 ^scratch_ 之后 *_test 不再算测试库
    # 3. docker 数据卷
    ("docker volume rm app_pgdata", MAIN),
    ("docker compose -f infra/docker-compose.yml down -v", MAIN),
    ("docker compose down -tv 0", MAIN),
    ("timeout 120 docker compose -f infra/docker-compose.yml down -v", MAIN),
    ("docker system prune -a --volumes", MAIN),
    # 4. force push 主干 / --all / --mirror / 删远端主干
    ("git push --force origin main", WORKTREE),
    ("git push -f origin HEAD:main", WORKTREE),
    ("git push origin +main", WORKTREE),
    ("git push origin :main", WORKTREE),
    ("git push origin --delete master", WORKTREE),
    ("git push --mirror", WORKTREE),
    ("git -C /somewhere push -f origin refs/heads/main", WORKTREE),
    ("git push -f", MAIN),  # 主 checkout 停在 main
    ("git push --force --all origin", WORKTREE),
    ("git push -f --all", WORKTREE),
    ("git push -f origin 'refs/heads/*'", WORKTREE),
    ("timeout 60 git push --force origin main", WORKTREE),
    ("git push -f origin develop", DEV, DEV),
    ("git push -f origin master", DEV, DEV),
    # 5. 不入库的本地文件（worktree_links / protected_paths）；主 checkout 里 git clean -x
    ("echo KEY=1 >> .env", MAIN),
    ("echo KEY=1 >> .env", WORKTREE),  # 软链指向主 checkout 那份
    ("cp /tmp/x .env", MAIN),
    ("sed -i '' 's/a/b/' .env", MAIN),
    ("printf x | tee .env", MAIN),
    ("dd if=/tmp/x of=.env", MAIN),
    ("mv .env /tmp/", MAIN),
    ("rm .env", MAIN),
    ("rm -f .env*", MAIN),
    ("rm design-system/.project-id", MAIN),
    ("rm -rf design-system", MAIN),
    ("ln -sf /tmp/x .env", MAIN),
    ("echo x > .github/workflows/ci.yml", WORKTREE),
    ("git clean -fdx", MAIN),
    ("git clean -fdX", MAIN),
    (f"git -C {MAIN} clean -fdx", WORKTREE),
    # 6. no_full_rewrite
    ("echo {} > web/i18n/en.json", WORKTREE),
    ("echo {} > web/i18n/fr.json", WORKTREE),
    ("cd web/i18n && echo {} > en.json", WORKTREE),
    ("dd if=/dev/zero of=web/i18n/en.json count=1", WORKTREE),
    ("cp /tmp/x.json web/i18n/en.json", WORKTREE),
    # 7. design 快照（已存在的文件）
    ("echo x > conductor/tracks/t1/design/a.md", WORKTREE),
    ("echo x > conductor/tracks/t1/design/a.md", MAIN),
    ('cat n.md >> "conductor/tracks/t1/design-r2/notes.md"', WORKTREE),
    ("printf x | tee -a conductor/tracks/t1/design/a.md", WORKTREE),
    ("sed -i '' s/a/b/ conductor/tracks/t1/design/a.md", WORKTREE),
    ("cd conductor/tracks/t1/design && echo x > a.md", WORKTREE),
    ("cd conductor/tracks/t1 && echo x >design/a.md", WORKTREE),
    ("mv conductor/tracks/t1/design/a.md /tmp/", WORKTREE),
    # 8. 抹盘
    ("dd if=/dev/zero of=/dev/disk2", MAIN),
    ("diskutil eraseDisk JHFS+ x disk2", MAIN),
    ("mkfs.ext4 /dev/sdb", MAIN),
    # 经 stdin / 脚本文件喂给 shell
    ("bash <<'EOF'\nrm -rf ~\nEOF", MAIN),
    ("echo 'rm -rf ~' | sh", MAIN),
    ("bash bad.sh", MAIN),
    ("bash < bad.sh", MAIN),
    ("cat bad.sh | sh", MAIN),
    ("bash rmarg.sh", MAIN),  # $1 为空时就是 rm -rf /
    ('rm -rf "$1/"', MAIN),
    ("bash -c 'echo x >> .env'", MAIN),  # 命令里现写的脚本照样套路径规则
    ("bash <<'EOF'\necho x >> .env\nEOF", MAIN),
    ("for d in $(psql -Atc 'select 1'); do psql -d postgres -c \"DROP DATABASE IF EXISTS $d\"; done", MAIN),
    ("rm -rf \\\n~", MAIN),  # 反斜杠续行
    ("export X; rm -rf ~", MAIN),
    ("local A=1 B; rm -rf ~", MAIN),
    ("X=1 > .env", MAIN),
    ("export X=1 > .env", MAIN),
]


def run(cmd, cwd, project=MAIN, env_project=True):
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    if env_project:
        env["CLAUDE_PROJECT_DIR"] = project
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": cwd})
    return subprocess.run([sys.executable, "-I", HOOK], input=payload, capture_output=True, text=True,
                          env=env, cwd=project)


failures = []
total = 0
for want, cases in ((0, ALLOW), (2, BLOCK)):
    for case in cases:
        cmd, cwd = case[0], case[1]
        project = case[2] if len(case) > 2 else MAIN
        total += 1
        r = run(cmd, cwd, project)
        if r.returncode != want:
            failures.append(f"FAIL want={'allow' if want == 0 else 'block'} cwd={cwd}\n  {cmd!r}\n  {r.stderr.strip()}")


def expect(name, ok, detail=""):
    global total
    total += 1
    if not ok:
        failures.append(f"FAIL {name}\n  {detail}")


# 缺 CLAUDE_PROJECT_DIR → 用进程 cwd 找 flow.json
r = run("rm -rf ~", MAIN, project=MAIN, env_project=False)
expect("无 CLAUDE_PROJECT_DIR、cwd 是启用 flow 的项目 → 拦", r.returncode == 2, r.stderr)
r = run("rm -rf ~", NOFLOW, project=NOFLOW, env_project=False)
expect("无 CLAUDE_PROJECT_DIR、cwd 没有 flow.json → 放行且无输出", r.returncode == 0 and not r.stdout + r.stderr,
       r.stdout + r.stderr)
# 阻断口径：退出码 2 + stderr 以 BLOCKED: 开头
r = run("rm -rf ~", MAIN)
expect("阻断信息以 BLOCKED: 开头", r.stderr.startswith("BLOCKED: "), r.stderr)
r = run("git status", MAIN)
expect("放行时无输出", not r.stdout + r.stderr, r.stdout + r.stderr)
# 通用：不带任何项目专属字样
with open(HOOK, encoding="utf-8") as f:
    src = f.read()
for word in ("pxcapital", "SECRETS_MASTER_KEY", "规则 7"):
    expect(f"守卫源码不含项目专属字样 {word}", word not in src)

for msg in failures:
    print(msg)
print(f"{total - len(failures)}/{total} passed")
sys.exit(1 if failures else 0)
