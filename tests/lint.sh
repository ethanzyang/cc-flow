#!/usr/bin/env bash
# 静态检查：macOS 自带 bash 3.2 会把紧跟在 $var 后面的中文字节当成变量名的一部分
# （set -u 下直接报 unbound variable）。凡是 $var 后面紧跟非 ASCII 字符的，必须写成 ${var}。
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
hits=$(grep -nP '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]' "$HERE"/plugins/flow/scripts/*.sh "$HERE"/tests/*.sh 2>/dev/null ||
  python3 - "$HERE" <<'PY'
import re, sys, glob
root = sys.argv[1]
pat = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])')
for p in sorted(glob.glob(root + '/plugins/flow/scripts/*.sh') + glob.glob(root + '/tests/*.sh')):
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        if pat.search(line):
            print(f"{p}:{i}:{line.rstrip()}")
PY
)
if [ -n "$hits" ]; then
  echo "lint: \$var 后紧跟非 ASCII 字符，请改成 \${var}:"
  echo "$hits"
  exit 1
fi
bash -n "$HERE"/plugins/flow/scripts/*.sh 2>&1 | sed 's/^/syntax: /'
for f in "$HERE"/plugins/flow/scripts/*.sh; do bash -n "$f" || exit 1; done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x "$HERE"/plugins/flow/scripts/*.sh || exit 1
fi
echo "lint: ok"
