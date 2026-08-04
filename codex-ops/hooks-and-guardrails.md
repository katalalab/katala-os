# Hooks and Guardrails

This file defines guardrails that should become hooks, checklist items, or evals.

The first implementation should be advisory. Hard-blocking hooks should only be added after the rule has low false-positive risk.

## Hook Candidates

| Hook | Trigger | Check | Action |
|---|---|---|---|
| `drive-backup-completion-check` | reporting Google Drive backup completion | `rsync -an` stable diff plus `fileproviderctl evaluate` on target artifact | refuse "complete" wording unless upload evidence exists |
| `rsync-drive-safety` | `rsync -E` into Drive/CloudStorage | look for Drive-backed destination and `-E` | warn or retry with plain `rsync -a --exclude='.DS_Store'` |
| `volatile-diff-classifier` | backup verification diff exists | classify Photos cloudsync, active logs, LevelDB, FileProvider temp paths | separate stable misses from volatile churn |
| `github-publish-preflight` | pushing or deleting GitHub branches | SSH auth, `gh auth status`, repo push permission, remote branch state | require remote evidence before final "clean" report |
| `secret-scan-publication-gate` | publishing backup-like or env-like material | private repo, secret scan, history boundary | prefer tracked-tree snapshot if history is risky |
| `tailscale-ssh-preflight` | fleet SSH/Tailscale work | Tailscale status, `RunSSH`, TCP 22, `ssh -G`, 1Password signer | classify offline, closed, auth, approval-required separately |
| `one-host-before-fanout` | multi-host SSH/bootstrap | one host end-to-end before bulk operations | stop broad rollout until one path is proven |
| `interactive-blocker-classifier` | approval URL, `check-required`, `agent refused operation` | identify user action requirement | continue non-blocked work and report exact blocker |
| `tmux-long-job-contract` | starting detached long task | session name, command, log, progress, stop command, completion criteria | create monitor note before backgrounding |
| `settings-change-preflight` | editing `.codex/config.toml`, shell startup, SSH config | backup/snapshot, current config read, blast radius | require concise change record |

## Risk Levels

| Level | Examples | Required Evidence |
|---|---|---|
| Low | read-only inventory, local docs, non-sensitive formatting | files read, no write outside docs |
| Medium | config docs, test runs, local scripts | command output summary, changed files |
| High | GitHub publish, backup deletion, auth config, SSH changes, external upload | preflight, audit, final verification |
| Critical | destructive commands, credential movement, public release | explicit user confirmation and rollback plan |

## Tmux Contract

Every long-running tmux job should have:

```text
session:
command:
working_directory:
log_file:
pid_file:
progress_check:
stop_command:
completion_criteria:
final_report:
```

Minimum commands:

```sh
tmux new-session -d -s <session> '<wrapper>'
tmux capture-pane -pt <session> -S -120
tmux kill-session -t <session>
```

Do not leave monitor sessions running after the reason for monitoring is gone.

## Completion Language

Use precise completion wording:

- "完了" only when the requested success condition is actually met.
- "完了。ただし..." when the user-facing objective is met with known, documented exceptions.
- "未完了" when any critical success condition is missing.
- "ブロック中" only when the blocker requires user action or external state change.
