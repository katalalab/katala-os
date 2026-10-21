#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-dispatch"
DISPATCH_TEST_BASH="${DISPATCH_TEST_BASH:-$BASH}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
work_dir="$tmp/work with spaces"
mkdir -p "$tmp/fake-bin" "$work_dir" "$tmp/pwsh-dir" "$tmp/coreutils-bin"

cat > "$tmp/fake-bin/codex" <<'EOF'
#!/bin/sh
if [ -n "${DISPATCH_ARGS_FILE:-}" ]; then
  normalize=0
  : > "$DISPATCH_ARGS_FILE"
  for arg in "$@"; do
    if [ "$normalize" = 1 ]; then
      printf '%s\n' '<output-file>' >> "$DISPATCH_ARGS_FILE"
      normalize=0
    else
      printf '%s\n' "$arg" >> "$DISPATCH_ARGS_FILE"
      [ "$arg" != -o ] || normalize=1
    fi
  done
fi
[ -z "${DISPATCH_PATH_FILE:-}" ] || printf '%s' "$PATH" > "$DISPATCH_PATH_FILE"
if [ "${DISPATCH_STUB_EXIT:-0}" != 0 ]; then
  printf 'stub failure\n' >&2
  exit "$DISPATCH_STUB_EXIT"
fi
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out="$2"; shift 2; else shift; fi
done
printf 'codex answer\n' > "$out"
EOF

for binary in cursor-agent opencode agy; do
  cat > "$tmp/fake-bin/$binary" <<'EOF'
#!/bin/sh
# Keep the cursor auth preflight offline.
if [ "${1:-}" = status ]; then printf 'logged in\n'; exit 0; fi
printf '%s\n' "$@" > "$DISPATCH_ARGS_FILE"
if [ "${DISPATCH_STUB_EXIT:-0}" != 0 ]; then
  printf 'stub failure\n' >&2
  exit "$DISPATCH_STUB_EXIT"
fi
printf 'model answer\n'
EOF
done

# Exercise the nonempty Windows ro_opts without calling a real Windows shell.
cat > "$tmp/fake-bin/uname" <<'EOF'
#!/bin/sh
if [ "${DISPATCH_TEST_WINDOWS:-0}" = 1 ]; then
  printf 'MINGW64_NT\n'
else
  /usr/bin/uname "$@"
fi
EOF
printf '#!/bin/sh\nexit 0\n' > "$tmp/pwsh-dir/pwsh.exe"
# Ubuntu can put pwsh and timeout in the same directory. Keep an isolated
# version of that layout so a lost timeout cannot fall back to a host binary.
cp "$tmp/pwsh-dir/pwsh.exe" "$tmp/coreutils-bin/pwsh"
cat > "$tmp/coreutils-bin/timeout" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
for utility in mktemp tr cat tail rm; do
  ln -s "$(type -P "$utility")" "$tmp/coreutils-bin/$utility"
done
# This argv test needs child exit propagation, not a host timeout implementation.
cp "$tmp/coreutils-bin/timeout" "$tmp/fake-bin/timeout"
chmod +x "$tmp/fake-bin/"* "$tmp/pwsh-dir/pwsh.exe" "$tmp/coreutils-bin/pwsh" "$tmp/coreutils-bin/timeout"
common_path="$tmp/fake-bin:$tmp/pwsh-dir:$PATH"

