# Runbook: Tmux Long Job

Use this for backups, large scans, builds, deploys, and fleet checks.

## Before Starting

Record:

```text
session:
workdir:
command:
log_file:
pid_file:
progress_check:
stop_command:
completion_criteria:
retention_rule:
prune_step:
final_report:
```

## Start

Prefer a wrapper script when the command is long or needs structured logging.

```sh
tmux new-session -d -s <session> '<command-or-wrapper>'
```

## Check

```sh
tmux ls
tmux capture-pane -pt <session> -S -120
ps -axo pid,ppid,state,etime,command | rg '<process-pattern>'
tail -n 80 <log_file>
```

## Completion

Completion needs more than "process disappeared":

- exit status or final line,
- final stats or output,
- retention rule and prune step when the job creates a backup,
- final report if user asked for it,
- no stale monitor sessions,
- no obsolete heartbeat automation.

## Stop

```sh
tmux kill-session -t <session>
```

If the process is doing I/O, prefer graceful shutdown first. Do not kill unknown processes by broad pattern.
