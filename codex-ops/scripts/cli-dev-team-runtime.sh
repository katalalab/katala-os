#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="${SCRIPT_DIR}/cli-dev-team-doctor.sh"
DISPATCH="${SCRIPT_DIR}/cli-dev-team-dispatch.sh"
STATUS="${SCRIPT_DIR}/cli-dev-team-status.sh"
MONITOR="$HOME/work/docs/scripts/agent-loop-monitor.py"
WATCHDOG="$HOME/work/docs/scripts/agent-loop-watchdog.py"
SUPERVISOR="$HOME/work/docs/scripts/agent-loop-supervisor.py"
LOOP_BATCH="$HOME/work/docs/scripts/agent-loop-batch.py"
LEASED_LOOP_BATCH="$HOME/work/docs/scripts/agent-leased-loop-batch.py"
MANAGED_SERIAL_LOOP="$HOME/work/docs/scripts/agent-managed-serial-loop.py"
CYCLE="$HOME/work/docs/scripts/agent-loop-cycle.py"
READINESS="$HOME/work/docs/scripts/agent-loop-readiness-board.py"
CONTROLLED_DISPATCH="$HOME/work/docs/scripts/agent-controlled-dispatch-runner.py"
CLEANUP_TO_FANOUT="$HOME/work/docs/scripts/agent-cleanup-to-fanout-runner.py"
CLEANUP_FRESHNESS="$HOME/work/docs/scripts/agent-cleanup-freshness-guard.py"
CLEANUP_DECISION="$HOME/work/docs/scripts/agent-cleanup-approval-decision.py"
CLEANUP_REHEARSAL="$HOME/work/docs/scripts/agent-cleanup-parallel-rehearsal.py"
APPROVED_CLEANUP_RUNWAY="$HOME/work/docs/scripts/agent-approved-cleanup-runway.py"
APPROVED_WORKTREE_RUNWAY="$HOME/work/docs/scripts/agent-approved-worktree-runway.py"
POST_CLEANUP_PARALLEL="$HOME/work/docs/scripts/agent-post-cleanup-parallel-runner.py"
PARALLEL_QUEUE="$HOME/work/docs/scripts/agent-parallel-work-queue.py"
UNBLOCK_PLAN="$HOME/work/docs/scripts/agent-participant-unblock-plan.py"
PARTICIPANT_PROMOTION="$HOME/work/docs/scripts/agent-participant-promotion-runner.py"
PARALLEL_PLAN="$HOME/work/docs/scripts/agent-parallel-development-plan.py"
PARALLEL_PACKETS="$HOME/work/docs/scripts/agent-parallel-packet-manifest.py"
PARALLEL_WORKTREES="$HOME/work/docs/scripts/agent-parallel-worktree-plan.py"
PARALLEL_SLOTS="$HOME/work/docs/scripts/agent-parallel-slot-gate.py"
LEASES="$HOME/work/docs/scripts/agent-lane-lease-board.py"
LOOP_CONTROL="$HOME/work/docs/scripts/agent-loop-control-board.py"
GOAL_AUDIT="$HOME/work/docs/scripts/agent-loop-goal-audit.py"
REDACTOR="${SCRIPT_DIR}/cli-dev-team-redact.sh"
if [[ ! -f "$REDACTOR" ]]; then
  printf 'redactor\tfail\tnot found: %s\n' "$REDACTOR" >&2
  exit 2
fi
source "$REDACTOR"
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.bun/bin:$HOME/.lmstudio/bin:/Applications/Codex.app/Contents/Resources:${PATH}:/opt/homebrew/bin:/usr/local/bin"

COMMAND="status"
TARGET_DIR="${PWD}"
TARGET_SET=0
RUNTIME_DIR="${PARALLEL_AI_RUNTIME_DIR:-$HOME/.local/state/parallel-ai-runtime}"
SOCKET="${PARALLEL_AI_TMUX_SOCKET:-${RUNTIME_DIR}/tmux.sock}"
SESSION="${PARALLEL_AI_TMUX_SESSION:-cli-dev-team}"
ROLES="codex,claude,cursor,antigravity,opencode,lmstudio"
ROLES_SET=0
PROMPT=""
PROMPT_SET=0
APPROVAL_TEXT=""
TIMEOUT_SECONDS=180
TIMEOUT_SET=0
STRICT=0
FORCE=0
REPAIR_STALE_SOCKET=0
PACKET=""
ALLOW_WRITE=0
EXECUTE_WRITE=0
EXECUTE_READONLY=0
EXECUTE_APPROVED_CLEANUP=0
EXECUTE_WORKTREE_CREATE=0
OUTPUT=""
POST_CHECK=0
RUN_VERIFIER=0
RUN_SECOND_REVIEW=0
RUN_ROLLBACK=0
OUTPUT_DIR=""
WORKTREE_ROOT=""
PARTICIPANT_BOARD=""
NO_WRITE=0
SELF_TEST_SUMMARY_FILE=""
LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"
LMSTUDIO_BIND="${LMSTUDIO_BIND:-127.0.0.1}"
LMSTUDIO_MODEL="${LMSTUDIO_MODEL:-nvidia/nemotron-3-nano-4b}"
LMSTUDIO_IDENTIFIER="${LMSTUDIO_IDENTIFIER:-cli-dev-team-local}"
LMSTUDIO_CONTEXT_LENGTH="${LMSTUDIO_CONTEXT_LENGTH:-4096}"
LMSTUDIO_TTL="${LMSTUDIO_TTL:-3600}"
WATCHDOG_SAMPLES=5
WATCHDOG_INTERVAL=5
LOOP_CYCLES=1
LEASE_ID=""
LEASE_PREFIX=""
LEASE_TTL_SECONDS=1800
MAX_BATCHES=1
STOP_FILE=""
TARGET_SLOTS=3
MAX_CONCURRENCY=3

