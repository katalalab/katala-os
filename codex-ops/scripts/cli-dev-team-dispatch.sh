#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACTOR="${SCRIPT_DIR}/cli-dev-team-redact.sh"
if [[ ! -f "$REDACTOR" ]]; then
  printf 'redactor\tfail\tnot found: %s\n' "$REDACTOR" >&2
  exit 2
fi
source "$REDACTOR"

TARGET_DIR="${PWD}"
TARGET_SET=0
ROLES="codex,claude,cursor,antigravity,opencode,lmstudio"
ROLES_SET=0
PROMPT="Read-only smoke test for a persistent CLI development team. Do not edit files, do not run shell commands, and do not change configuration. Reply with your role name followed by READY."
PROMPT_SET=0
OUTPUT_DIR=""
DRY_RUN=0
SKIP_FANOUT_GATE=0
TIMEOUT_SECONDS=180
TIMEOUT_SET=0
LMSTUDIO_URL="${LMSTUDIO_URL:-http://127.0.0.1:1234}"
FANOUT_GATE_SCRIPT="${FANOUT_GATE_SCRIPT:-$HOME/work/docs/scripts/agent-fanout-readiness-check.py}"
PACKET=""
PACKET_ID=""
PACKET_MODE="readonly"
PACKET_WRITE=0
PACKET_FILES_OWNED=""
PACKET_VERIFIER=""
PACKET_EXECUTOR=""
ALLOW_WRITE=0
POST_CHECK=0
RUN_VERIFIER=0
RUN_SECOND_REVIEW=0
RUN_ROLLBACK=0
EXECUTE_WRITE=0
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.bun/bin:$HOME/.lmstudio/bin:/Applications/Codex.app/Contents/Resources:${PATH}:/opt/homebrew/bin:/usr/local/bin"

usage() {
  cat <<'EOF'
Usage: cli-dev-team-dispatch.sh [options]

Read-only dispatcher for the local CLI development team. It runs selected agents
serially, stores each role's output under an evidence directory, and writes a TSV
summary. It does not edit the target repository, start services, log in, or change
CLI configuration.

Options:
  --packet FILE       JSON task packet. Supports id, target, roles, mode,
                      prompt, timeout_seconds, files_owned, verifier.
                      Write modes require --allow-write. Write execution also
                      requires --execute-write.
  --allow-write       Validate write/workspace-write packets. This does not
                      execute write agents yet.
  --execute-write     Run packet executor.command after the clean-tree write
                      gate, then run post-check validation. Requires
                      --allow-write --run-verifier --run-second-review.
  --post-check        For write packets: validate the current git diff after a
                      separate write step. Requires --allow-write.
  --run-verifier      During post-check, run verifier.command in the target repo.
  --run-second-review During post-check, run second_review.command in the target repo.
  --run-rollback      During post-check, run rollback.command after backing up the
                      current diff into the evidence directory.
  --target PATH        Workspace path for the agents. Defaults to current directory.
  --roles CSV         Roles to run. Defaults to codex,claude,cursor,antigravity,opencode,lmstudio.
                      Supported: codex, claude, cursor, antigravity, agy, opencode, lmstudio.
  --prompt TEXT       Prompt sent to agent roles.
  --output-dir PATH   Evidence output directory. Created unless --dry-run is set.
  --timeout SECONDS   Per-role timeout. Defaults to 180.
  --dry-run           Print planned commands only.
  --skip-fanout-gate  Allow actual multi-role readonly dispatch even when the
                      local fan-out readiness gate fails. Use only after a
                      fresh manual review.
  -h, --help          Show this help.

Environment:
  LMSTUDIO_URL        LM Studio base URL. Defaults to http://127.0.0.1:1234.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --packet)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--packet requires a path\n' >&2
        exit 2
      fi
      PACKET="$2"
      shift 2
      ;;
    --target)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--target requires a path\n' >&2
        exit 2
      fi
      TARGET_DIR="$2"
      TARGET_SET=1
      shift 2
      ;;
    --roles)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--roles requires a comma-separated value\n' >&2
        exit 2
      fi
      ROLES="$2"
      ROLES_SET=1
      shift 2
      ;;
    --prompt)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--prompt requires text\n' >&2
        exit 2
      fi
      PROMPT="$2"
      PROMPT_SET=1
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--output-dir requires a path\n' >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--timeout requires seconds\n' >&2
        exit 2
      fi
      TIMEOUT_SECONDS="$2"
      TIMEOUT_SET=1
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-fanout-gate)
      SKIP_FANOUT_GATE=1
      shift
      ;;
    --allow-write)
      ALLOW_WRITE=1
      shift
      ;;
    --execute-write)
      EXECUTE_WRITE=1
      shift
      ;;
    --post-check)
      POST_CHECK=1
      shift
      ;;
    --run-verifier)
      RUN_VERIFIER=1
      shift
      ;;
    --run-second-review)
      RUN_SECOND_REVIEW=1
      shift
      ;;
    --run-rollback)
      RUN_ROLLBACK=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'arg\tfail\tunknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  printf 'arg\tfail\t--timeout must be a positive integer\n' >&2
  exit 2