pass=0 fail=0
check_dispatch() {
  local backend="$1" read_mode="$2" model_kind="$3" windows="$4" want_rc="$5"
  shift 5
  local label="$backend-$read_mode-$model_kind-win$windows-exit$want_rc"
  local actual="$tmp/$label.args" expected="$tmp/$label.expected"
  local errors="$tmp/$label.err" seen_path="$tmp/$label.path"
  local prompt='check argv boundaries' output rc=0 ok=1 answer='model answer'
  local execution_path="${DISPATCH_TEST_CHILD_PATH:-$common_path}"

  if [ "$backend" = gpt ]; then
    answer='codex answer'
    {
      printf '%s\n' exec --skip-git-repo-check --color never -C "$work_dir"
      [ "$read_mode" != readonly ] || printf '%s\n' -s read-only
      if [ "$read_mode" = readonly ] && [ "$windows" = 1 ]; then
        printf '%s\n' -c mcp_servers.node_repl.enabled=false
      fi
      [ "$model_kind" != explicit ] || printf '%s\n' -m fixture-model
      printf '%s\n' -o '<output-file>' "$prompt"
    } > "$expected"
  else
    {
      printf '%s\n' -p --output-format text --trust
      if [ "$read_mode" = readonly ]; then printf '%s\n' --mode ask; else printf '%s\n' --force; fi
      [ "$model_kind" != explicit ] || printf '%s\n' --model fixture-model
      printf '%s\n' --workspace "$work_dir" "$prompt"
    } > "$expected"
  fi

  output="$(PATH="$execution_path" USAGE_GATE=0 DISPATCH_ARGS_FILE="$actual" \
    DISPATCH_PATH_FILE="$seen_path" DISPATCH_TEST_WINDOWS="$windows" DISPATCH_STUB_EXIT="$want_rc" \
    "$DISPATCH_TEST_BASH" "$runner" "$backend" --dir "$work_dir" "$@" -- "$prompt" 2>"$errors")" || rc=$?
  [ "$rc" -eq "$want_rc" ] || ok=0
  if [ "$want_rc" = 0 ]; then
    [ "$output" = "$answer" ] || ok=0
  else
    [ -z "$output" ] || ok=0
    grep -q 'stub failure' "$errors" || ok=0
  fi
  cmp -s "$expected" "$actual" || ok=0
  if [ "$backend" = gpt ] && [ -f "$seen_path" ]; then
    if [ "$windows" = 1 ]; then
      case ":$(cat "$seen_path"):" in *":$tmp/pwsh-dir:"*|*":$tmp/coreutils-bin:"*) ok=0 ;; esac
    else
      [ "$(cat "$seen_path")" = "$execution_path" ] || ok=0
    fi
  fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: expected exit %s, got %s\n' "$label" "$want_rc" "$rc" >&2
    cat "$errors" >&2
    if [ -f "$actual" ]; then diff -u "$expected" "$actual" >&2 || true; fi
  fi
}

for backend in gpt cursor; do
  check_dispatch "$backend" readonly default 0 0 --read-only
  check_dispatch "$backend" readonly explicit 0 0 --read-only --model fixture-model
  check_dispatch "$backend" write default 0 0
  check_dispatch "$backend" write explicit 0 0 --model fixture-model
  check_dispatch "$backend" readonly default 0 17 --read-only
done
check_dispatch gpt readonly default 1 0 --read-only
check_dispatch gpt readonly explicit 1 0 --read-only --model fixture-model
DISPATCH_TEST_CHILD_PATH="$tmp/fake-bin:$tmp/coreutils-bin" check_dispatch gpt readonly default 1 0 --read-only
DISPATCH_TEST_CHILD_PATH="$tmp/fake-bin:$tmp/coreutils-bin" check_dispatch gpt readonly explicit 1 0 --read-only --model fixture-model
printf 'dispatch exact-argv matrix: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

output="$(PATH="$common_path" USAGE_GATE=0 "$DISPATCH_TEST_BASH" "$runner" gpt --dir "$work_dir" --read-only -- 'check')"
[[ "$output" = 'codex answer' ]]

for backend in cursor opencode antigravity; do
  output="$(
    PATH="$common_path" USAGE_GATE=0 DISPATCH_ARGS_FILE="$tmp/$backend-args" \
      "$DISPATCH_TEST_BASH" "$runner" "$backend" --dir "$work_dir" --read-only -- 'check'
  )"
  [[ "$output" = 'model answer' ]]
done

# cursor and antigravity get no model option unless one is asked for; read-only
# opencode intentionally pins the free default model (see agent-dispatch).
for backend in cursor antigravity; do
  if grep -Eq '^(--model|-m)$' "$tmp/$backend-args"; then
    echo "unexpected model option for $backend" >&2
    exit 1
  fi
done
grep -qx -- '-m' "$tmp/opencode-args"
grep -qx 'opencode-go/deepseek-v4-flash' "$tmp/opencode-args"

grep -qx 'ask' "$tmp/cursor-args"
grep -qx 'plan' "$tmp/opencode-args"
grep -qx 'plan' "$tmp/antigravity-args"

echo 'agent-dispatch optional-argument tests: PASS'
