#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACTOR="${SCRIPT_DIR}/cli-dev-team-redact.sh"
if [[ ! -f "$REDACTOR" ]]; then
  printf 'redactor\tfail\tnot found: %s\n' "$REDACTOR" >&2
  exit 2
fi
source "$REDACTOR"

STRICT=0
TARGET_DIR="${PWD}"
LMSTUDIO_URL="${LMSTUDIO_URL:-http://127.0.0.1:1234}"
PARALLEL_TMUX_SOCKET="${PARALLEL_AI_TMUX_SOCKET:-$HOME/.local/state/parallel-ai-runtime/tmux.sock}"
PROBE_TIMEOUT_SECONDS="${CLI_DEV_TEAM_PROBE_TIMEOUT_SECONDS:-20}"
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.bun/bin:$HOME/.lmstudio/bin:/Applications/Codex.app/Contents/Resources:${PATH}:/opt/homebrew/bin:/usr/local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --target)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--target requires a path\n' >&2
        exit 2
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: cli-dev-team-doctor.sh [--strict] [--target PATH]

Read-only readiness check for the local CLI development team:
Codex CLI, Claude Code CLI, Cursor Agent CLI, OpenCode, Antigravity CLI,
LM Studio, tmux, MCP surfaces, and target repository context. It never starts
services, edits config, logs in, or reads credential files.
EOF
      exit 0
      ;;
    *)
      printf 'arg\tfail\tunknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

required_failures=0
warnings=0
manuals=0
lmstudio_ready=0
opencode_provider_ready=0
antigravity_ready=0
parallel_tmux_ready=0
target_git_clean=0

probe_category() {
  local name="$1"
  case "$name" in
    generated_at|host|mode|team.*)
      printf 'metadata'
      ;;
    *.version|support.*.version)
      printf 'local_exec'
      ;;
    *.auth|antigravity.models)
      printf 'auth_or_provider'
      ;;
    *.models|*.plugins)
      printf 'provider_inventory'
      ;;
    *.mcp)
      printf 'mcp_inventory'
      ;;
    lmstudio.api)
      printf 'loopback_network'
      ;;
    lmstudio.status)
      printf 'local_runtime'
      ;;
    tmux.*)
      printf 'process_inventory'
      ;;
    target.*)
      printf 'filesystem_git'
      ;;
    *)
      printf 'uncategorized'
      ;;
  esac
}

probe_impact() {
  local name="$1"
  case "$name" in
    generated_at|host|mode|team.*)
      printf 'no_probe'
      ;;
    *.version|support.*.version)
      printf 'executes_local_cli_version_only'
      ;;
    codex.auth|opencode.auth)
      printf 'reads_auth_status'
      ;;
    antigravity.models)
      printf 'may_touch_provider_auth_state'
      ;;
    cursor.models|opencode.models)
      printf 'provider_model_inventory'
      ;;
    antigravity.plugins)
      printf 'provider_plugin_inventory'
      ;;
    codex.mcp|claude.mcp|opencode.mcp)
      printf 'reads_mcp_registry'
      ;;
    lmstudio.api)
      printf 'loopback_http_get'
      ;;
    lmstudio.status)
      printf 'reads_local_runtime_status'
      ;;
    tmux.*)
      printf 'reads_process_session_table'
      ;;
    target.git_status)
      printf 'reads_git_worktree_status'
      ;;
    target.instructions)
      printf 'finds_instruction_files'
      ;;
    target.*)
      printf 'reads_filesystem_metadata'
      ;;
    *)
      printf 'read_only_probe'
      ;;
  esac
}

record() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  local severity="${4:-required}"

  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$detail" "$(probe_category "$name")" "$(probe_impact "$name")"

  case "$status" in
    ok)
      ;;
    warn)
      warnings=$((warnings + 1))
      ;;
    manual)
      manuals=$((manuals + 1))
      ;;
    *)
      if [[ "$severity" == "advisory" ]]; then
        warnings=$((warnings + 1))
      else
        required_failures=$((required_failures + 1))
      fi
      ;;
  esac
}

record_info() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$detail" "$(probe_category "$name")" "$(probe_impact "$name")"
}

capture() {
  local tmp pid start now elapsed rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/cli-dev-team-doctor-capture.XXXXXX")" || return 97
  "$@" > "$tmp" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$PROBE_TIMEOUT_SECONDS" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      printf 'timeout=%ss\n' "$PROBE_TIMEOUT_SECONDS"
      sed -n '1,20p' "$tmp"
      rm -f "$tmp"
      return 124
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  cat "$tmp"
  rm -f "$tmp"
  return "$rc"
}