usage() {
  cat <<'EOF'
Usage: cli-dev-team-runtime.sh [command] [options]

On-demand runtime wrapper for the local CLI development team. It manages a
dedicated tmux socket/session and delegates readiness checks or smoke dispatches
to the sibling doctor/dispatcher scripts. It does not install launchd jobs,
log in, edit CLI config, or run destructive cleanup. Only lmstudio-start and
ensure start the localhost LM Studio lane.

Commands:
  status      Report the runtime tmux socket/session state. Default.
  ensure      Start/check tmux, start/check localhost LM Studio, then emit
              readiness summary. No launchd or login changes.
  self-test   Run ensure, all-role read-only dispatch, and a temp-fixture
              write executor rollback check. No target repo writes.
  start       Start the dedicated tmux runtime if it is not already running.
  stop        Stop the dedicated tmux session. Requires --force.
  doctor      Run cli-dev-team-doctor.sh with this runtime socket.
  dispatch    Run cli-dev-team-dispatch.sh with this runtime socket.
  lmstudio-status
              Report LM Studio server/model/API state.
  lmstudio-start
              Start localhost LM Studio server and load the low-load model.
  lmstudio-stop
              Unload the low-load model and stop LM Studio server. Requires --force.
  team-status Generate machine-readable readiness JSON.
  monitor     Report read-only process/tmux loop monitor JSON. No cleanup.
  watchdog    Sample the read-only loop monitor repeatedly and write a receipt.
  supervisor  Refresh watchdog, cleanup dry-run, readiness, participant, queue,
              and final monitor receipts in order. No cleanup or dispatch.
  loop-batch  Run finite supervised repo/dev/verify cycles with supervisor
              before/after each cycle. No cleanup or repo writes.
  leased-loop-batch
              Run loop-batch under an explicit lane lease, then release it and
              verify post-release leases plus final monitor.
  managed-serial-loop
              Run foreground leased-loop batches serially with final monitor
              and lease checks. Supports stop-file natural shutdown.
  cycle       Run one monitored read-only repo/dev/verify loop cycle.
  readiness   Build the read-only loop/fanout/cleanup readiness board.
  controlled-dispatch
              Run gated one-agent then three-agent dispatch receipt.
  cleanup-to-fanout
              After approved cleanup receipt, run postcheck, readiness, and
              gated dispatch. Refuses before cleanup execution.
  cleanup-freshness
              Verify cleanup dry-run fingerprint, monitor, and lease board are
              fresh before using approval. No cleanup execution.
  cleanup-decision
              Build the read-only operator decision packet for approval-gated
              cleanup from cleanup freshness and goal audit evidence.
  cleanup-rehearsal
              Rehearse cleanup-to-parallel sequence without cleanup execution;
              verifies decision and refusal gates plus final monitor/leases.
  approved-cleanup-runway
              Run freshness, exact-approval cleanup executor, post-cleanup
              parallel runway, final monitor, and final leases. Cleanup only
              executes with --execute-approved-cleanup plus exact --approval-text.
  approved-worktree-runway
              Run worktree plan, exact-approval worktree/branch creation,
              post-create checks, final monitor, and final leases. Worktrees
              only execute with --execute-worktree-create plus exact --approval-text.
  post-cleanup-parallel
              After executed cleanup receipt, run postcheck, readiness,
              participant refresh, slot gate, leased read-only queue, and final checks.
  parallel-queue
              Gate a bounded parallel work queue before dispatch. Refuses when
              participant readiness, monitor, ownership, or fanout gates fail.
  unblock-plan
              Create a read-only operator unblock plan for blocked participants.
  participant-promotion
              Probe operator-unblocked Claude/Cursor/Antigravity, run one-role
              canaries, refresh participant board, then verify monitor/leases.
  parallel-plan
              Create a read-only serial/advisory/parallel promotion plan from
              the latest supervisor, queue, unblock, and cleanup receipts.
  parallel-packets
              Validate and materialize bounded development packet manifests.
              Writes packet JSON and commands only; no dispatch or repo writes.
  parallel-worktrees
              Plan isolated git worktree lanes and retargeted packet JSON.
              Writes evidence only; does not create worktrees or branches.
  parallel-slots
              Plan bounded execution slots and lease IDs from live monitor,
              lease board, participant readiness, and fan-out gate.
  leases      Report lane leases and compare them with live loop processes.
              Board mode is read-only; use the script directly for acquire/release.
  loop-control
              Build one read-only control board from live monitor, leases, and
              latest loop/cleanup/participant/parallel receipts.
  goal-audit  Audit the full user objective against live control evidence.
              Read-only; no cleanup, dispatch, process signal, branch, or worktree creation.

Options:
  --target PATH        Workspace path. Defaults to current directory.
  --packet FILE       JSON task packet passed to dispatch.
  --output FILE       JSON output path for team-status.
  --output-dir PATH   Evidence output directory for dispatch.
  --allow-write       Pass write-packet gate enablement to dispatch.
  --execute-write     Run packet executor.command via dispatch after write gates.
  --execute-readonly  For parallel-queue only: run read-only packets after all
                      queue gates pass. Does not run write packet executors.
  --post-check        Pass write result diff-scope validation to dispatch.
  --run-verifier      Run packet verifier during post-check.
  --run-second-review Run packet second_review.command during post-check.
  --run-rollback      Run packet rollback.command during post-check.
  --lmstudio-model MODEL
                      Model key for lmstudio-start. Defaults to nvidia/nemotron-3-nano-4b.
  --lmstudio-id ID    Loaded model identifier. Defaults to cli-dev-team-local.
  --lmstudio-port N   Local server port. Defaults to 1234.
  --lmstudio-bind IP  Bind address. Defaults to 127.0.0.1.
  --lmstudio-ttl SEC  Model unload TTL. Defaults to 3600.
  --lmstudio-context N
                      Context length for model load. Defaults to 4096.
  --watchdog-samples N
                      Sample count for watchdog. Defaults to 5.
  --watchdog-interval SEC
                      Seconds between watchdog samples. Defaults to 5.
  --cycles N         Cycle count for loop-batch. Defaults to 1.
  --lease-id ID      Optional lease ID for leased-loop-batch.
  --lease-prefix ID  Optional lease ID prefix for managed-serial-loop.
  --lease-ttl-seconds SEC
                      Lease TTL for leased-loop-batch and parallel-queue task leases.
                      Defaults to 1800.
  --max-batches N    Batch count for managed-serial-loop. Defaults to 1.
  --stop-file PATH   Stop-file path for managed-serial-loop natural shutdown.
  --target-slots N   Desired slots for parallel-slots. Defaults to 3.
  --max-concurrency N
                      Maximum concurrent read-only dispatches for parallel-queue. Defaults to 3.
  --worktree-root PATH
                      Root directory for parallel-worktrees lane plans.
  --participant-board PATH
                      Participant readiness board for unblock-plan, parallel-slots,
                      or parallel-queue when a specific board must be used.
  --no-write         For loop-control and leases: do not write evidence files.
  --socket PATH        tmux socket path. Defaults to $PARALLEL_AI_TMUX_SOCKET
                       or ~/.local/state/parallel-ai-runtime/tmux.sock.
  --session NAME       tmux session name. Defaults to cli-dev-team.
  --roles CSV         Roles for dispatch. Defaults to codex,claude,cursor,antigravity,opencode,lmstudio.
  --prompt TEXT       Prompt passed to dispatch. Defaults to dispatcher prompt.
  --approval-text TEXT
                      Exact approval text for approved cleanup/worktree runways.
  --timeout SECONDS   Per-role timeout for dispatch. Defaults to 180.
  --strict            Pass strict mode to doctor.
  --force             Required for stop.
  --execute-approved-cleanup
                      For approved-cleanup-runway only: allow cleanup executor
                      after freshness and exact approval-text gates pass.
  --execute-worktree-create
                      For approved-worktree-runway only: allow planned
                      worktree/branch creation after exact approval-text gate.
  --repair-stale-socket
                      For start only: move an unreachable socket aside first.
                      Backup retention is keep newest 5 stale socket backups.
  -h, --help          Show this help.
EOF
}

