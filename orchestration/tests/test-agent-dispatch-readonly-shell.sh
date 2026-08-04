#!/usr/bin/env bash
# agent-dispatch の gpt バックエンドが --read-only のときだけ Windows 用の回避を適用することを検証する。
# 回避の中身: pwsh を含む PATH 要素を落とす / node_repl MCP を無効化する。
#
# カバー範囲の境界: ここでは codex スタブで「渡した引数」と「見えた PATH」だけを検証する。
# 「実際に System32 の powershell.exe 5.1 が選択されサンドボックス内で動く」ことは実 codex が
# 必要なため E2E 側の担当で、証跡は ~/.codex/.sandbox/sandbox.<date>.log の SUCCESS 行と
# ~/work/docs/official-docs-evidence/2026-07-26-codex-windows-sandbox-readonly.md に残す。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-dispatch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) is_windows=1 ;; *) is_windows=0 ;; esac

# codex スタブ: 受け取った引数と PATH を記録し、-o の指すファイルに回答を書く。
fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/codex" <<'STUB'
#!/usr/bin/env bash
out=""
: > "$AD_TEST_ARGS"
while [ $# -gt 0 ]; do
  printf '%s\n' "$1" >> "$AD_TEST_ARGS"
  if [ "$1" = "-o" ]; then out="$2"; fi
  shift
done
printf '%s' "$PATH" > "$AD_TEST_PATH"
[ -n "$out" ] && printf 'stub-answer\n' > "$out"
STUB
chmod +x "$fake_bin/codex"

# pwsh を持つディレクトリ。read-only 時に PATH から落ちることを確認するための的。
pwsh_dir="$tmp/pwsh-dir"
mkdir -p "$pwsh_dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$pwsh_dir/pwsh.exe"
chmod +x "$pwsh_dir/pwsh.exe"

args_file="$tmp/args"
path_file="$tmp/seen-path"

dispatch() {
  AD_TEST_ARGS="$args_file" AD_TEST_PATH="$path_file" USAGE_GATE=0 \
    PATH="$fake_bin:$pwsh_dir:$PATH" bash "$runner" gpt "$@" --dir "$tmp" -- 'probe' > /dev/null
}

# --- read-only ---
dispatch --read-only
grep -qx -- '-s' "$args_file"
grep -qx -- 'read-only' "$args_file"
seen_path="$(cat "$path_file")"

if [ "$is_windows" = 1 ]; then
  grep -qx -- 'mcp_servers.node_repl.enabled=false' "$args_file" \
    || { echo 'FAIL: read-only で node_repl が無効化されていない' >&2; exit 1; }
  case ":$seen_path:" in
    *":$pwsh_dir:"*) echo 'FAIL: pwsh を含むディレクトリが PATH に残っている' >&2; exit 1 ;;
  esac
  case ":$seen_path:" in
    *":$fake_bin:"*) ;;
    *) echo 'FAIL: pwsh を持たないディレクトリまで PATH から落ちている' >&2; exit 1 ;;
  esac
else
  # Windows 以外ではこの回避を適用しない (macOS の pwsh は正常に動く)。
  if grep -qx -- 'mcp_servers.node_repl.enabled=false' "$args_file"; then
    echo 'FAIL: 非Windowsで node_repl が無効化されている' >&2; exit 1
  fi
  case ":$seen_path:" in
    *":$pwsh_dir:"*) ;;
    *) echo 'FAIL: 非Windowsで PATH が書き換えられている' >&2; exit 1 ;;
  esac
fi

# --- 既定 (フル権限) ---
dispatch
if grep -qx -- 'read-only' "$args_file"; then
  echo 'FAIL: --read-only 未指定なのに read-only サンドボックスになっている' >&2; exit 1
fi
if grep -qx -- 'mcp_servers.node_repl.enabled=false' "$args_file"; then
  echo 'FAIL: --read-only 未指定なのに node_repl が無効化されている' >&2; exit 1
fi
case ":$(cat "$path_file"):" in
  *":$pwsh_dir:"*) ;;
  *) echo 'FAIL: --read-only 未指定なのに PATH が書き換えられている' >&2; exit 1 ;;
esac

# --- PATH の境界ケース: 先頭/末尾/連続コロン + pwsh ディレクトリ2個 (拡張子なしも含む) ---
if [ "$is_windows" = 1 ]; then
  pwsh_dir2="$tmp/pwsh-dir2"
  mkdir -p "$pwsh_dir2"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$pwsh_dir2/pwsh"
  chmod +x "$pwsh_dir2/pwsh"

  AD_TEST_ARGS="$args_file" AD_TEST_PATH="$path_file" USAGE_GATE=0 \
    PATH=":$fake_bin::$pwsh_dir:$pwsh_dir2:$PATH:" bash "$runner" gpt --read-only --dir "$tmp" -- 'probe' > /dev/null
  seen="$(cat "$path_file")"

  case "$seen" in
    :*) echo 'FAIL: ro_path が先頭コロンで始まっている' >&2; exit 1 ;;
  esac
  case "$seen" in
    *:) echo 'FAIL: ro_path が末尾コロンで終わっている' >&2; exit 1 ;;
  esac
  case "$seen" in
    *::*) echo 'FAIL: ro_path に空要素が残っている' >&2; exit 1 ;;
  esac
  for d in "$pwsh_dir" "$pwsh_dir2"; do
    case ":$seen:" in
      *":$d:"*) echo "FAIL: pwsh を持つ $d が PATH に残っている" >&2; exit 1 ;;
    esac
  done
fi

echo 'agent-dispatch read-only shell tests: PASS'
