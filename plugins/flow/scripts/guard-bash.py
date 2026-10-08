#!/usr/bin/env python3
"""flow 的 PreToolUse(Bash) 守卫：只拦致命、不可逆的命令，其余交给 auto 模式分类器 / 权限提示。

由 guard-bash.sh 调用（那里先判「flow 已启用」与 python3 可用）；直接跑也一样：没有
.claude/flow.json（在 $CLAUDE_PROJECT_DIR，缺省当前目录）就立即放行、无输出。

效率优先：宁可放过一条「只是危险」的命令，也不误拦正常工作。判断基于 shell 词法切分后的
命令词，而不是对整串做子串匹配——heredoc 正文、commit message、PR 正文里「提到」某个命令
不会被拦，`2>&1` / `>/dev/null` 也不算写文件（旧版按子串匹配的 guard-bash.sh 的误拦全来自这两点）。
反过来，真正会被执行的文本照样要查：`bash -c`、`eval`、`$(...)`、喂给 shell / SQL 客户端的
heredoc、`<<<`、管道上游的 echo / printf 与 cat 的文件。

拦截清单（都是丢了找不回来的东西）：
  1. rm -r / find -delete 删到 / 、家目录、主 checkout 根或它们的上级；删 .git 目录；
     `$VAR/` 在变量为空时展开成 /
  2. 对测试库以外的库执行 DROP / TRUNCATE（psql / mysql / mariadb / sqlite3）、dropdb、mysqladmin drop；
     测试库按 flow.json 的 bash_guard.test_db_pattern 判，缺省 *_test / test_*
  3. 删 docker 数据卷
  4. force push 到主干（main_branch / main / master，含 --all、通配 refspec）、删远端主干、push --mirror
  5. 不入库的本地文件：worktree_links 列出的文件（如 .env）与 protected_paths 命中的文件——
     rm / mv / 重定向 / tee / sed -i / dd of= / cp 落点等写入；主 checkout 里 git clean -x / -X
  6. no_full_rewrite 命中的文件：用 Bash 写入（读放行）
  7. conductor/tracks/*/design*/ 下已存在的文件：用 Bash 回改（新建放行）
  8. 抹盘：mkfs、diskutil erase*、dd of=/dev/<块设备>

路径规则（5–7）只管本项目的文件（主 checkout 与它的各个 worktree 里）；仓库外的同名文件不归守卫管。
不拦 git reset --hard 之类可从 reflog 找回、或只是「危险」的命令。

退出码 2 = 阻断并把 stderr（`BLOCKED: <原因>`）喂回模型；0 = 放行。配置或解析出错一律放行（fail-open）。
只用 Python 3.8 也有的语法（macOS 命令行工具自带的 python3 是 3.9）。
"""
import fnmatch
import glob
import json
import os
import re
import shlex
import subprocess
import sys

HOME = os.path.realpath(os.path.expanduser("~"))
UNKNOWN_CWD = "/nonexistent-flow-guard-bash-unknown-cwd"  # cd 到解析不了的目录之后，相对路径一律当未知
OPERATOR_CHARS = set("();<>|&")
# 放在真正命令前面、本身不决定行为的词 → 它们带值的短选项；timeout 之后还跟一个时长位置参数。
PREFIX_OPTS = {"sudo": "ugUChpDrtT", "nice": "n", "timeout": "sk", "gtimeout": "sk", "stdbuf": "ioe",
               "env": "uSC", "xargs": "IinPLdsEa", "exec": "a", "nohup": "", "time": "", "command": "",
               "builtin": "", "then": "", "do": "", "else": "", "elif": "", "if": "", "while": "",
               "until": "", "!": "", "{": ""}