capture() {
  "$@" 2>&1
}

record() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  printf '%s\t%s\t%s\n' "$name" "$status" "$detail"
}

record_self_test() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  record "$name" "$status" "$detail"
  if [[ -n "$SELF_TEST_SUMMARY_FILE" ]]; then
    printf '%s\t%s\t%s\n' "$name" "$status" "$detail" >> "$SELF_TEST_SUMMARY_FILE"
  fi
}

tmux_has_session() {
  tmux -S "$SOCKET" has-session -t "$SESSION" >/dev/null 2>&1
}

tmux_status() {
  local out rc panes windows
  record "runtime.socket" "$(if [[ -S "$SOCKET" ]]; then printf ok; else printf warn; fi)" "$SOCKET"

  if [[ ! -S "$SOCKET" ]]; then
    record "runtime.session" "warn" "missing socket; run start"
    return 0
  fi

  out="$(capture tmux -S "$SOCKET" list-windows -t "$SESSION" -F '#{session_name}:#{window_index}:#{window_name} panes=#{window_panes}')"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "runtime.session" "warn" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 0
  fi

  windows="$(printf '%s\n' "$out" | awk 'NF {count++} END {print count+0}')"
  panes="$(printf '%s\n' "$out" | awk -F'panes=' 'NF > 1 {sum += $2} END {print sum+0}')"
  record "runtime.session" "ok" "session=$SESSION windows=$windows panes=$panes"
  printf '%s\n' "$out" | sed 's/^/runtime.window\tok\t/'
}

lmstudio_status() {
  local out rc api_out api_rc chat_out chat_rc content
  if ! command -v lms >/dev/null 2>&1; then
    record "lmstudio.version" "fail" "lms not found"
    return 1
  fi

  out="$(capture lms status)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record "lmstudio.status" "ok" "$(printf '%s' "$out" | clean_detail)"
  else
    record "lmstudio.status" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi

  out="$(capture lms ps)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    if printf '%s\n' "$out" | grep -Fq "$LMSTUDIO_IDENTIFIER"; then
      record "lmstudio.model" "ok" "$LMSTUDIO_IDENTIFIER loaded"
    else
      record "lmstudio.model" "warn" "$(printf '%s' "$out" | clean_detail)"
    fi
  else
    record "lmstudio.model" "warn" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
  fi

  if command -v curl >/dev/null 2>&1; then
    api_out="$(capture curl -fsS --max-time 2 "http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}/v1/models")"
    api_rc=$?
    if [[ "$api_rc" -eq 0 ]]; then
      record "lmstudio.api" "ok" "http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}/v1/models reachable"
    else
      record "lmstudio.api" "warn" "rc=$api_rc :: $(printf '%s' "$api_out" | clean_detail)"
    fi

    if printf '%s\n' "$api_out" | grep -Fq "$LMSTUDIO_IDENTIFIER"; then
      chat_out="$(capture curl -fsS --max-time 60 "http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}/v1/chat/completions" -H 'Content-Type: application/json' -d "{\"model\":\"${LMSTUDIO_IDENTIFIER}\",\"messages\":[{\"role\":\"user\",\"content\":\"Return one word: READY\"}],\"temperature\":0,\"max_tokens\":96}")"
      chat_rc=$?
      if [[ "$chat_rc" -eq 0 ]]; then
        content="$(printf '%s' "$chat_out" | jq -r '.choices[0].message.content // empty' 2>/dev/null | clean_detail)"
        if printf '%s' "$content" | grep -Fq "READY"; then
          record "lmstudio.chat" "ok" "$LMSTUDIO_IDENTIFIER returned READY"
        else
          record "lmstudio.chat" "warn" "unexpected content=$(printf '%s' "$content" | clean_detail)"
        fi
      else
        record "lmstudio.chat" "warn" "rc=$chat_rc :: $(printf '%s' "$chat_out" | clean_detail)"
      fi
    fi
  else
    record "lmstudio.api" "warn" "curl not found"
  fi
}

lmstudio_start() {
  local out rc estimate
  if ! command -v lms >/dev/null 2>&1; then
    record "lmstudio.start" "fail" "lms not found"
    return 1
  fi

  out="$(capture lms server start --port "$LMSTUDIO_PORT" --bind "$LMSTUDIO_BIND")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "lmstudio.server_start" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi
  record "lmstudio.server_start" "ok" "$(printf '%s' "$out" | clean_detail)"

  if lms ps 2>/dev/null | grep -Fq "$LMSTUDIO_IDENTIFIER"; then
    record "lmstudio.load" "ok" "$LMSTUDIO_IDENTIFIER already loaded"
    lmstudio_status
    return 0
  fi

  estimate="$(capture lms load "$LMSTUDIO_MODEL" --context-length "$LMSTUDIO_CONTEXT_LENGTH" --ttl "$LMSTUDIO_TTL" --identifier "$LMSTUDIO_IDENTIFIER" --estimate-only)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record "lmstudio.estimate" "ok" "$(printf '%s' "$estimate" | clean_detail)"
  else
    record "lmstudio.estimate" "warn" "rc=$rc :: $(printf '%s' "$estimate" | clean_detail)"
  fi

  out="$(capture lms load "$LMSTUDIO_MODEL" --context-length "$LMSTUDIO_CONTEXT_LENGTH" --ttl "$LMSTUDIO_TTL" --identifier "$LMSTUDIO_IDENTIFIER" -y)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "lmstudio.load" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi
  record "lmstudio.load" "ok" "$(printf '%s' "$out" | clean_detail)"
  lmstudio_status
}

lmstudio_stop() {
  local out rc
  if [[ "$FORCE" -ne 1 ]]; then
    record "lmstudio.stop" "manual" "requires --force; rollback command: lms unload $LMSTUDIO_IDENTIFIER && lms server stop"
    return 2
  fi

  out="$(capture lms unload "$LMSTUDIO_IDENTIFIER")"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record "lmstudio.unload" "ok" "$(printf '%s' "$out" | clean_detail)"
  else
    record "lmstudio.unload" "warn" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
  fi

  out="$(capture lms server stop)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "lmstudio.server_stop" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi
  record "lmstudio.server_stop" "ok" "$(printf '%s' "$out" | clean_detail)"
}

