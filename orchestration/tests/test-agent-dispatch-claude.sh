#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-dispatch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/fake-bin" "$tmp/work space"
cat > "$tmp/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" > "$CLAUDE_CWD_FILE"
printf '%s\n' "$@" > "$CLAUDE_ARGS_FILE"
printf 'claude answer\n'
EOF
chmod +x "$tmp/fake-bin/claude"

# Literal command substitution text verifies that the dispatcher does not re-evaluate prompts.
# shellcheck disable=SC2016
prompt='review this literal prompt; $(must-not-execute)'
output="$(
  PATH="$tmp/fake-bin:$PATH" CLAUDE_CWD_FILE="$tmp/cwd" CLAUDE_ARGS_FILE="$tmp/args" \
    bash "$runner" claude --dir "$tmp/work space" --read-only --model sonnet -- "$prompt"
)"

[[ "$output" = 'claude answer' ]]
[[ "$(cat "$tmp/cwd")" = "$tmp/work space" ]]
expected=(
  -p
  --output-format text
  --permission-mode dontAsk
  --tools Read,Glob,Grep,Bash
  --no-session-persistence
  --model sonnet
  "$prompt"
)
printf '%s\n' "${expected[@]}" > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/args"

PATH="$tmp/fake-bin:$PATH" CLAUDE_CWD_FILE="$tmp/write-cwd" CLAUDE_ARGS_FILE="$tmp/write-args" \
  bash "$runner" claude --dir "$tmp/work space" -- 'write check' >/dev/null
grep -qx 'bypassPermissions' "$tmp/write-args"
! grep -qx 'dontAsk' "$tmp/write-args"
! grep -qx -- '--no-session-persistence' "$tmp/write-args"

echo 'agent-dispatch claude tests: PASS'