check_version() {
  local label="$1"
  shift
  local cmd="$1"
  shift
  local path out rc
  path="$(command -v "$cmd" 2>/dev/null || true)"
  if [[ -z "$path" ]]; then
    record "$label.version" "fail" "$cmd not found"
    return
  fi
  out="$(capture "$cmd" "$@")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record "$label.version" "ok" "$path :: $(printf '%s' "$out" | clean_detail)"
  else
    record "$label.version" "fail" "rc=$rc :: $path :: $(printf '%s' "$out" | clean_detail)"
  fi
}

check_optional_version() {
  local label="$1"
  shift
  local cmd="$1"
  shift
  local path out rc
  path="$(command -v "$cmd" 2>/dev/null || true)"
  if [[ -z "$path" ]]; then
    record_info "support.${label}.version" "missing" "$cmd not found"
    return
  fi
  out="$(capture "$cmd" "$@")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record_info "support.${label}.version" "ok" "$path :: $(printf '%s' "$out" | clean_detail)"
  else
    record_info "support.${label}.version" "warn" "rc=$rc :: $path :: $(printf '%s' "$out" | clean_detail)"
  fi
}

check_contains() {
  local label="$1"
  local expected="$2"
  local severity="${3:-required}"
  shift 3
  local out rc
  out="$(capture "$@")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "$label" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)" "$severity"
    return
  fi
  if printf '%s\n' "$out" | grep -Fq "$expected"; then
    record "$label" "ok" "$(printf '%s' "$out" | clean_detail)"
  else
    if [[ "$severity" == "advisory" ]]; then
      record "$label" "warn" "expected '$expected' not found :: $(printf '%s' "$out" | clean_detail)" "$severity"
    else
      record "$label" "fail" "expected '$expected' not found :: $(printf '%s' "$out" | clean_detail)" "$severity"
    fi
  fi
}

check_codex_mcp() {
  local out rc enabled disabled
  out="$(capture codex mcp list)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "codex.mcp" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return
  fi
  enabled="$(printf '%s\n' "$out" | awk '$0 ~ / enabled / {count++} END {print count+0}')"
  disabled="$(printf '%s\n' "$out" | awk '$0 ~ / disabled / {count++} END {print count+0}')"
  if [[ "$enabled" -gt 0 ]]; then
    record "codex.mcp" "ok" "enabled=$enabled disabled=$disabled"
  else
    record "codex.mcp" "warn" "no enabled MCP servers detected"
  fi
}

check_claude_mcp() {
  local out rc connected
  out="$(capture claude mcp list)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "claude.mcp" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)" "advisory"
    return
  fi
  connected="$(printf '%s\n' "$out" | awk '$0 ~ /Connected/ {count++} END {print count+0}')"
  if [[ "$connected" -gt 0 ]]; then
    record "claude.mcp" "ok" "connected=$connected"
  else
    record "claude.mcp" "warn" "no connected MCP servers detected"
  fi
}

check_opencode_mcp() {
  local out rc connected
  out="$(capture opencode mcp list)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "opencode.mcp" "warn" "rc=$rc :: $(printf '%s' "$out" | clean_detail)" "advisory"
    return
  fi
  connected="$(printf '%s\n' "$out" | awk '$0 ~ /connected/ {count++} END {print count+0}')"
  if [[ "$connected" -gt 0 ]]; then
    record "opencode.mcp" "ok" "connected=$connected"
  else
    record "opencode.mcp" "warn" "no connected MCP servers detected"
  fi
}

check_cursor_models() {
  local out rc count
  out="$(capture cursor-agent --list-models)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "cursor.models" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return
  fi
  count="$(printf '%s\n' "$out" | awk '/ - / {count++} END {print count+0}')"
  if [[ "$count" -gt 0 ]]; then
    record "cursor.models" "ok" "available_models=$count"
  else
    record "cursor.models" "warn" "model list returned but no models parsed"
  fi
}

