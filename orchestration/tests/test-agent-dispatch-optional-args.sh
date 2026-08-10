#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-dispatch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/fake-bin" "$tmp/work"

cat > "$tmp/fake-bin/codex" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" = -o ]]; then out="$2"; shift 2; else shift; fi
done
printf 'codex answer\n' > "$out"
EOF

for binary in cursor-agent opencode agy; do
  cat > "$tmp/fake-bin/$binary" <<'EOF'
#!/usr/bin/env bash
# agent-dispatch preflights cursor with `cursor-agent status`; answer it here so
# the test stays hermetic on nodes (and CI) with no real engine logged in.
if [[ "${1:-}" = status ]]; then printf 'logged in\n'; exit 0; fi
printf '%s\n' "$@" > "$DISPATCH_ARGS_FILE"
printf 'model answer\n'
EOF
done
chmod +x "$tmp/fake-bin/"*

common_path="$tmp/fake-bin:$PATH"

output="$(PATH="$common_path" USAGE_GATE=0 bash "$runner" gpt --dir "$tmp/work" --read-only -- 'check')"
[[ "$output" = 'codex answer' ]]

for backend in cursor opencode antigravity; do
  output="$(
    PATH="$common_path" USAGE_GATE=0 DISPATCH_ARGS_FILE="$tmp/$backend-args" \
      bash "$runner" "$backend" --dir "$tmp/work" --read-only -- 'check'
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