fi

if [[ -n "$PACKET" ]]; then
  if [[ ! -f "$PACKET" ]]; then
    printf 'packet\tfail\tnot a file: %s\n' "$PACKET" >&2
    exit 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'packet\tfail\tjq not found; cannot parse JSON task packet\n' >&2
    exit 2
  fi
  if ! jq -e . "$PACKET" >/dev/null; then
    printf 'packet\tfail\tinvalid JSON: %s\n' "$PACKET" >&2
    exit 2
  fi

  PACKET_ID="$(jq -r '.id // empty' "$PACKET")"
  PACKET_MODE="$(jq -r '.mode // "readonly"' "$PACKET")"
  PACKET_FILES_OWNED="$(jq -c '.files_owned // []' "$PACKET")"
  PACKET_VERIFIER="$(jq -r 'if (.verifier | type) == "object" then (.verifier | tojson) else (.verifier // empty) end' "$PACKET")"
  PACKET_EXECUTOR="$(jq -r 'if (.executor | type) == "object" then (.executor | tojson) else empty end' "$PACKET")"

  case "$PACKET_MODE" in
    readonly|read-only)
      ;;
    write|workspace-write)
      if [[ "$ALLOW_WRITE" -ne 1 ]]; then
        printf 'packet\tfail\twrite mode requires --allow-write and remains gate-only: %s\n' "$PACKET_MODE" >&2
        exit 2
      fi
      PACKET_WRITE=1
      ;;
    *)
      printf 'packet\tfail\tmode must be readonly/read-only/write/workspace-write: %s\n' "$PACKET_MODE" >&2
      exit 2
      ;;
  esac

  if [[ "$TARGET_SET" -eq 0 ]]; then
    packet_target="$(jq -r '.target // empty' "$PACKET")"
    [[ -n "$packet_target" ]] && TARGET_DIR="$packet_target"
  fi
  if [[ "$ROLES_SET" -eq 0 ]]; then
    packet_roles="$(jq -r 'if has("roles") then (if (.roles|type) == "array" then (.roles|join(",")) else (.roles|tostring) end) else empty end' "$PACKET")"
    [[ -n "$packet_roles" ]] && ROLES="$packet_roles"
  fi
  if [[ "$PROMPT_SET" -eq 0 ]]; then
    packet_prompt="$(jq -r '.prompt // empty' "$PACKET")"
    [[ -n "$packet_prompt" ]] && PROMPT="$packet_prompt"
  fi
  if [[ "$TIMEOUT_SET" -eq 0 ]]; then
    packet_timeout="$(jq -r '.timeout_seconds // empty' "$PACKET")"
    [[ -n "$packet_timeout" ]] && TIMEOUT_SECONDS="$packet_timeout"
  fi
fi

if [[ "$EXECUTE_WRITE" -eq 1 ]]; then
  if [[ "$PACKET_WRITE" -ne 1 ]]; then
    printf 'packet\tfail\t--execute-write requires a write/workspace-write packet\n' >&2
    exit 2
  fi
  if [[ "$RUN_VERIFIER" -ne 1 || "$RUN_SECOND_REVIEW" -ne 1 ]]; then
    printf 'packet\tfail\t--execute-write requires --run-verifier and --run-second-review\n' >&2
    exit 2
  fi