check_opencode_auth_and_models() {
  local auth_out auth_rc models_out models_rc model_count
  auth_out="$(capture opencode auth list)"
  auth_rc=$?
  if [[ "$auth_rc" -ne 0 ]]; then
    record "opencode.auth" "warn" "rc=$auth_rc :: $(printf '%s' "$auth_out" | clean_detail)" "advisory"
  elif printf '%s\n' "$auth_out" | grep -Eq '0 credentials|No credentials'; then
    record "opencode.auth" "ok" "0 credentials; using provider-only lane when opencode provider models are available"
  else
    record "opencode.auth" "ok" "$(printf '%s' "$auth_out" | clean_detail)"
  fi

  models_out="$(capture opencode models opencode)"
  models_rc=$?
  if [[ "$models_rc" -ne 0 ]]; then
    record "opencode.models" "warn" "rc=$models_rc :: $(printf '%s' "$models_out" | clean_detail)" "advisory"
    return
  fi
  model_count="$(printf '%s\n' "$models_out" | awk '/^opencode\// {count++} END {print count+0}')"
  if [[ "$model_count" -gt 0 ]]; then
    opencode_provider_ready=1
    record "opencode.models" "ok" "opencode_provider_models=$model_count"
  else
    record "opencode.models" "warn" "no opencode provider models parsed" "advisory"
  fi
}

check_antigravity_models_and_plugins() {
  local models_out models_rc model_count plugins_out plugins_rc
  models_out="$(capture agy models)"
  models_rc=$?
  if [[ "$models_rc" -ne 0 ]]; then
    if printf '%s\n' "$models_out" | grep -Fqi "sign in"; then
      record "antigravity.models" "manual" "sign-in required :: $(printf '%s' "$models_out" | clean_detail)" "advisory"
    else
      record "antigravity.models" "warn" "rc=$models_rc :: $(printf '%s' "$models_out" | clean_detail)" "advisory"
    fi
  else
    model_count="$(printf '%s\n' "$models_out" | awk 'NF {count++} END {print count+0}')"
    if [[ "$model_count" -gt 0 ]]; then
      antigravity_ready=1
      record "antigravity.models" "ok" "available_models=$model_count"
    else
      record "antigravity.models" "warn" "model list returned but no models parsed" "advisory"
    fi
  fi

  plugins_out="$(capture agy plugin list)"
  plugins_rc=$?
  if [[ "$plugins_rc" -eq 0 ]]; then
    record "antigravity.plugins" "ok" "$(printf '%s' "$plugins_out" | clean_detail)"
  else
    record "antigravity.plugins" "warn" "rc=$plugins_rc :: $(printf '%s' "$plugins_out" | clean_detail)" "advisory"
  fi
}

check_lmstudio() {
  local out rc api_out api_rc
  out="$(capture lms status)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "lmstudio.status" "warn" "rc=$rc :: $(printf '%s' "$out" | clean_detail)" "advisory"
    return
  fi
  if printf '%s\n' "$out" | grep -Eq 'Server:[[:space:]]+ON'; then
    record "lmstudio.status" "ok" "$(printf '%s' "$out" | clean_detail)"
    if command -v curl >/dev/null 2>&1; then
      api_out="$(capture curl -fsS --max-time 2 "$LMSTUDIO_URL/v1/models")"
      api_rc=$?
      if [[ "$api_rc" -eq 0 ]]; then
        lmstudio_ready=1
        record "lmstudio.api" "ok" "$LMSTUDIO_URL/v1/models reachable"
      else
        record "lmstudio.api" "warn" "rc=$api_rc :: $(printf '%s' "$api_out" | clean_detail)" "advisory"
      fi
    else
      record "lmstudio.api" "warn" "curl not found; skipped API reachability" "advisory"
    fi
  else
    record "lmstudio.status" "warn" "$(printf '%s' "$out" | clean_detail)" "advisory"
  fi
}

check_tmux() {
  local out rc panes default_detail socket_detail
  out="$(capture tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} pid=#{pane_pid} cmd=#{pane_current_command} cwd=#{pane_current_path}')"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    panes="$(printf '%s\n' "$out" | awk 'NF {count++} END {print count+0}')"
    default_detail="default_socket_panes=$panes"
    record "tmux.default" "ok" "$default_detail"
  else
    record "tmux.default" "ok" "unused; dedicated socket is checked by tmux.parallel_socket"
  fi

  if [[ -S "$PARALLEL_TMUX_SOCKET" ]]; then
    out="$(capture tmux -S "$PARALLEL_TMUX_SOCKET" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}')"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      panes="$(printf '%s\n' "$out" | awk 'NF {count++} END {print count+0}')"
      socket_detail="socket=$PARALLEL_TMUX_SOCKET panes=$panes"
      parallel_tmux_ready=1
      record "tmux.parallel_socket" "ok" "$socket_detail"
    else
      record "tmux.parallel_socket" "warn" "rc=$rc :: $PARALLEL_TMUX_SOCKET :: $(printf '%s' "$out" | clean_detail)" "advisory"
    fi
  else
    record "tmux.parallel_socket" "warn" "missing socket: $PARALLEL_TMUX_SOCKET" "advisory"
  fi
}