PREFIX_POSITIONALS = {"timeout": 1, "gtimeout": 1}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
SAFE_DEVICES = re.compile(r"^/dev/(null|zero|u?random|stdout|stderr|fd/\d+)$")
DEFAULT_TEST_DB = r"(^|_)test(_|$)"  # app_test、test_x；不认 app_latest
TEST_DB_HINT = "只允许测试库（.claude/flow.json 的 bash_guard.test_db_pattern，缺省 *_test / test_*）。"
# MySQL 有同名的数值函数 TRUNCATE(x, d)，后面紧跟括号的不算清表
DESTRUCTIVE_SQL = re.compile(r"\b(?:drop\s+(?:table|schema|database)|truncate\b(?!\s*\())", re.I)
DROP_DATABASE = re.compile(r"\bdrop\s+database\s+(?:if\s+exists\s+)?[\"`]?([\w-]+)", re.I)
DROP_SCHEMA = re.compile(r"\bdrop\s+schema\s+(?:if\s+exists\s+)?[\"`]?([\w-]+)", re.I)
CONN_SCOPED = re.compile(r"\b(?:drop\s+(?:table|schema)|truncate\b(?!\s*\())", re.I)  # 作用于当前连接的库
CONN_SCOPED_MYSQL = re.compile(r"\b(?:drop\s+table|truncate\b(?!\s*\())", re.I)  # MySQL 的 SCHEMA 就是 DATABASE
HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
VAR = re.compile(r"\$(?:\{([A-Za-z_]\w*)(:?[-=?+][^}]*)?\}|([A-Za-z_]\w*))")
DESIGN_SNAPSHOT = re.compile(r"/conductor/tracks/[^/]+/design[^/]*/")
UNSET = "\0unset"      # 变量无法解析，且为空时不会报错
GUARDED = "\0guarded"  # ${VAR:?} 这类为空即报错的写法，视为「未知但非空」


class Blocked(Exception):
    pass


def git(*args):
    try:
        return subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def glob_rules(items, default_reason):
    """protected_paths / no_full_rewrite → [(glob, reason)]；条目可以是 {glob, reason} 或纯字符串。"""
    out = []
    for it in items if isinstance(items, list) else []:
        if isinstance(it, str):
            g, reason = it, None
        elif isinstance(it, dict):
            g, reason = it.get("glob"), it.get("reason")
        else:
            continue
        if isinstance(g, str) and g:
            out.append((g, reason if isinstance(reason, str) and reason else default_reason))
    return out


def compile_test_db(pattern):
    if isinstance(pattern, str) and pattern:
        try:
            return re.compile(pattern, re.I)
        except re.error:
            pass  # 写错的正则退回缺省口径，不让整个守卫失效
    return re.compile(DEFAULT_TEST_DB, re.I)