fi

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  printf 'arg\tfail\t--timeout must be a positive integer\n' >&2
  exit 2
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  printf 'target\tfail\tnot a directory: %s\n' "$TARGET_DIR" >&2
  exit 2
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$HOME/work/docs/agent-team-design/evidence/dispatch-$(date '+%Y%m%dT%H%M%SJST')"
fi

summary_file="${OUTPUT_DIR}/summary.tsv"

quote_cmd() {
  local rendered=""
  local part
  for part in "$@"; do
    rendered+="$(printf '%q' "$part") "
  done
  printf '%s' "${rendered% }"
}

record() {
  local role="$1"
  local status="$2"
  local detail="${3:-}"
  printf '%s\t%s\t%s\n' "$role" "$status" "$detail"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    printf '%s\t%s\t%s\n' "$role" "$status" "$detail" >> "$summary_file"
  fi
}

record_gate() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  record "packet_gate.${name}" "$status" "$detail"
  [[ "$status" == "ok" ]]
}

terminate_process_tree() {
  local pid="$1"
  local child
  while IFS= read -r child; do
    [[ -z "$child" ]] && continue
    terminate_process_tree "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
  kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$pid" 2>/dev/null || true
}

run_shell_with_timeout() {
  local root="$1"
  local command_text="$2"
  local outfile="$3"
  local rc pid start now elapsed

  (
    cd "$root" || exit 97
    bash -lc "$command_text"
  ) > "$outfile" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
      terminate_process_tree "$pid"
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  return "$rc"
}

is_owned_file() {
  local path="$1"
  jq -e --arg path "$path" '(.files_owned // []) | index($path) != null' "$PACKET" >/dev/null
}

validate_owned_file_path() {
  local root="$1"
  local path="$2"
  local root_real candidate parent parent_real

  root_real="$(cd "$root" && pwd -P)" || return 1
  candidate="${root}/${path}"
  parent="$(dirname "$candidate")"

  if [[ -L "$candidate" ]]; then
    record_gate "files_owned_realpath" "fail" "owned path is a symlink: $path"
    return 1
  fi

  if [[ ! -d "$parent" ]]; then
    record_gate "files_owned_realpath" "fail" "owned path parent does not exist: $path"
    return 1
  fi

  parent_real="$(cd "$parent" && pwd -P)" || return 1
  case "${parent_real}/" in
    "${root_real}/"| "${root_real}/"*)
      record_gate "files_owned_realpath" "ok" "$path"
      return 0
      ;;
    *)
      record_gate "files_owned_realpath" "fail" "owned path parent escapes git root: $path"
      return 1
      ;;
  esac
}

write_changed_files() {
  local root="$1"
  {
    git -C "$root" diff --name-only --relative --cached -- 2>/dev/null || true
    git -C "$root" diff --name-only --relative -- 2>/dev/null || true
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null || true
  } | LC_ALL=C sort -u
}

run_packet_verifier() {
  local root="$1"
  local verifier_command="$2"
  local verifier_out="${OUTPUT_DIR}/verifier.out"
  local rc snippet

  if [[ "$RUN_VERIFIER" -ne 1 ]]; then
    record_gate "verifier_run" "manual" "not run; pass --run-verifier during --post-check"
    return 0
  fi

  run_shell_with_timeout "$root" "$verifier_command" "$verifier_out"
  rc=$?
  snippet="$(sed -n '1,20p' "$verifier_out" 2>/dev/null | clean_detail)"
  if [[ "$rc" -eq 124 ]]; then
    record_gate "verifier_run" "fail" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
    return 1
  fi
  if [[ "$rc" -eq 0 ]]; then
    record_gate "verifier_run" "ok" "rc=0 :: $snippet"
    return 0
  fi
  record_gate "verifier_run" "fail" "rc=$rc :: $snippet"
  return 1
}