check_target_repo() {
  local root status_out rc status_count agents_path
  if [[ ! -d "$TARGET_DIR" ]]; then
    record "target.path" "fail" "not a directory: $TARGET_DIR"
    return
  fi
  record "target.path" "ok" "$TARGET_DIR"

  root="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$root" ]]; then
    record "target.git" "warn" "not inside a git repository" "advisory"
    return
  fi
  record "target.git_root" "ok" "$root"
  status_out="$(capture git -C "$root" status --short)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "target.git_status" "warn" "rc=$rc :: $(printf '%s' "$status_out" | clean_detail)" "advisory"
  else
    status_count="$(printf '%s\n' "$status_out" | awk 'NF {count++} END {print count+0}')"
    if [[ "$status_count" -eq 0 ]]; then
      target_git_clean=1
      record "target.git_status" "ok" "clean"
    else
      record "target.git_status" "manual" "dirty_entries=$status_count; inspect before multi-agent writes" "advisory"
    fi
  fi

  agents_path="$(find "$root" -name AGENTS.md -o -name AGENTS.MD 2>/dev/null | sed -n '1p')"
  if [[ -n "$agents_path" ]]; then
    record "target.instructions" "ok" "$agents_path"
  else
    record "target.instructions" "warn" "no repo-local AGENTS.md found under $root" "advisory"
  fi
}

printf '# CLI Dev Team Doctor\n'
record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
record "host" "ok" "$(hostname)"
record "mode" "ok" "$(if [[ "$STRICT" -eq 1 ]]; then printf strict; else printf inventory; fi)"

printf '\n## Versions\n'
check_version "codex" codex --version
check_version "claude" claude --version
check_version "cursor_agent" cursor-agent --version
check_version "opencode" opencode --version
check_version "antigravity" agy --version
check_version "lms" lms --version
check_version "tmux" tmux -V

printf '\n## Support CLI Inventory\n'
check_optional_version "go" go version
check_optional_version "aider" aider --version
check_optional_version "gemini" gemini --version
check_optional_version "ollama" ollama --version
check_optional_version "cmux" cmux --version
check_optional_version "gh" gh --version
check_optional_version "gcloud" gcloud --version
check_optional_version "wrangler" wrangler --version
check_optional_version "vercel" vercel --version
check_optional_version "bun" bun --version
check_optional_version "node" node --version
check_optional_version "npm" npm --version
check_optional_version "uv" uv --version
check_optional_version "python3" python3 --version
check_optional_version "op" op --version

printf '\n## Auth And Models\n'
check_contains "codex.auth" "Logged in" "required" codex login status
check_cursor_models
check_opencode_auth_and_models
check_antigravity_models_and_plugins

printf '\n## MCP\n'
check_codex_mcp
check_claude_mcp
check_opencode_mcp

printf '\n## Local Runtime\n'
check_lmstudio
check_tmux

printf '\n## Target Context\n'
check_target_repo

printf '\n## Summary\n'
if [[ "$required_failures" -eq 0 ]]; then
  record "team.core_ready" "ok" "Codex + Claude + Cursor + tmux core checks passed"
else
  record "team.core_ready" "fail" "required_failures=$required_failures"
fi

if [[ "$required_failures" -eq 0 && "$lmstudio_ready" -eq 1 && "$opencode_provider_ready" -eq 1 && "$antigravity_ready" -eq 1 && "$parallel_tmux_ready" -eq 1 ]]; then
  record "team.readonly_ready" "ok" "Codex + Claude + Cursor + OpenCode provider + Antigravity + LM Studio API + dedicated tmux ready"
else
  record "team.readonly_ready" "warn" "required_failures=$required_failures lmstudio_ready=$lmstudio_ready opencode_provider_ready=$opencode_provider_ready antigravity_ready=$antigravity_ready parallel_tmux_ready=$parallel_tmux_ready" "advisory"
fi

if [[ "$target_git_clean" -eq 1 ]]; then
  record "team.write_ready" "ok" "target git tree clean; write packet gates can be evaluated"
else
  record "team.write_ready" "manual" "target git tree is dirty or unavailable; write dispatch must remain gate-only" "advisory"
fi

if [[ "$warnings" -eq 0 && "$manuals" -eq 0 && "$required_failures" -eq 0 ]]; then
  record "team.full_ready" "ok" "all checked surfaces ready"
else
  record "team.full_ready" "warn" "required_failures=$required_failures warnings=$warnings manuals=$manuals" "advisory"
fi

if [[ "$STRICT" -eq 1 && "$required_failures" -ne 0 ]]; then
  exit 1
fi

exit 0