class Project:
    """本项目的 flow 配置与仓库布局。git 调用都懒加载：多数命令（ls / cat / grep）根本用不到。"""

    def __init__(self, project_dir, cfg):
        self.dir = os.path.realpath(project_dir)
        main = cfg.get("main_branch")
        self.main_branches = {"main", "master"} | ({main} if isinstance(main, str) and main else set())
        self.protected = glob_rules(cfg.get("protected_paths"), "受保护路径，禁止修改。")
        self.no_rewrite = glob_rules(cfg.get("no_full_rewrite"), "该文件禁止整文件重写。")
        links = cfg.get("worktree_links")
        if links is None:
            links = [".env"]  # 与 link-worktree.sh 的缺省一致
        self.links = {os.path.normpath(x) for x in (links if isinstance(links, list) else [])
                      if isinstance(x, str) and x.strip() and not os.path.isabs(x)}
        guard = cfg.get("bash_guard")
        self.test_db = compile_test_db(guard.get("test_db_pattern") if isinstance(guard, dict) else None)
        self._main_root = False
        self._roots = None

    @property
    def main_root(self):
        """主 checkout 根目录（项目目录是 worktree 时也指向主 checkout）；不是 git 仓库则 None。"""
        if self._main_root is False:
            out = git("-C", self.dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
            self._main_root = os.path.realpath(os.path.dirname(out)) if out.endswith("/.git") else None
        return self._main_root

    @property
    def base(self):
        return self.main_root or self.dir

    @property
    def roots(self):
        """主 checkout + 全部 worktree 的根（realpath，长的在前，便于找最内层）。worktree 放在哪都认。"""
        if self._roots is None:
            roots = {self.base}
            if self.main_root:
                for line in git("-C", self.main_root, "worktree", "list", "--porcelain").splitlines():
                    if line.startswith("worktree "):
                        roots.add(os.path.realpath(line[len("worktree "):]))
            self._roots = sorted(roots, key=len, reverse=True)
        return self._roots

    def root_of(self, real):
        for r in self.roots:
            if real == r or real.startswith(r.rstrip("/") + "/"):
                return r
        return None

    @property
    def protected_roots(self):
        return [p for p in (HOME, self.base) if p]


PROJ = None  # main() 里按 flow.json 建好


def strip_heredocs(cmd):
    """去掉 heredoc 正文（它是数据不是命令）；正文另外返回，喂给 shell / SQL 客户端时再查。"""
    lines, out, bodies, i = cmd.split("\n"), [], [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for m in HEREDOC.finditer(line):
            dash, delim, body = m.group(1), m.group(3), []
            while i < len(lines):
                cur = lines[i]
                i += 1
                if (cur.lstrip("\t") if dash else cur) == delim:
                    break
                body.append(cur)
            bodies.append("\n".join(body))
    return "\n".join(out), bodies


def tokenize(cmd):
    cmd = cmd.replace("\n", " ; ")
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""  # shlex 会把词中间的 # 当注释吞掉后半行；宁可把注释当成普通词
    try:
        return list(lex)
    except ValueError:
        # 引号嵌套太复杂（如正则里的 \` ' "）时 shlex 会放弃；退化成按空白 / 运算符粗切，
        # 保证 `rm -rf ~` 这类致命命令在怪引号旁边也还认得出来
        return [t.strip("'\"") for t in re.findall(r"[();<>|&]+|[^\s();<>|&]+", cmd)]


def is_operator(tok):
    return bool(tok) and all(c in OPERATOR_CHARS for c in tok)


def segments(tokens):
    """按 ; && || | & ( ) 切成简单命令；重定向运算符留在命令内部。"""
    seg = []
    for tok in tokens:
        if is_operator(tok) and "<" not in tok and ">" not in tok:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(tok)
    if seg:
        yield seg


class Segment:
    """一条简单命令：命令词 + 重定向。`2>&1`、`>&2` 这类 fd 复制不算写文件。"""

    def __init__(self, seg):
        self.words, self.writes, self.inputs, self.herestrings, self.heredoc = [], [], [], [], False
        i = 0
        while i < len(seg):
            tok = seg[i]
            if not is_operator(tok):
                self.words.append(tok)
                i += 1
                continue
            target = seg[i + 1] if i + 1 < len(seg) else ""
            if self.words and self.words[-1].isdigit():
                self.words.pop()  # `2>` 里的 fd 号
            if tok.startswith("<<<"):
                self.herestrings.append(target)
            elif tok.startswith("<<"):
                self.heredoc = True
            elif tok.endswith("&") and (target.isdigit() or target == "-"):
                pass
            elif ">" in tok:
                self.writes.append(target)
            elif "<" in tok:
                self.inputs.append(target)
            i += 2


def strip_prefix(words):
    """剥掉变量赋值与 sudo / timeout / nice / env / xargs 这类前缀词（连同它们的选项），返回真正的 argv。"""
    i = 0
    while i < len(words):
        if ASSIGN.match(words[i]):
            i += 1
            continue
        name = os.path.basename(words[i])
        if name not in PREFIX_OPTS:
            break
        valued = PREFIX_OPTS[name]
        i += 1
        while i < len(words) and words[i].startswith("-") and words[i] != "-":
            flag = words[i]
            i += 1
            if flag == "--":
                break
            if not flag.startswith("--") and len(flag) == 2 and flag[1] in valued:
                i += 1  # 值在下一个词：sudo -u root、nice -n 10、timeout -s KILL
        i += PREFIX_POSITIONALS.get(name, 0)
    return words[i:]


def exec_inner(argv):
    """docker exec <容器> CMD / docker compose exec <服务> CMD：返回在容器里执行的 CMD。"""
    if os.path.basename(argv[0]) not in ("docker", "docker-compose", "podman") or "exec" not in argv:
        return None
    rest = argv[argv.index("exec") + 1:]
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        flag = rest[i]
        i += 1
        if flag in ("-e", "--env", "-u", "--user", "-w", "--workdir", "--env-file", "--detach-keys", "--index"):
            i += 1
    return rest[i + 1:] or None  # rest[i] 是容器 / 服务名


def expand(tok, shell_vars, cwd=None):
    def sub(m):
        name = m.group(1) or m.group(3)
        if name == "PWD" and cwd:
            return cwd
        if name in shell_vars:
            return shell_vars[name]
        if name in os.environ:
            return os.environ[name]
        return GUARDED if (m.group(2) or "").lstrip(":").startswith("?") else UNSET
    tok = VAR.sub(sub, tok)
    if tok == "~" or tok.startswith("~/"):
        tok = HOME + tok[1:]
    return tok


def resolve(tok, shell_vars, cwd):
    """展开变量后解析成绝对路径；含未知变量时返回 None。"""
    t = expand(tok, shell_vars, cwd)
    if "\0" in t:
        return None
    return os.path.normpath(os.path.join(cwd, t))


def read_small(path, limit=256 * 1024):
    """读喂给 shell / SQL 客户端的脚本文件；读不到就当空（fail-open）。.env 一类不读。"""
    try:
        base = os.path.basename(path or "")
        if path and base != ".env" and not base.startswith(".env.") and os.path.isfile(path) \
                and os.path.getsize(path) <= limit:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read()
    except OSError:
        pass
    return ""


def is_protected(path):
    """path 是 / 、家目录、主 checkout 根，或它们的上级——删掉它就删掉了全部。"""
    real = os.path.realpath(path)
    prefix = real.rstrip("/") + "/"
    return any(root == real or root.startswith(prefix) for root in PROJ.protected_roots)


def glob_base(path):
    """含通配符的路径：返回第一个通配段之前的目录（它的所有子项都会被删）。"""
    parts = path.split("/")
    for i, part in enumerate(parts):
        if any(c in part for c in "*?["):
            return "/".join(parts[:i]) or "/"
    return None


def local_rule(path):
    """path 落在本项目里、且是 worktree_links 的本地文件或命中 protected_paths → 返回原因；否则 None。

    按 realpath 判归属：worktree 里指向主 checkout 的软链，写它就是写主 checkout 那份。
    """
    if not path or path.startswith("/dev/"):
        return None
    logical = os.path.normpath(path)
    real = os.path.realpath(logical)
    root = PROJ.root_of(real)
    if root is None:
        return None
    if os.path.relpath(real, root) in PROJ.links:
        return "它是 worktree_links 里不入库的本地文件，丢了无法从 git 找回（worktree 里的同名文件是指向主 checkout 的软链）"
    for g, reason in PROJ.protected:
        if fnmatch.fnmatchcase(logical, g) or fnmatch.fnmatchcase(real, g):
            return f"{reason.rstrip('。. ')}（.claude/flow.json protected_paths: {g}）"
    return None


def local_file_under(path):
    """rm -r 的目录里是否含主 checkout 的 worktree_links 真身（worktree 里那份只是软链，删了无害）。"""
    prefix = os.path.realpath(path).rstrip("/") + "/"
    for rel in sorted(PROJ.links):
        f = os.path.join(PROJ.base, rel)
        if f.startswith(prefix) and os.path.lexists(f) and not os.path.islink(f):
            return f
    return None


def in_main_checkout(path):
    """path 在主 checkout 里、且不在嵌套于其中的某个 worktree 里。"""
    main = PROJ.main_root
    return bool(main) and PROJ.root_of(os.path.realpath(path)) == main


def parse_opts(args, valued_short="", valued_long=()):
    """极简 getopt：返回 ({flag: value}, 位置参数)。只为找出库名 / 目标路径，够用即可。"""
    opts, pos, i = {}, [], 0
    while i < len(args):
        a = args[i]
        i += 1
        if a == "--":
            pos.extend(args[i:])
            break
        if a.startswith("--"):
            key, eq, val = a[2:].partition("=")
            if not eq and key in valued_long and i < len(args):
                val = args[i]
                i += 1
            opts[key] = val
        elif a.startswith("-") and len(a) > 1:
            j = 1
            while j < len(a):
                c = a[j]
                j += 1
                if c in valued_short:
                    rest = a[j:]
                    if not rest and i < len(args):
                        rest = args[i]
                        i += 1
                    opts[c] = rest
                    break
                opts[c] = ""
        else:
            pos.append(a)
    return opts, pos


def change_dir(argv, shell_vars, cwd):
    args = [a for a in argv[1:] if not (a.startswith("-") and a != "-")]
    if not args:
        return HOME
    if args[0] == "-":
        return UNKNOWN_CWD
    t = expand(args[0], shell_vars)
    if t == UNSET:
        return HOME  # 变量为空时 `cd $X` 回家目录（bash / zsh 实测）
    if "\0" in t:
        return UNKNOWN_CWD
    return os.path.normpath(os.path.join(cwd, t))


def check_rm(args, shell_vars, cwd):
    opts, targets = parse_opts(args)
    recursive = "r" in opts or "R" in opts or "recursive" in opts
    for tok in targets:
        t = expand(tok, shell_vars, cwd)
        if t.startswith(UNSET) and t[len(UNSET):] in ("/", "/*", "/."):
            raise Blocked(f"rm 的目标 `{tok}` 在变量为空时会展开成根目录。确需删除请写成 `${{VAR:?}}/...`。")
        if "\0" in t:
            continue
        path = os.path.normpath(os.path.join(cwd, t))
        base = glob_base(path)
        for hit in (glob.glob(path) if base else [path]):
            # 软链（worktree 里指向主 checkout 的那种）删了无害，不存在的删了也无事发生
            if os.path.lexists(hit) and not os.path.islink(hit):
                reason = local_rule(hit)
                if reason:
                    raise Blocked(f"不能删除 {hit}：{reason}。")
        if not recursive:
            continue
        whole = base if base is not None else path  # 通配时整个被清空的是 base
        if is_protected(whole):
            raise Blocked(f"rm -r 目标 `{tok}` 覆盖了根目录 / 家目录 / 主 checkout（{path}）。")
        if os.path.basename(whole) == ".git" and os.path.isdir(whole):
            raise Blocked(f"不能删除 git 仓库目录 {whole}（所有 worktree 与未推送的提交都在里面）。")
        kept = local_file_under(whole)
        if kept:
            raise Blocked(f"rm -r `{tok}` 会连带删掉 {kept}：它是 worktree_links 里不入库的本地文件，删了无法从 git 找回。")


def current_branch(cwd):
    return git("-C", cwd, "rev-parse", "--abbrev-ref", "HEAD")


def check_git(args, shell_vars, cwd):
    i, gcwd = 0, cwd
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            gcwd = resolve(args[i + 1], shell_vars, cwd) or cwd
            i += 2
        elif args[i] in ("-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1:]
    if sub == "push":
        opts, pos = parse_opts(rest, "o", ("repo", "push-option", "receive-pack", "exec"))
        if "mirror" in opts:
            raise Blocked("git push --mirror 会用本地引用覆盖远端全部分支（含主干）。")
        force = "f" in opts or any(k.startswith("force") for k in opts)
        delete = "d" in opts or "delete" in opts
        if force and ("all" in opts or "branches" in opts):
            raise Blocked("禁止 force push --all：会连同本地（可能过期的）主干一起强推。")
        for r in pos[1:] or ["HEAD"]:
            plus = r.startswith("+")
            src, colon, dst = r.lstrip("+").partition(":")
            dst = dst if colon else src
            if dst == "HEAD":
                dst = current_branch(gcwd)
            if dst.replace("refs/heads/", "", 1) not in PROJ.main_branches and "*" not in dst:
                continue
            if force or plus:
                raise Blocked(f"禁止 force push 到 {dst}（会改写主干历史）。")
            if delete or (colon and not src):
                raise Blocked(f"禁止删除远端主干 {dst}。")
    elif sub == "clean":
        opts, _ = parse_opts(rest, "e", ("exclude",))
        if ("x" in opts or "X" in opts) and in_main_checkout(gcwd):
            raise Blocked("主 checkout 里禁止 git clean -x / -X：会删掉被 gitignore 的本地文件（如 .env），"
                          "它们不在 git 里、删了找不回。要清构建产物请在 worktree 里做，或去掉 -x。")


def check_docker(argv):
    args = argv[1:]
    if "volume" in args and any(a in args for a in ("rm", "remove", "prune")):
        raise Blocked("禁止删除 docker 数据卷（数据库等持久数据在卷里）。")
    if "system" in args and "prune" in args and "--volumes" in args:
        raise Blocked("禁止 docker system prune --volumes（会删数据卷）。")
    project = parse_opts(args, "pf", ("project-name", "file"))[0]
    project = project.get("p") or project.get("project-name") or ""
    if "down" in args and not PROJ.test_db.search(project) and \
            any(a == "--volumes" or re.fullmatch(r"-[a-zA-Z]*v[a-zA-Z]*", a) for a in args[args.index("down"):]):
        raise Blocked("禁止 docker compose down -v（会删数据卷）；要停服务去掉 -v。")


def without_password(args):
    """mysql 系的 -p<密码> 只能粘写；不剥掉会被极简 getopt 拆成 -e 之类的短选项。"""
    return [a for a in args if not (a.startswith("-p") or a.startswith("--password"))]


def judge_sql(sql, conn, mysql=False):
    if not DESTRUCTIVE_SQL.search(sql):
        return
    dbs = DROP_DATABASE.findall(sql)
    if mysql:
        dbs += DROP_SCHEMA.findall(sql)
    if (CONN_SCOPED_MYSQL if mysql else CONN_SCOPED).search(sql):
        dbs.append(conn)
    if not dbs or not all(PROJ.test_db.search(d) for d in dbs):
        names = "、".join(d or "（无法确定）" for d in dbs) or "（无法确定）"
        raise Blocked(f"禁止对非测试库执行破坏性 SQL（DROP / TRUNCATE），目标库：{names}。{TEST_DB_HINT}")


SQLITE_VALUED = {"-cmd", "-separator", "-newline", "-nullvalue", "-init", "-vfs", "-mmap", "-maxsize",
                 "-lookaside", "-pagecache", "-heap", "-escape"}


def check_sql(argv, stdin_text, shell_vars, cwd):
    """只看命令名本身是 SQL 客户端的命令（docker exec 已剥掉），`grep dropdb` 不算。"""
    name, args = os.path.basename(argv[0]), argv[1:]
    if name == "dropdb":
        _, pos = parse_opts(args, "hpU", ("host", "port", "username", "maintenance-db"))
        if pos and not PROJ.test_db.search(pos[-1]):
            raise Blocked(f"禁止 dropdb {pos[-1]}：{TEST_DB_HINT}")
    elif name in ("mysqladmin", "mariadb-admin"):
        _, pos = parse_opts(without_password(args), "uhPS", ("user", "host", "port", "socket"))
        for i, a in enumerate(pos):
            db = pos[i + 1] if i + 1 < len(pos) else ""
            if a.lower() == "drop" and not PROJ.test_db.search(db):
                raise Blocked(f"禁止 {name} drop {db}：{TEST_DB_HINT}")
    elif name == "psql":
        opts, pos = parse_opts(args, "cdfhpUvoLPFRT",
                               ("command", "dbname", "file", "host", "port", "username", "set", "variable",
                                "output", "log-file", "pset", "field-separator", "record-separator", "table-attr"))
        if "c" in opts or "command" in opts:
            sql = " ".join([opts.get("c", ""), opts.get("command", "")])
        elif "f" in opts or "file" in opts:
            sql = read_small(resolve(opts.get("f") or opts.get("file", ""), shell_vars, cwd))
        else:
            sql = "\n".join(stdin_text())
        conn = opts.get("d") or opts.get("dbname") or (pos[0] if pos else "") \
            or opts.get("U") or opts.get("username") or os.environ.get("PGDATABASE", "")
        m = re.match(r"postgres(?:ql)?://[^/]*/([\w-]+)", conn) or re.search(r"\bdbname=([\w-]+)", conn)
        judge_sql(sql, m.group(1) if m else conn)
    elif name in ("mysql", "mariadb"):
        opts, pos = parse_opts(without_password(args), "uhPDeS",
                               ("user", "host", "port", "database", "execute", "socket"))
        if "e" in opts or "execute" in opts:
            sql = opts.get("e", "") + "\n" + opts.get("execute", "")
        else:
            sql = "\n".join(stdin_text())
        judge_sql(sql, opts.get("D") or opts.get("database") or (pos[0] if pos else ""), mysql=True)
    elif name == "sqlite3":
        pos, extra, i = [], [], 0
        while i < len(args):
            a = args[i]
            i += 1
            if a.startswith("-") and len(a) > 1:
                key = "-" + a.lstrip("-")
                if key in SQLITE_VALUED and i < len(args):
                    val = args[i]
                    i += 1
                    if key == "-cmd":
                        extra.append(val)
                    elif key == "-init":
                        extra.append(read_small(resolve(val, shell_vars, cwd)))
            else:
                pos.append(a)
        db = pos[0] if pos else ""
        if db in ("", ":memory:"):
            return  # 内存库，没有可丢的数据
        sql = "\n".join(extra + (pos[1:] or stdin_text()))
        judge_sql(sql, os.path.splitext(os.path.basename(db))[0])


def check_writes(targets, shell_vars, cwd):
    """写入 / 覆盖 / 搬走的目标：本地文件、no_full_rewrite、已入仓的 design 快照。只管本项目里的路径。"""
    for tok in targets:
        if not tok:
            continue
        path = resolve(tok, shell_vars, cwd)
        if path is None or path.startswith("/dev/"):
            continue
        real = os.path.realpath(path)
        if PROJ.root_of(real) is None:
            continue
        reason = local_rule(path)
        if reason:
            raise Blocked(f"禁止用 Bash 写入、覆盖或搬走 {path}：{reason}。")
        for g, why in PROJ.no_rewrite:
            if fnmatch.fnmatchcase(path, g) or fnmatch.fnmatchcase(real, g):
                raise Blocked(f"疑似用 Bash 写入 {g}（目标：{path}）。{why} 请用 Edit 工具做局部修改。")
        if (DESIGN_SNAPSHOT.search(path) or DESIGN_SNAPSHOT.search(real)) and os.path.exists(path):
            raise Blocked(f"conductor/tracks/*/design*/ 入仓后是只读立项快照（workflow §3.2）；"
                          f"新建文件可以，回改不行（目标：{path}）。")


def write_targets(argv, shell_vars, cwd):
    """cp / mv / tee / sed -i / dd / truncate / sponge 的落点；mv 的源也算（搬走 = 删掉），软链除外。"""
    name, args = os.path.basename(argv[0]), argv[1:]
    if name in ("cp", "install", "rsync"):
        return parse_opts(args, "S" if name == "cp" else "")[1][-1:]
    if name == "ln":
        # 在空位上建软链无害（worktree 补 .env 链接就是这样）；只有覆盖已有的真文件才算写
        dst = parse_opts(args, "S")[1][-1:]
        return [p for p in dst if os.path.lexists(resolve(p, shell_vars, cwd) or "")
                and not os.path.islink(resolve(p, shell_vars, cwd) or "")]
    if name == "mv":
        pos = parse_opts(args)[1]
        return [p for p in pos if not os.path.islink(resolve(p, shell_vars, cwd) or "")]
    if name in ("tee", "truncate", "sponge"):
        return parse_opts(args, "s" if name == "truncate" else "")[1]
    if name == "sed":
        opts, pos = parse_opts(args, "ef", ("expression", "file"))
        if "i" in opts or any(k.startswith("in-place") for k in opts):
            return pos if ("e" in opts or "f" in opts or "expression" in opts) else pos[1:]
    if name == "dd":
        return [a[3:] for a in args if a.startswith("of=") and not a[3:].startswith("/dev/")]
    return []


NAME_FILTERS = {"-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename", "-regex", "-iregex"}


def check_find(args, shell_vars, cwd):
    starts = []
    for a in args:
        if a.startswith("-") or a in ("(", "!"):
            break
        starts.append(a)
    deletes = "-delete" in args or any(
        a in ("-exec", "-execdir", "-ok") and i + 1 < len(args) and os.path.basename(args[i + 1]) == "rm"
        for i, a in enumerate(args))
    if not deletes or NAME_FILTERS & set(args):
        return
    for tok in starts or ["."]:
        path = resolve(tok, shell_vars, cwd)
        if path and is_protected(path):
            raise Blocked(f"find {tok} 不带按名过滤就删除，等于清空 {path}。")


def check_disk(argv):
    name, args = os.path.basename(argv[0]), argv[1:]
    if name == "mkfs" or name.startswith("mkfs."):
        raise Blocked("禁止格式化磁盘（mkfs）。")
    if name == "diskutil" and args and (args[0].lower().startswith("erase") or
                                        args[0].lower() in ("partitiondisk", "zerodisk", "randomdisk", "secureerase")):
        raise Blocked(f"禁止 diskutil {args[0]}（抹盘）。")
    if name == "dd" and any(a.startswith("of=/dev/") and not SAFE_DEVICES.match(a[3:]) for a in args):
        raise Blocked("禁止 dd 写入块设备。")


def shell_scripts(argv, stdin_text, shell_vars, cwd):
    """shell 要执行的脚本：`-c` 的参数、位置参数给的脚本文件，否则就是它的 stdin。"""
    if os.path.basename(argv[0]) not in SHELLS:
        return []
    args = argv[1:]
    for i, a in enumerate(args):
        if re.fullmatch(r"-[a-z]*c[a-z]*", a):
            return args[i + 1:i + 2]
        if not a.startswith("-"):
            return [read_small(resolve(a, shell_vars, cwd))]
    return stdin_text()


def inline_scripts(argv):
    """eval 的参数、词里的 $(...) 与 `...`。"""
    out = []
    for tok in argv:
        out.extend(re.findall(r"\$\(([^()]*)\)", tok))
        out.extend(re.findall(r"`([^`]*)`", tok))
    if os.path.basename(argv[0]) == "eval":
        out.append(" ".join(argv[1:]))
    return out


def check(cmd, cwd, depth=0):
    if depth > 3:
        return
    stripped, bodies = strip_heredocs(cmd)
    # $(pwd) 不加引号时会被切成运算符；先统一成 $PWD，由 expand 解析成命令自己的 cwd
    stripped = stripped.replace("$(pwd)", "$PWD").replace("`pwd`", "$PWD")
    segs = [Segment(s) for s in segments(tokenize(stripped))]
    shell_vars = {}

    def piped_text():
        """管道上游可能喂过来的文本：heredoc、<<<、echo / printf 的参数、cat 的文件。宁多勿漏。"""
        out = list(bodies)
        for s in segs:
            out += s.herestrings
            argv = strip_prefix(s.words)
            if argv and os.path.basename(argv[0]) in ("echo", "printf"):
                out.append(" ".join(argv[1:]))
            elif argv and os.path.basename(argv[0]) == "cat":
                out += [read_small(resolve(a, shell_vars, cwd)) for a in parse_opts(argv[1:])[1]]
        return out

    for s in segs:
        if s.words and all(ASSIGN.match(w) for w in s.words):
            for w in s.words:
                k, v = ASSIGN.match(w).groups()
                shell_vars[k] = expand(v, shell_vars)
            continue
        argv = strip_prefix(s.words)
        check_writes(s.writes, shell_vars, cwd)
        if not argv:
            continue
        name = os.path.basename(argv[0])
        if name in ("cd", "pushd", "popd"):
            cwd = change_dir(argv, shell_vars, cwd) if name != "popd" else UNKNOWN_CWD
            continue
        if name == "rm":
            check_rm(argv[1:], shell_vars, cwd)
        elif name == "git":
            check_git(argv[1:], shell_vars, cwd)
        elif name in ("docker", "docker-compose", "podman"):
            check_docker(argv)
        elif name == "find":
            check_find(argv[1:], shell_vars, cwd)
        check_writes(write_targets(argv, shell_vars, cwd), shell_vars, cwd)
        check_disk(argv)

        def stdin_text(s=s):
            own = s.herestrings + (bodies if s.heredoc else []) + \
                [read_small(resolve(p, shell_vars, cwd)) for p in s.inputs]
            return own if (s.herestrings or s.heredoc or s.inputs) else piped_text()

        inner = strip_prefix(exec_inner(argv) or argv)
        if inner:
            check_sql(inner, stdin_text, shell_vars, cwd)
            for script in shell_scripts(inner, stdin_text, shell_vars, cwd):
                check(script, cwd, depth + 1)
        for script in inline_scripts(argv):
            check(script, cwd, depth + 1)


def load_project():
    """读 $CLAUDE_PROJECT_DIR（缺省当前目录）/.claude/flow.json；没有即未启用 flow → None。"""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    path = os.path.join(project_dir, ".claude", "flow.json")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    return Project(project_dir, cfg) if isinstance(cfg, dict) else None


def main():
    global PROJ
    try:
        raw = sys.stdin.read()
        PROJ = load_project()
        if PROJ is None:
            return 0
        data = json.loads(raw)
        cmd = (data.get("tool_input") or {}).get("command") or ""
        cwd = data.get("cwd") or os.getcwd()
        if isinstance(cmd, str) and cmd:
            check(cmd, cwd)
    except Blocked as e:
        print(f"BLOCKED: {e}", file=sys.stderr)
        return 2
    except Exception:
        pass  # fail-open：守卫自身出错不该挡住工作，分类器还在
    return 0


if __name__ == "__main__":
    sys.exit(main())