run_packet_second_review() {
  local root="$1"
  local review_command
  local review_out="${OUTPUT_DIR}/second_review.out"
  local rc snippet

  if [[ "$RUN_SECOND_REVIEW" -ne 1 ]]; then
    record_gate "second_review_run" "manual" "not run; pass --run-second-review during --post-check"
    return 0
  fi

  review_command="$(jq -r '.second_review.command // empty' "$PACKET")"
  if [[ -z "$review_command" ]]; then
    record_gate "second_review_run" "fail" "second_review.command is required with --run-second-review"
    return 1
  fi

  run_shell_with_timeout "$root" "$review_command" "$review_out"
  rc=$?
  snippet="$(sed -n '1,20p' "$review_out" 2>/dev/null | clean_detail)"
  if [[ "$rc" -eq 124 ]]; then
    record_gate "second_review_run" "fail" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
    return 1
  fi
  if [[ "$rc" -eq 0 ]]; then
    record_gate "second_review_run" "ok" "rc=0 :: $snippet"
    return 0
  fi
  record_gate "second_review_run" "fail" "rc=$rc :: $snippet"
  return 1
}

backup_write_state() {
  local root="$1"
  local backup_dir="${OUTPUT_DIR}/rollback-backup"
  local untracked_file="${backup_dir}/untracked-files.txt"
  local rc

  mkdir -p "$backup_dir"
  git -C "$root" status --porcelain=v1 > "${backup_dir}/status.txt" 2>&1 || true
  git -C "$root" diff --binary > "${backup_dir}/working.diff" 2>&1 || true
  git -C "$root" diff --cached --binary > "${backup_dir}/staged.diff" 2>&1 || true
  git -C "$root" ls-files --others --exclude-standard > "$untracked_file" 2>&1 || true
  if [[ -s "$untracked_file" ]]; then
    (
      cd "$root" || exit 97
      tar -czf "${backup_dir}/untracked.tar.gz" -T "$untracked_file"
    ) >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      record_gate "rollback_backup" "fail" "failed to archive untracked files rc=$rc"
      return 1
    fi
  fi

  record_gate "rollback_backup" "ok" "path=$backup_dir"
  record "packet_gate.rollback_restore" "manual" "restore tracked: git -C $(printf '%q' "$root") apply ${backup_dir}/working.diff && git -C $(printf '%q' "$root") apply --cached ${backup_dir}/staged.diff"
  record "packet_gate.rollback_backup_retention" "ok" "evidence retention: keep with dispatch evidence; prune by deleting this evidence directory"
  return 0
}

run_packet_rollback() {
  local root="$1"
  local rollback_command
  local rollback_out="${OUTPUT_DIR}/rollback.out"
  local rc snippet

  if [[ "$RUN_ROLLBACK" -ne 1 ]]; then
    record_gate "rollback_run" "manual" "not run; pass --run-rollback during --post-check"
    return 0
  fi

  rollback_command="$(jq -r '.rollback.command // empty' "$PACKET")"
  if [[ -z "$rollback_command" ]]; then
    record_gate "rollback_run" "fail" "rollback.command is required with --run-rollback"
    return 1
  fi

  backup_write_state "$root" || return 1
  run_shell_with_timeout "$root" "$rollback_command" "$rollback_out"
  rc=$?
  snippet="$(sed -n '1,20p' "$rollback_out" 2>/dev/null | clean_detail)"
  if [[ "$rc" -eq 124 ]]; then
    record_gate "rollback_run" "fail" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
    return 1
  fi
  if [[ "$rc" -eq 0 ]]; then
    record_gate "rollback_run" "ok" "rc=0 :: $snippet"
    return 0
  fi
  record_gate "rollback_run" "fail" "rc=$rc :: $snippet"
  return 1
}

run_packet_executor() {
  local root="$1"
  local executor_command
  local executor_out="${OUTPUT_DIR}/executor.out"
  local rc snippet pid start now elapsed

  executor_command="$(jq -r '.executor.command // empty' "$PACKET")"
  if [[ -z "$executor_command" ]]; then
    record_gate "executor_run" "fail" "executor.command is required with --execute-write"
    return 1
  fi

  (
    cd "$root" || exit 97
    bash -lc "$executor_command"
  ) > "$executor_out" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
      terminate_process_tree "$pid"
      wait "$pid" 2>/dev/null || true
      snippet="$(sed -n '1,20p' "$executor_out" 2>/dev/null | clean_detail)"
      record_gate "executor_run" "fail" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  snippet="$(sed -n '1,20p' "$executor_out" 2>/dev/null | clean_detail)"
  if [[ "$rc" -eq 0 ]]; then
    record_gate "executor_run" "ok" "rc=0 :: $snippet"
    return 0
  fi
  record_gate "executor_run" "fail" "rc=$rc :: $snippet"
  return 1
}

