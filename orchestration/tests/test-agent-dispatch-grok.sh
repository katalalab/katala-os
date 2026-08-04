#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-dispatch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/fake-bin" "$tmp/work space"
cat > "$tmp/fake-bin/grok" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GROK_ARGS_FILE"
printf 'grok answer\n'
EOF
chmod +x "$tmp/fake-bin/grok"

# Literal command substitution text verifies that the dispatcher does not re-evaluate prompts.
# shellcheck disable=SC2016
prompt='review this literal prompt; $(must-not-execute)'
output="$(
  PATH="$tmp/fake-bin:$PATH" GROK_ARGS_FILE="$tmp/args" \
    bash "$runner" grok --dir "$tmp/work space" --read-only --model grok-test -- "$prompt"
)"

[[ "$output" = 'grok answer' ]]
expected=(
  --permission-mode plan
  --model grok-test
  --single "$prompt"
  --cwd "$tmp/work space"
  --output-format plain
)
printf '%s\n' "${expected[@]}" > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/args"

PATH="$tmp/fake-bin:$PATH" GROK_ARGS_FILE="$tmp/write-args" \
  bash "$runner" grok --dir "$tmp/work space" -- 'write check' >/dev/null
grep -qx 'bypassPermissions' "$tmp/write-args"

echo 'agent-dispatch grok tests: PASS'