backup_stale_socket() {
  local backup_dir backup_path base pruned old
  backup_dir="${RUNTIME_DIR}/stale-socket-backups"
  base="$(basename "$SOCKET")"
  backup_path="${backup_dir}/${base}.stale.$(date '+%Y%m%dT%H%M%SJST')"
  pruned=0

  mkdir -p "$backup_dir"
  record "runtime.backup" "manual" "restore: mv $(printf '%q' "$backup_path") $(printf '%q' "$SOCKET")"
  record "runtime.backup_retention" "ok" "keep_newest=5 in $backup_dir"

  if ! mv "$SOCKET" "$backup_path"; then
    record "runtime.backup" "fail" "could not move stale socket to $backup_path"
    return 1
  fi
  record "runtime.backup" "ok" "moved stale socket to $backup_path"

  while IFS= read -r old; do
    [[ -z "$old" ]] && continue
    rm -f "$old" && pruned=$((pruned + 1))
  done < <(find "$backup_dir" -maxdepth 1 -name "${base}.stale.*" -type s -print 2>/dev/null | LC_ALL=C sort -r | sed -n '6,$p')
  record "runtime.backup_prune" "ok" "pruned=$pruned keep_newest=5"
}

start_runtime() {
  local out rc first_window
  if ! command -v tmux >/dev/null 2>&1; then
    record "runtime.start" "fail" "tmux not found"
    return 1
  fi
  if [[ ! -d "$TARGET_DIR" ]]; then
    record "runtime.start" "fail" "target not a directory: $TARGET_DIR"
    return 1
  fi

  mkdir -p "$(dirname "$SOCKET")"

  if [[ -S "$SOCKET" ]]; then
    if tmux_has_session; then
      record "runtime.start" "ok" "already running"
      tmux_status
      return 0
    fi
    if [[ "$REPAIR_STALE_SOCKET" -eq 1 ]]; then
      backup_stale_socket || return 1
    else
      record "runtime.start" "fail" "socket exists but session is unavailable; rerun start with --repair-stale-socket after inspection: $SOCKET"
      return 1
    fi
  fi

  if [[ -e "$SOCKET" ]]; then
    record "runtime.start" "fail" "socket exists but session is unavailable; inspect before removing: $SOCKET"
    return 1
  fi

  out="$(capture tmux -S "$SOCKET" new-session -d -s "$SESSION" -c "$TARGET_DIR")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "runtime.start" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi

  first_window="$(tmux -S "$SOCKET" list-windows -t "$SESSION" -F '#{window_index}' 2>/dev/null | sed -n '1p')"
  if [[ -n "$first_window" ]]; then
    tmux -S "$SOCKET" rename-window -t "${SESSION}:${first_window}" control >/dev/null 2>&1 || true
  fi
  tmux -S "$SOCKET" new-window -d -t "$SESSION" -n evidence -c "$TARGET_DIR" >/dev/null 2>&1 || true
  tmux -S "$SOCKET" set-option -t "$SESSION" status-left '[cli-dev-team] ' >/dev/null 2>&1 || true

  record "runtime.start" "ok" "socket=$SOCKET session=$SESSION target=$TARGET_DIR"
  tmux_status
}

stop_runtime() {
  local out rc
  if [[ "$FORCE" -ne 1 ]]; then
    record "runtime.stop" "manual" "requires --force; this only kills session=$SESSION on socket=$SOCKET"
    return 2
  fi
  if [[ ! -S "$SOCKET" ]]; then
    record "runtime.stop" "ok" "socket already absent: $SOCKET"
    return 0
  fi
  out="$(capture tmux -S "$SOCKET" kill-session -t "$SESSION")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record "runtime.stop" "fail" "rc=$rc :: $(printf '%s' "$out" | clean_detail)"
    return 1
  fi
  record "runtime.stop" "ok" "stopped session=$SESSION"
}

ensure_runtime() {
  local failures=0 status_tmp status_args status_rc ready_summary

  record "ensure.phase" "ok" "start_runtime"
  if ! start_runtime; then
    failures=$((failures + 1))
  fi

  record "ensure.phase" "ok" "lmstudio_start"
  if ! lmstudio_start; then
    failures=$((failures + 1))
  fi

  status_tmp="$(mktemp "${TMPDIR:-/tmp}/cli-dev-team-ensure-status.XXXXXX")"
  status_args=(--target "$TARGET_DIR" --require readonly --require-known-probes)
  if [[ -n "$OUTPUT" ]]; then
    status_args+=(--output "$OUTPUT")
  fi

  PARALLEL_AI_TMUX_SOCKET="$SOCKET" LMSTUDIO_URL="http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}" "$STATUS" "${status_args[@]}" > "$status_tmp"
  status_rc=$?
  if [[ "$status_rc" -ne 0 ]]; then
    record "ensure.team_status" "fail" "rc=$status_rc"
    failures=$((failures + 1))
  elif command -v jq >/dev/null 2>&1; then
    ready_summary="$(jq -r '"core=\(.ready.core) readonly=\(.ready.readonly) write=\(.ready.write) full=\(.ready.full)"' "$status_tmp" 2>/dev/null || true)"
    record "ensure.team_status" "ok" "${ready_summary:-status_json_parsed=false}"
  else
    record "ensure.team_status" "ok" "status generated; jq not found for summary"
  fi

  rm -f "$status_tmp"

  if [[ "$failures" -eq 0 ]]; then
    record "ensure.summary" "ok" "target=$TARGET_DIR socket=$SOCKET lmstudio=http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}"
    return 0
  fi
  record "ensure.summary" "fail" "failures=$failures"
  return 1
}

create_self_test_fixture() {
  local fixture tree commit status_out
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/cli-dev-team-self-test-fixture.XXXXXX")"
  mkdir -p "${fixture}/src"
  printf 'baseline\n' > "${fixture}/src/example.txt"

  git -C "$fixture" init -b main >/dev/null 2>&1 || return 1
  git -C "$fixture" add src/example.txt >/dev/null 2>&1 || return 1
  tree="$(git -C "$fixture" write-tree 2>/dev/null)" || return 1
  commit="$(GIT_AUTHOR_NAME=CodexFixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=CodexFixture GIT_COMMITTER_EMAIL=fixture@example.invalid git -C "$fixture" commit-tree "$tree" -m fixture-baseline 2>/dev/null)" || return 1
  git -C "$fixture" update-ref refs/heads/main "$commit" >/dev/null 2>&1 || return 1
  git -C "$fixture" reset --hard HEAD >/dev/null 2>&1 || return 1

  status_out="$(git -C "$fixture" status --short 2>/dev/null || true)"
  if [[ -n "$status_out" ]]; then
    return 1
  fi
  printf '%s\n' "$fixture"
}