validate_write_packet() {
  local failures=0
  local root status_out path rel_dup_count
  local verifier_command rollback_ok review_ok changed_count changed_file outside_count

  if [[ -z "$PACKET_ID" ]]; then
    record_gate "id" "fail" "id is required"
    failures=$((failures + 1))
  else
    record_gate "id" "ok" "$PACKET_ID"
  fi

  root="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$root" ]]; then
    record_gate "git_root" "fail" "target is not inside a git repository: $TARGET_DIR"
    failures=$((failures + 1))
  else
    record_gate "git_root" "ok" "$root"
    if [[ "$POST_CHECK" -eq 1 ]]; then
      status_out="$(write_changed_files "$root")"
      changed_count="$(printf '%s\n' "$status_out" | awk 'NF {count++} END {print count+0}')"
      record_gate "git_status" "ok" "post-check mode; changed_files=$changed_count"
      outside_count=0
      while IFS= read -r changed_file; do
        [[ -z "$changed_file" ]] && continue
        if is_owned_file "$changed_file"; then
          record_gate "changed_file" "ok" "$changed_file"
        else
          record_gate "changed_file" "fail" "outside files_owned: $changed_file"
          outside_count=$((outside_count + 1))
        fi
      done <<< "$status_out"
      if [[ "$outside_count" -eq 0 ]]; then
        record_gate "changed_scope" "ok" "all changed files are within files_owned"
      else
        record_gate "changed_scope" "fail" "outside_files=$outside_count"
        failures=$((failures + 1))
      fi
    else
      status_out="$(git -C "$root" status --porcelain --untracked-files=all 2>/dev/null || true)"
      if [[ -n "$status_out" ]]; then
        record_gate "git_status" "fail" "dirty tree; inspect before write dispatch"
        failures=$((failures + 1))
      else
        record_gate "git_status" "ok" "clean"
      fi
    fi
  fi

  if jq -e '(.files_owned | type == "array") and ((.files_owned | length) > 0) and all(.files_owned[]; (type == "string") and (length > 0))' "$PACKET" >/dev/null; then
    record_gate "files_owned" "ok" "$PACKET_FILES_OWNED"
  else
    record_gate "files_owned" "fail" "files_owned must be a non-empty string array"
    failures=$((failures + 1))
  fi

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in
      /*|~*|*'/../'*|../*|*'/..'|.)
        record_gate "files_owned_path" "fail" "unsafe relative path: $path"
        failures=$((failures + 1))
        ;;
    esac
    if [[ -n "$root" ]]; then
      if ! validate_owned_file_path "$root" "$path"; then
        failures=$((failures + 1))
      fi
    fi
  done < <(jq -r '.files_owned[]? // empty' "$PACKET")

  rel_dup_count="$(jq -r '([.files_owned[]?] | length) - ([.files_owned[]?] | unique | length)' "$PACKET")"
  if [[ "$rel_dup_count" =~ ^[0-9]+$ && "$rel_dup_count" -eq 0 ]]; then
    record_gate "ownership_conflict" "ok" "no duplicate owned paths"
  else
    record_gate "ownership_conflict" "fail" "duplicate files_owned entries"
    failures=$((failures + 1))
  fi

  review_ok="$(jq -r 'if ((.second_review.required == true) and (((.second_review.role // .second_review.reviewer // "") | strings | length) > 0 or ((.second_review.roles // []) | type == "array" and length > 0))) then "ok" else "fail" end' "$PACKET")"
  if [[ "$review_ok" == "ok" ]]; then
    record_gate "second_review" "ok" "$(jq -c '.second_review' "$PACKET")"
  else
    record_gate "second_review" "fail" "second_review.required=true and reviewer/role/roles are required"
    failures=$((failures + 1))
  fi

  verifier_command="$(jq -r 'if (.verifier | type) == "object" then (.verifier.command // "") else (.verifier // "") end' "$PACKET")"
  if [[ -n "$verifier_command" ]]; then
    record_gate "verifier" "ok" "$verifier_command"
  else
    record_gate "verifier" "fail" "verifier.command or verifier string is required"
    failures=$((failures + 1))
  fi

  if [[ "$EXECUTE_WRITE" -eq 1 && "$POST_CHECK" -eq 0 ]]; then
    if jq -e '(.executor | type == "object") and (((.executor.command // "") | strings | length) > 0)' "$PACKET" >/dev/null; then
      record_gate "executor" "ok" "$(jq -c '.executor' "$PACKET")"
    else
      record_gate "executor" "fail" "executor.command is required with --execute-write"
      failures=$((failures + 1))
    fi
  fi

  rollback_ok="$(jq -r 'if ((.rollback | type) == "object") and (((.rollback.command // "") | strings | length) > 0 or ((.rollback.steps // []) | type == "array" and length > 0)) then "ok" else "fail" end' "$PACKET")"
  if [[ "$rollback_ok" == "ok" ]]; then
    record_gate "rollback" "ok" "$(jq -c '.rollback' "$PACKET")"
  else
    record_gate "rollback" "fail" "rollback.command or rollback.steps is required"
    failures=$((failures + 1))
  fi

  if [[ "$POST_CHECK" -eq 1 && "$failures" -eq 0 ]]; then
    if ! run_packet_verifier "$root" "$verifier_command"; then
      failures=$((failures + 1))
    fi
  fi

  if [[ "$POST_CHECK" -eq 1 && "$failures" -eq 0 ]]; then
    if ! run_packet_second_review "$root"; then
      failures=$((failures + 1))
    fi
  fi

  if [[ "$POST_CHECK" -eq 1 && "$RUN_ROLLBACK" -eq 1 ]]; then
    if ! run_packet_rollback "$root"; then
      failures=$((failures + 1))
    fi
  elif [[ "$POST_CHECK" -eq 1 ]]; then
    record_gate "rollback_run" "manual" "not run; pass --run-rollback during --post-check"
  fi

  if [[ "$failures" -eq 0 ]]; then
    if [[ "$POST_CHECK" -eq 1 ]]; then
      if [[ "$EXECUTE_WRITE" -eq 1 ]]; then
        record "packet_write_execution" "ok" "executor completed; post-check passed"
      else
        record "packet_write_execution" "manual" "post-check only; write agent execution is intentionally disabled"
      fi
    elif [[ "$EXECUTE_WRITE" -eq 1 ]]; then
      record "packet_write_execution" "planned" "pre-gate passed; executor pending"
    else
      record "packet_write_execution" "manual" "gate-only; write agent execution is intentionally disabled"
    fi
    return 0
  fi

  record "packet_write_execution" "fail" "gate_failures=$failures"
  return 1
}

execute_write_packet() {
  local root

  POST_CHECK=0
  if ! validate_write_packet; then
    return 1
  fi

  root="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$root" ]]; then
    record_gate "executor_root" "fail" "target is not inside a git repository: $TARGET_DIR"
    return 1
  fi

  if ! run_packet_executor "$root"; then
    record "packet_write_execution" "fail" "executor failed"
    return 1
  fi

  POST_CHECK=1
  validate_write_packet
}

build_prompt() {
  local role="$1"
  printf '%s\n\nRole: %s\nWorkspace: %s\nRequired output: one concise line.' "$PROMPT" "$role" "$TARGET_DIR"
}

role_command() {
  local role="$1"
  local role_prompt
  role_prompt="$(build_prompt "$role")"
  case "$role" in
    codex)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=0
      ROLE_PARSE_LMSTUDIO=0
      ROLE_CMD=(codex exec --ephemeral --skip-git-repo-check --sandbox read-only -c 'approval_policy="never"' --cd "$TARGET_DIR" "$role_prompt")
      ;;
    claude)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=0
      ROLE_PARSE_LMSTUDIO=0
      ROLE_CMD=(claude -p "$role_prompt" --permission-mode plan --allowedTools Read Glob Grep --no-session-persistence)
      ;;
    cursor)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=0
      ROLE_PARSE_LMSTUDIO=0
      ROLE_CMD=(cursor-agent --print --mode ask --trust --sandbox enabled --workspace "$TARGET_DIR" "$role_prompt")
      ;;
    antigravity|agy)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=1
      ROLE_PARSE_LMSTUDIO=0
      ROLE_CMD=(agy --prompt "$role_prompt" --print-timeout "${TIMEOUT_SECONDS}s" --sandbox --add-dir "$TARGET_DIR")
      ;;
    opencode)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=1
      ROLE_PARSE_LMSTUDIO=0
      ROLE_CMD=(opencode run --pure --dir "$TARGET_DIR" --agent compaction --model opencode/north-mini-code-free "$role_prompt")
      ;;
    lmstudio)
      ROLE_WORKDIR="$TARGET_DIR"
      ROLE_ADVISORY=1
      ROLE_PARSE_LMSTUDIO=1
      ROLE_CMD=(lms status)
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

run_role() {
  local role="$1"
  ROLE_CMD=()
  ROLE_WORKDIR="$TARGET_DIR"
  ROLE_ADVISORY=0
  ROLE_PARSE_LMSTUDIO=0

  if ! role_command "$role"; then
    record "$role" "fail" "unsupported role"
    return 1
  fi

  local rendered
  rendered="$(quote_cmd "${ROLE_CMD[@]}")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    record "$role" "planned" "cd $(printf '%q' "$ROLE_WORKDIR") && $rendered"
    return 0
  fi

  local outfile="${OUTPUT_DIR}/${role}.out"
  local rc pid start now elapsed snippet status
  (
    cd "$ROLE_WORKDIR" || exit 97
    "${ROLE_CMD[@]}"
  ) > "$outfile" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
      terminate_process_tree "$pid"
      wait "$pid" 2>/dev/null || true
      sanitize_role_output "$outfile"
      snippet="$(sed -n '1,12p' "$outfile" 2>/dev/null | clean_detail)"
      if [[ "$ROLE_ADVISORY" -eq 1 ]]; then
        record "$role" "warn" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
        return 0
      fi
      record "$role" "fail" "timeout=${TIMEOUT_SECONDS}s :: $snippet"
      return 1
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  sanitize_role_output "$outfile"
  snippet="$(sed -n '1,12p' "$outfile" 2>/dev/null | clean_detail)"

  if [[ "$ROLE_PARSE_LMSTUDIO" -eq 1 && "$rc" -eq 0 ]]; then
    if grep -Eq 'Server:[[:space:]]+ON' "$outfile"; then
      record "$role" "ok" "$snippet"
    else
      record "$role" "warn" "$snippet"
    fi
    return 0
  fi

  if [[ "$rc" -eq 0 ]]; then
    status="ok"
  elif [[ "$ROLE_ADVISORY" -eq 1 ]]; then
    status="warn"
  else
    status="fail"
  fi

  record "$role" "$status" "rc=$rc :: $snippet"
  [[ "$status" != "fail" ]]
}

role_count() {
  local count=0 raw_role role
  IFS=',' read -r -a role_count_items <<< "$ROLES"
  for raw_role in "${role_count_items[@]}"; do
    role="$(printf '%s' "$raw_role" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "$role" ]] && count=$((count + 1))
  done
  printf '%s\n' "$count"
}

check_fanout_gate() {
  local count gate_script gate_out rc snippet
  count="$(role_count)"
  if [[ "$DRY_RUN" -eq 1 || "$PACKET_WRITE" -eq 1 || "$SKIP_FANOUT_GATE" -eq 1 || "$count" -le 1 ]]; then
    record "fanout_gate" "ok" "skipped dry_run=$DRY_RUN packet_write=$PACKET_WRITE skip=$SKIP_FANOUT_GATE role_count=$count"
    return 0
  fi

  gate_script="$FANOUT_GATE_SCRIPT"
  if [[ ! -f "$gate_script" ]]; then
    record "fanout_gate" "fail" "missing gate script: $gate_script"
    return 1
  fi

  gate_out="${OUTPUT_DIR}/fanout-readiness.md"
  python3 "$gate_script" --format md --block-on-high-findings --target-fanout "$count" > "$gate_out" 2>&1
  rc=$?
  snippet="$(sed -n '1,24p' "$gate_out" 2>/dev/null | tr '\n' ' ' | clean_detail)"
  if [[ "$rc" -eq 0 ]]; then
    record "fanout_gate" "ok" "role_count=$count :: $snippet"
    return 0
  fi
  record "fanout_gate" "fail" "role_count=$count rc=$rc :: $snippet"
  record "fanout_gate.next" "manual" "rerun after cleanup or pass --skip-fanout-gate after fresh manual review"
  return 1
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$OUTPUT_DIR"
  {
    printf '# CLI Dev Team Dispatch\n'
    printf 'generated_at\tok\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'target\tok\t%s\n' "$TARGET_DIR"
    printf 'roles\tok\t%s\n' "$ROLES"
    printf 'timeout_seconds\tok\t%s\n' "$TIMEOUT_SECONDS"
    if [[ -n "$PACKET" ]]; then
      printf 'packet\tok\t%s\n' "$PACKET"
      printf 'packet_id\tok\t%s\n' "${PACKET_ID:-none}"
      printf 'packet_mode\tok\t%s\n' "$PACKET_MODE"
      printf 'packet_files_owned\tok\t%s\n' "$PACKET_FILES_OWNED"
      printf 'packet_verifier\tok\t%s\n' "${PACKET_VERIFIER:-none}"
      printf 'packet_executor\tok\t%s\n' "${PACKET_EXECUTOR:-none}"
    fi
  } > "$summary_file"
else
  printf '# CLI Dev Team Dispatch Dry Run\n'
  printf 'target\tok\t%s\n' "$TARGET_DIR"
  printf 'roles\tok\t%s\n' "$ROLES"
  if [[ -n "$PACKET" ]]; then
    printf 'packet\tok\t%s\n' "$PACKET"
    printf 'packet_id\tok\t%s\n' "${PACKET_ID:-none}"
    printf 'packet_mode\tok\t%s\n' "$PACKET_MODE"
    printf 'packet_files_owned\tok\t%s\n' "$PACKET_FILES_OWNED"
    printf 'packet_verifier\tok\t%s\n' "${PACKET_VERIFIER:-none}"
    printf 'packet_executor\tok\t%s\n' "${PACKET_EXECUTOR:-none}"
  fi
fi

if ! check_fanout_gate; then
  record "summary" "fail" "fanout_gate_failed output_dir=$OUTPUT_DIR failures=1"
  exit 2
fi

if [[ "$PACKET_WRITE" -eq 1 ]]; then
  if [[ "$EXECUTE_WRITE" -eq 1 ]]; then
    if execute_write_packet; then
      record "summary" "ok" "write_execute output_dir=$OUTPUT_DIR failures=0"
      exit 0
    fi
    record "summary" "fail" "write_execute output_dir=$OUTPUT_DIR failures=1"
    exit 2
  fi
  if validate_write_packet; then
    if [[ "$POST_CHECK" -eq 1 ]]; then
      record "summary" "ok" "write_post_check output_dir=$OUTPUT_DIR failures=0"
    else
      record "summary" "ok" "write_gate_only output_dir=$OUTPUT_DIR failures=0"
    fi
    exit 0
  fi
  if [[ "$POST_CHECK" -eq 1 ]]; then
    record "summary" "fail" "write_post_check output_dir=$OUTPUT_DIR failures=1"
  else
    record "summary" "fail" "write_gate_only output_dir=$OUTPUT_DIR failures=1"
  fi
  exit 2
fi

failures=0
IFS=',' read -r -a role_items <<< "$ROLES"
for raw_role in "${role_items[@]}"; do
  role="$(printf '%s' "$raw_role" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -z "$role" ]] && continue
  if ! run_role "$role"; then
    failures=$((failures + 1))
  fi
done

if [[ "$DRY_RUN" -eq 0 ]]; then
  record "summary" "ok" "output_dir=$OUTPUT_DIR failures=$failures"
else
  record "summary" "ok" "dry_run failures=$failures"
fi

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

exit 0
