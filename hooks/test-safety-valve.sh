#!/usr/bin/env bash
# Behavior test for claude-safety-valve.js: PreToolUse warns the operator
# (systemMessage), PostToolUse feeds the agent (additionalContext), clean paths
# stay silent, and malformed input never breaks the advisory contract (exit 0).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

pass=0 fail=0

# check <label> <stdin-json> <expected-ere>   (empty ere = expect no output)
check() {
  local label="$1" input="$2" expect_re="$3" out rc=0 ok=0
  out="$(printf '%s' "$input" | node claude-safety-valve.js)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -z "$expect_re" ]; then
      if [ -z "$out" ]; then ok=1; fi
    elif printf '%s' "$out" | grep -qE "$expect_re"; then
      ok=1
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-26s rc=%s out=%s\n' "$label" "$rc" "$out" >&2
  fi
}

check 'pre warns operator' \
  '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"/srv/app/.env"}}' \
  '"systemMessage"'

check 'post nudges agent' \
  '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/srv/app/.env"}}' \
  '"hookEventName":"PostToolUse".*"additionalContext"'

check 'notebook path detected' \
  '{"hook_event_name":"PostToolUse","tool_input":{"notebook_path":"/srv/prod/etl.ipynb"}}' \
  '"additionalContext"'

check 'env template stays silent' \
  '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"/srv/app/.env.example"}}' \
  ''

check 'clean path stays silent' \
  '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"/tmp/notes.md"}}' \
  ''

check 'no event field falls back to operator warning' \
  '{"tool_input":{"file_path":"/srv/app/.env"}}' \
  '"systemMessage"'

check 'malformed input fails open' \
  'not json at all' \
  ''

# The installer must register the valve on the tools the valve reads paths from.
if grep -q "matcher: 'Edit|Write|NotebookEdit'" apply-safety-valve.js \
   && grep -q "'PreToolUse', 'PostToolUse'" apply-safety-valve.js; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  printf 'FAIL installer wiring: matcher or event list drifted\n' >&2
fi

printf 'safety-valve test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