write_self_test_packet() {
  local packet="$1"
  local fixture="$2"
  jq -n \
    --arg target "$fixture" \
    '{
      id: "self-test-write-execute",
      mode: "write",
      target: $target,
      roles: ["codex"],
      timeout_seconds: 30,
      files_owned: ["src/example.txt"],
      executor: {
        command: "printf '\''baseline\\nowned-change\\n'\'' > src/example.txt"
      },
      second_review: {
        required: true,
        role: "risk_reviewer",
        command: "test \"$(git diff --name-only --relative | tr '\''\\n'\'' '\'' '\'')\" = \"src/example.txt \""
      },
      verifier: {
        command: "grep -q '\''owned-change'\'' src/example.txt"
      },
      rollback: {
        command: "git checkout -- src/example.txt"
      },
      prompt: "Self-test write executor packet. Dispatcher must pre-gate, execute owned file change, verify, second-review, rollback, and leave fixture clean."
    }' > "$packet"
}

self_test_runtime() {
  local failures=0 self_dir readonly_dir write_dir fixture packet status_out

  if [[ -n "$OUTPUT_DIR" ]]; then
    self_dir="$OUTPUT_DIR"
  else
    self_dir="$HOME/work/docs/agent-team-design/evidence/self-test-$(date '+%Y%m%dT%H%M%SJST')"
  fi
  readonly_dir="${self_dir}/readonly"
  write_dir="${self_dir}/write-execute-rollback"
  mkdir -p "$self_dir"
  SELF_TEST_SUMMARY_FILE="${self_dir}/self-test-summary.tsv"
  {
    printf '# CLI Dev Team Self Test Summary\n'
    printf 'generated_at\tok\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'target\tok\t%s\n' "$TARGET_DIR"
    printf 'roles\tok\t%s\n' "$ROLES"
  } > "$SELF_TEST_SUMMARY_FILE"

  record_self_test "self_test.output_dir" "ok" "$self_dir"
  record_self_test "self_test.phase" "ok" "ensure"
  if ! ensure_runtime > "${self_dir}/ensure.tsv"; then
    record_self_test "self_test.ensure" "fail" "see ${self_dir}/ensure.tsv"
    failures=$((failures + 1))
  else
    record_self_test "self_test.ensure" "ok" "see ${self_dir}/ensure.tsv"
  fi

  record_self_test "self_test.phase" "ok" "readonly_dispatch"
  if PARALLEL_AI_TMUX_SOCKET="$SOCKET" "$DISPATCH" --target "$TARGET_DIR" --roles "$ROLES" --timeout "$TIMEOUT_SECONDS" --output-dir "$readonly_dir" > "${self_dir}/readonly.out" 2>&1; then
    record_self_test "self_test.readonly_dispatch" "ok" "summary=${readonly_dir}/summary.tsv"
  else
    record_self_test "self_test.readonly_dispatch" "fail" "summary=${readonly_dir}/summary.tsv"
    failures=$((failures + 1))
  fi

  record_self_test "self_test.phase" "ok" "write_fixture"
  fixture="$(create_self_test_fixture || true)"
  if [[ -z "$fixture" ]]; then
    record_self_test "self_test.fixture" "fail" "could not create clean git fixture"
    failures=$((failures + 1))
  else
    record_self_test "self_test.fixture" "ok" "$fixture"
    record_self_test "self_test.fixture_retention" "manual" "temporary fixture; remove when no longer needed: rm -rf $(printf '%q' "$fixture")"
    packet="${self_dir}/write-execute.packet.json"
    if ! write_self_test_packet "$packet" "$fixture"; then
      record_self_test "self_test.packet" "fail" "could not write $packet"
      failures=$((failures + 1))
    else
      record_self_test "self_test.packet" "ok" "$packet"
      if PARALLEL_AI_TMUX_SOCKET="$SOCKET" "$DISPATCH" --packet "$packet" --allow-write --execute-write --run-verifier --run-second-review --run-rollback --output-dir "$write_dir" > "${self_dir}/write-execute-rollback.out" 2>&1; then
        status_out="$(git -C "$fixture" status --short 2>/dev/null || true)"
        if [[ -z "$status_out" ]]; then
          record_self_test "self_test.write_execute_rollback" "ok" "summary=${write_dir}/summary.tsv fixture_clean=true"
        else
          record_self_test "self_test.write_execute_rollback" "fail" "fixture dirty after rollback: $(printf '%s' "$status_out" | clean_detail)"
          failures=$((failures + 1))
        fi
      else
        record_self_test "self_test.write_execute_rollback" "fail" "summary=${write_dir}/summary.tsv"
        failures=$((failures + 1))
      fi
    fi
  fi

  if [[ "$failures" -eq 0 ]]; then
    record_self_test "self_test.summary" "ok" "output_dir=$self_dir failures=0"
    return 0
  fi
  record_self_test "self_test.summary" "fail" "output_dir=$self_dir failures=$failures"
  return 1
}

if [[ $# -gt 0 && "$1" != --* ]]; then
  COMMAND="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--target requires a path" >&2
        exit 2
      fi
      TARGET_DIR="$2"
      TARGET_SET=1
      shift 2
      ;;
    --packet)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--packet requires a path" >&2
        exit 2
      fi
      PACKET="$2"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--output requires a path" >&2
        exit 2
      fi
      OUTPUT="$2"
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--output-dir requires a path" >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --worktree-root)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--worktree-root requires a path" >&2
        exit 2
      fi
      WORKTREE_ROOT="$2"
      shift 2
      ;;
    --participant-board)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--participant-board requires a path" >&2
        exit 2
      fi
      PARTICIPANT_BOARD="$2"
      shift 2
      ;;
    --no-write)
      NO_WRITE=1
      shift
      ;;
    --socket)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--socket requires a path" >&2
        exit 2
      fi
      SOCKET="$2"
      shift 2
      ;;
    --lmstudio-model)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-model requires a model key" >&2
        exit 2
      fi
      LMSTUDIO_MODEL="$2"
      shift 2
      ;;
    --lmstudio-id)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-id requires an identifier" >&2
        exit 2
      fi
      LMSTUDIO_IDENTIFIER="$2"
      shift 2
      ;;
    --lmstudio-port)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-port requires a port" >&2
        exit 2
      fi
      LMSTUDIO_PORT="$2"
      shift 2
      ;;
    --lmstudio-bind)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-bind requires an address" >&2
        exit 2
      fi
      LMSTUDIO_BIND="$2"
      shift 2
      ;;
    --lmstudio-ttl)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-ttl requires seconds" >&2
        exit 2
      fi
      LMSTUDIO_TTL="$2"
      shift 2
      ;;
    --lmstudio-context)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lmstudio-context requires a token count" >&2
        exit 2
      fi
      LMSTUDIO_CONTEXT_LENGTH="$2"
      shift 2
      ;;
    --watchdog-samples)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--watchdog-samples requires a count" >&2
        exit 2
      fi
      WATCHDOG_SAMPLES="$2"
      shift 2
      ;;
    --watchdog-interval)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--watchdog-interval requires seconds" >&2
        exit 2
      fi
      WATCHDOG_INTERVAL="$2"
      shift 2
      ;;
    --cycles)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--cycles requires a count" >&2
        exit 2
      fi
      LOOP_CYCLES="$2"
      shift 2
      ;;
    --lease-id)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lease-id requires an ID" >&2
        exit 2
      fi
      LEASE_ID="$2"
      shift 2
      ;;
    --lease-prefix)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lease-prefix requires an ID prefix" >&2
        exit 2
      fi
      LEASE_PREFIX="$2"
      shift 2
      ;;
    --lease-ttl-seconds)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--lease-ttl-seconds requires seconds" >&2
        exit 2
      fi
      LEASE_TTL_SECONDS="$2"
      shift 2
      ;;
    --max-batches)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--max-batches requires a count" >&2
        exit 2
      fi
      MAX_BATCHES="$2"
      shift 2
      ;;
    --stop-file)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--stop-file requires a path" >&2
        exit 2
      fi
      STOP_FILE="$2"
      shift 2
      ;;
    --target-slots)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--target-slots requires a count" >&2
        exit 2
      fi
      TARGET_SLOTS="$2"
      shift 2
      ;;
    --max-concurrency)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--max-concurrency requires a count" >&2
        exit 2
      fi
      MAX_CONCURRENCY="$2"
      shift 2
      ;;
    --session)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--session requires a name" >&2
        exit 2
      fi
      SESSION="$2"
      shift 2
      ;;
    --roles)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--roles requires a comma-separated value" >&2
        exit 2
      fi
      ROLES="$2"
      ROLES_SET=1
      shift 2
      ;;
    --prompt)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--prompt requires text" >&2
        exit 2
      fi
      PROMPT="$2"
      PROMPT_SET=1
      shift 2
      ;;
    --approval-text)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--approval-text requires text" >&2
        exit 2
      fi
      APPROVAL_TEXT="$2"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        record "arg" "fail" "--timeout requires seconds" >&2
        exit 2
      fi
      TIMEOUT_SECONDS="$2"
      TIMEOUT_SET=1
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --force)
      FORCE=1
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
    --execute-readonly)
      EXECUTE_READONLY=1
      shift
      ;;
    --execute-approved-cleanup)
      EXECUTE_APPROVED_CLEANUP=1
      shift
      ;;
    --execute-worktree-create)
      EXECUTE_WORKTREE_CREATE=1
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
    --repair-stale-socket)
      REPAIR_STALE_SOCKET=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      record "arg" "fail" "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  record "arg" "fail" "--timeout must be a positive integer" >&2
  exit 2
fi

if [[ ! "$WATCHDOG_SAMPLES" =~ ^[0-9]+$ || "$WATCHDOG_SAMPLES" -lt 1 ]]; then
  record "arg" "fail" "--watchdog-samples must be a positive integer" >&2
  exit 2
fi

if [[ ! "$WATCHDOG_INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  record "arg" "fail" "--watchdog-interval must be a non-negative number" >&2
  exit 2
fi

if [[ ! "$LOOP_CYCLES" =~ ^[0-9]+$ || "$LOOP_CYCLES" -lt 1 ]]; then
  record "arg" "fail" "--cycles must be a positive integer" >&2
  exit 2
fi

if [[ ! "$LEASE_TTL_SECONDS" =~ ^[0-9]+$ || "$LEASE_TTL_SECONDS" -lt 1 ]]; then
  record "arg" "fail" "--lease-ttl-seconds must be a positive integer" >&2
  exit 2
fi

if [[ ! "$MAX_BATCHES" =~ ^[0-9]+$ || "$MAX_BATCHES" -lt 1 ]]; then
  record "arg" "fail" "--max-batches must be a positive integer" >&2
  exit 2
fi

if [[ ! "$TARGET_SLOTS" =~ ^[0-9]+$ || "$TARGET_SLOTS" -lt 1 ]]; then
  record "arg" "fail" "--target-slots must be a positive integer" >&2
  exit 2
fi

if [[ ! "$MAX_CONCURRENCY" =~ ^[0-9]+$ || "$MAX_CONCURRENCY" -lt 1 ]]; then
  record "arg" "fail" "--max-concurrency must be a positive integer" >&2
  exit 2
fi

case "$COMMAND" in
  ensure)
    printf '# CLI Dev Team Ensure\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "target" "ok" "$TARGET_DIR"
    record "lmstudio.target" "ok" "model=$LMSTUDIO_MODEL id=$LMSTUDIO_IDENTIFIER bind=$LMSTUDIO_BIND port=$LMSTUDIO_PORT ttl=$LMSTUDIO_TTL"
    ensure_runtime
    ;;
  self-test)
    printf '# CLI Dev Team Self Test\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "target" "ok" "$TARGET_DIR"
    record "roles" "ok" "$ROLES"
    record "lmstudio.target" "ok" "model=$LMSTUDIO_MODEL id=$LMSTUDIO_IDENTIFIER bind=$LMSTUDIO_BIND port=$LMSTUDIO_PORT ttl=$LMSTUDIO_TTL"
    self_test_runtime
    ;;
  status)
    printf '# CLI Dev Team Runtime\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "target" "ok" "$TARGET_DIR"
    tmux_status
    ;;
  start)
    printf '# CLI Dev Team Runtime Start\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    start_runtime
    ;;
  stop)
    printf '# CLI Dev Team Runtime Stop\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    stop_runtime
    ;;
  doctor)
    if [[ "$STRICT" -eq 1 ]]; then
      PARALLEL_AI_TMUX_SOCKET="$SOCKET" "$DOCTOR" --strict --target "$TARGET_DIR"
    else
      PARALLEL_AI_TMUX_SOCKET="$SOCKET" "$DOCTOR" --target "$TARGET_DIR"
    fi
    ;;
  dispatch)
    dispatch_args=()
    if [[ -n "$PACKET" ]]; then
      dispatch_args+=(--packet "$PACKET")
    fi
    if [[ -z "$PACKET" || "$TARGET_SET" -eq 1 ]]; then
      dispatch_args+=(--target "$TARGET_DIR")
    fi
    if [[ -z "$PACKET" || "$ROLES_SET" -eq 1 ]]; then
      dispatch_args+=(--roles "$ROLES")
    fi
    if [[ "$PROMPT_SET" -eq 1 ]]; then
      dispatch_args+=(--prompt "$PROMPT")
    fi
    if [[ -z "$PACKET" || "$TIMEOUT_SET" -eq 1 ]]; then
      dispatch_args+=(--timeout "$TIMEOUT_SECONDS")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      dispatch_args+=(--output-dir "$OUTPUT_DIR")
    fi
    if [[ "$ALLOW_WRITE" -eq 1 ]]; then
      dispatch_args+=(--allow-write)
    fi
    if [[ "$EXECUTE_WRITE" -eq 1 ]]; then
      dispatch_args+=(--execute-write)
    fi
    if [[ "$POST_CHECK" -eq 1 ]]; then
      dispatch_args+=(--post-check)
    fi
    if [[ "$RUN_VERIFIER" -eq 1 ]]; then
      dispatch_args+=(--run-verifier)
    fi
    if [[ "$RUN_SECOND_REVIEW" -eq 1 ]]; then
      dispatch_args+=(--run-second-review)
    fi
    if [[ "$RUN_ROLLBACK" -eq 1 ]]; then
      dispatch_args+=(--run-rollback)
    fi
    PARALLEL_AI_TMUX_SOCKET="$SOCKET" "$DISPATCH" "${dispatch_args[@]}"
    ;;
  lmstudio-status)
    printf '# CLI Dev Team LM Studio Status\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "lmstudio.target" "ok" "model=$LMSTUDIO_MODEL id=$LMSTUDIO_IDENTIFIER bind=$LMSTUDIO_BIND port=$LMSTUDIO_PORT ttl=$LMSTUDIO_TTL"
    lmstudio_status
    ;;
  lmstudio-start)
    printf '# CLI Dev Team LM Studio Start\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "lmstudio.target" "ok" "model=$LMSTUDIO_MODEL id=$LMSTUDIO_IDENTIFIER bind=$LMSTUDIO_BIND port=$LMSTUDIO_PORT ttl=$LMSTUDIO_TTL"
    lmstudio_start
    ;;
  lmstudio-stop)
    printf '# CLI Dev Team LM Studio Stop\n'
    record "generated_at" "ok" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    record "lmstudio.target" "ok" "model=$LMSTUDIO_MODEL id=$LMSTUDIO_IDENTIFIER bind=$LMSTUDIO_BIND port=$LMSTUDIO_PORT ttl=$LMSTUDIO_TTL"
    lmstudio_stop
    ;;
  team-status)
    status_args=(--target "$TARGET_DIR")
    if [[ -n "$OUTPUT" ]]; then
      status_args+=(--output "$OUTPUT")
    fi
    PARALLEL_AI_TMUX_SOCKET="$SOCKET" LMSTUDIO_URL="http://${LMSTUDIO_BIND}:${LMSTUDIO_PORT}" "$STATUS" "${status_args[@]}"
    ;;
  monitor)
    monitor_args=(--socket "$SOCKET" --session "$SESSION" --format json)
    if [[ -n "$OUTPUT" ]]; then
      monitor_args+=(--output "$OUTPUT")
    fi
    python3 "$MONITOR" "${monitor_args[@]}"
    ;;
  watchdog)
    watchdog_args=(--socket "$SOCKET" --session "$SESSION" --samples "$WATCHDOG_SAMPLES" --interval "$WATCHDOG_INTERVAL" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      watchdog_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$WATCHDOG" "${watchdog_args[@]}"
    ;;
  supervisor)
    supervisor_args=(--target "$TARGET_DIR" --roles "$ROLES" --watchdog-samples "$WATCHDOG_SAMPLES" --watchdog-interval "$WATCHDOG_INTERVAL" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      supervisor_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$SUPERVISOR" "${supervisor_args[@]}"
    ;;
  loop-batch)
    batch_args=(--target "$TARGET_DIR" --roles "$ROLES" --cycles "$LOOP_CYCLES" --dispatch-timeout "$TIMEOUT_SECONDS" --watchdog-samples "$WATCHDOG_SAMPLES" --watchdog-interval "$WATCHDOG_INTERVAL" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      batch_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$LOOP_BATCH" "${batch_args[@]}"
    ;;
  leased-loop-batch)
    leased_batch_args=(--target "$TARGET_DIR" --roles "$ROLES" --cycles "$LOOP_CYCLES" --dispatch-timeout "$TIMEOUT_SECONDS" --lease-ttl-seconds "$LEASE_TTL_SECONDS" --watchdog-samples "$WATCHDOG_SAMPLES" --watchdog-interval "$WATCHDOG_INTERVAL" --format json)
    if [[ -n "$LEASE_ID" ]]; then
      leased_batch_args+=(--lease-id "$LEASE_ID")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      leased_batch_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$LEASED_LOOP_BATCH" "${leased_batch_args[@]}"
    ;;
  managed-serial-loop)
    managed_serial_args=(--target "$TARGET_DIR" --roles "$ROLES" --cycles "$LOOP_CYCLES" --max-batches "$MAX_BATCHES" --dispatch-timeout "$TIMEOUT_SECONDS" --lease-ttl-seconds "$LEASE_TTL_SECONDS" --watchdog-samples "$WATCHDOG_SAMPLES" --watchdog-interval "$WATCHDOG_INTERVAL" --format json)
    if [[ -n "$LEASE_PREFIX" ]]; then
      managed_serial_args+=(--lease-prefix "$LEASE_PREFIX")
    fi
    if [[ -n "$STOP_FILE" ]]; then
      managed_serial_args+=(--stop-file "$STOP_FILE")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      managed_serial_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$MANAGED_SERIAL_LOOP" "${managed_serial_args[@]}"
    ;;
  cycle)
    cycle_args=(--target "$TARGET_DIR" --roles "$ROLES" --dispatch-timeout "$TIMEOUT_SECONDS" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      cycle_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CYCLE" "${cycle_args[@]}"
    ;;
  readiness)
    readiness_args=(--target-fanout "$(printf '%s' "$ROLES" | awk -F',' '{print NF}')")
    if [[ -n "$OUTPUT_DIR" ]]; then
      readiness_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$READINESS" "${readiness_args[@]}"
    ;;
  controlled-dispatch)
    controlled_args=(--target "$TARGET_DIR" --one-roles codex --three-roles "$ROLES" --dispatch-timeout "$TIMEOUT_SECONDS")
    if [[ -n "$OUTPUT_DIR" ]]; then
      controlled_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CONTROLLED_DISPATCH" "${controlled_args[@]}"
    ;;
  cleanup-to-fanout)
    cleanup_fanout_args=(--target "$TARGET_DIR" --one-roles codex --three-roles "$ROLES" --dispatch-timeout "$TIMEOUT_SECONDS")
    if [[ -n "$OUTPUT_DIR" ]]; then
      cleanup_fanout_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CLEANUP_TO_FANOUT" "${cleanup_fanout_args[@]}"
    ;;
  cleanup-freshness)
    cleanup_freshness_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      cleanup_freshness_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CLEANUP_FRESHNESS" "${cleanup_freshness_args[@]}"
    ;;
  cleanup-decision)
    cleanup_decision_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      cleanup_decision_args+=(--packet "$PACKET")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      cleanup_decision_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CLEANUP_DECISION" "${cleanup_decision_args[@]}"
    ;;
  cleanup-rehearsal)
    cleanup_rehearsal_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      cleanup_rehearsal_args+=(--packet "$PACKET")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      cleanup_rehearsal_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$CLEANUP_REHEARSAL" "${cleanup_rehearsal_args[@]}"
    ;;
  approved-cleanup-runway)
    approved_cleanup_args=(--target "$TARGET_DIR" --target-slots "$TARGET_SLOTS" --max-concurrency "$MAX_CONCURRENCY" --cycles "$LOOP_CYCLES" --lease-ttl-seconds "$LEASE_TTL_SECONDS" --format json)
    if [[ -n "$PACKET" ]]; then
      approved_cleanup_args+=(--queue "$PACKET")
    fi
    if [[ -n "$APPROVAL_TEXT" ]]; then
      approved_cleanup_args+=(--approval-text "$APPROVAL_TEXT")
    fi
    if [[ "$EXECUTE_APPROVED_CLEANUP" -eq 1 ]]; then
      approved_cleanup_args+=(--execute-approved-cleanup)
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      approved_cleanup_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$APPROVED_CLEANUP_RUNWAY" "${approved_cleanup_args[@]}"
    ;;
  approved-worktree-runway)
    worktree_runway_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      worktree_runway_args+=(--manifest "$PACKET")
    fi
    if [[ -n "$WORKTREE_ROOT" ]]; then
      worktree_runway_args+=(--worktree-root "$WORKTREE_ROOT")
    fi
    if [[ -n "$APPROVAL_TEXT" ]]; then
      worktree_runway_args+=(--approval-text "$APPROVAL_TEXT")
    fi
    if [[ "$EXECUTE_WORKTREE_CREATE" -eq 1 ]]; then
      worktree_runway_args+=(--execute-worktree-create)
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      worktree_runway_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$APPROVED_WORKTREE_RUNWAY" "${worktree_runway_args[@]}"
    ;;
  post-cleanup-parallel)
    post_cleanup_parallel_args=(--target "$TARGET_DIR" --target-slots "$TARGET_SLOTS" --max-concurrency "$MAX_CONCURRENCY" --cycles "$LOOP_CYCLES" --lease-ttl-seconds "$LEASE_TTL_SECONDS" --format json)
    if [[ -n "$PACKET" ]]; then
      post_cleanup_parallel_args+=(--queue "$PACKET")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      post_cleanup_parallel_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$POST_CLEANUP_PARALLEL" "${post_cleanup_parallel_args[@]}"
    ;;
  parallel-queue)
    parallel_queue_args=(--target "$TARGET_DIR" --max-concurrency "$MAX_CONCURRENCY" --lease-ttl-seconds "$LEASE_TTL_SECONDS")
    if [[ -n "$PACKET" ]]; then
      parallel_queue_args+=(--queue "$PACKET")
    fi
    if [[ -n "$PARTICIPANT_BOARD" ]]; then
      parallel_queue_args+=(--participant-board "$PARTICIPANT_BOARD")
    fi
    if [[ "$ALLOW_WRITE" -eq 1 ]]; then
      parallel_queue_args+=(--allow-write)
    fi
    if [[ "$EXECUTE_READONLY" -eq 1 ]]; then
      parallel_queue_args+=(--execute-readonly)
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      parallel_queue_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARALLEL_QUEUE" "${parallel_queue_args[@]}"
    ;;
  unblock-plan)
    unblock_args=(--format json)
    if [[ -n "$PARTICIPANT_BOARD" ]]; then
      unblock_args+=(--participant-board "$PARTICIPANT_BOARD")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      unblock_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$UNBLOCK_PLAN" "${unblock_args[@]}"
    ;;
  participant-promotion)
    promotion_roles="$ROLES"
    if [[ "$ROLES_SET" -eq 0 ]]; then
      promotion_roles="claude,cursor,antigravity"
    fi
    participant_promotion_args=(--target "$TARGET_DIR" --roles "$promotion_roles" --dispatch-timeout "$TIMEOUT_SECONDS" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      participant_promotion_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARTICIPANT_PROMOTION" "${participant_promotion_args[@]}"
    ;;
  parallel-plan)
    parallel_plan_args=(--target "$TARGET_DIR" --roles "$ROLES" --format json)
    if [[ -n "$OUTPUT_DIR" ]]; then
      parallel_plan_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARALLEL_PLAN" "${parallel_plan_args[@]}"
    ;;
  parallel-packets)
    parallel_packets_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      parallel_packets_args+=(--manifest "$PACKET")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      parallel_packets_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARALLEL_PACKETS" "${parallel_packets_args[@]}"
    ;;
  parallel-worktrees)
    parallel_worktree_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      parallel_worktree_args+=(--manifest "$PACKET")
    fi
    if [[ -n "$WORKTREE_ROOT" ]]; then
      parallel_worktree_args+=(--worktree-root "$WORKTREE_ROOT")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      parallel_worktree_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARALLEL_WORKTREES" "${parallel_worktree_args[@]}"
    ;;
  parallel-slots)
    parallel_slots_args=(--target "$TARGET_DIR" --target-slots "$TARGET_SLOTS" --cycles "$LOOP_CYCLES" --lease-ttl-seconds "$LEASE_TTL_SECONDS" --format json)
    if [[ -n "$PACKET" ]]; then
      parallel_slots_args+=(--queue "$PACKET")
    fi
    if [[ -n "$PARTICIPANT_BOARD" ]]; then
      parallel_slots_args+=(--participant-board "$PARTICIPANT_BOARD")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      parallel_slots_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$PARALLEL_SLOTS" "${parallel_slots_args[@]}"
    ;;
  leases)
    lease_args=(--target "$TARGET_DIR" --format json)
    if [[ "$NO_WRITE" -eq 1 ]]; then
      lease_args+=(--no-write)
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      lease_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$LEASES" "${lease_args[@]}"
    ;;
  loop-control)
    loop_control_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      loop_control_args+=(--packet "$PACKET")
    fi
    if [[ "$NO_WRITE" -eq 1 ]]; then
      loop_control_args+=(--no-write)
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      loop_control_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$LOOP_CONTROL" "${loop_control_args[@]}"
    ;;
  goal-audit)
    goal_audit_args=(--target "$TARGET_DIR" --format json)
    if [[ -n "$PACKET" ]]; then
      goal_audit_args+=(--packet "$PACKET")
    fi
    if [[ -n "$OUTPUT_DIR" ]]; then
      goal_audit_args+=(--output-dir "$OUTPUT_DIR")
    fi
    python3 "$GOAL_AUDIT" "${goal_audit_args[@]}"
    ;;
  *)
    record "command" "fail" "unknown command: $COMMAND" >&2
    usage >&2
    exit 2
    ;;
esac
