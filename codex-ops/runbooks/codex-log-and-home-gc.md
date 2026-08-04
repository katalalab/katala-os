# Runbook: Codex Log Retention and Home GC

Fleet-wide policy values and procedures for `~/.codex/` growth. Canonical here; `AGENTS.MD` Maintenance and OS overlays point at this file.

## logs_2.sqlite retention

- Soft cap: 250 MiB (ratified 2026-07-29). The former 100 MiB was unreachable — a busy day on an active node writes ~138 MiB of rows and retention only prunes rows older than one day, so one day always breached it.
- Row-level retention: `~/work/docs/scripts/codex-logs-retention.py --keep-days 1 --apply` (report-only without `--apply`; backs up with `quick_check`, deletes stale rows, reclaims with `incremental_vacuum`, keeps the newest 2 backups, yields when Codex holds the write lock). A full VACUUM cannot bring the file under the cap: the size is real rows.
- Before VACUUM or rotation: copy `logs_2.sqlite`, `logs_2.sqlite-wal`, and `logs_2.sqlite-shm` to `~/.codex/log-maintenance-backups/<timestamp>/`.
- Restore: stop Codex, copy backup files back to `~/.codex/`, restart Codex.

Windows remote specifics (SSH discovery, Scheduled Task wiring): `windows-codex-remote-and-log-retention.md`.

## Home GC

`~/work/docs/scripts/codex-home-gc.sh` — dry-run default; pass `--apply` to act.

- `log/*.log`: rotate when >500 MB; keep tail 200 MB in `log-maintenance-backups/codex-log-rotate-<base>-<ts>/` (cascades into the rule below). Closes the 2026-05 `codex-tui.log` 98 GB unbounded-growth gap.
- `log-maintenance-backups/`: keep 2 newest, compress >7d as `tar.zst`, delete >30d.
- `archived_sessions/`: compress >7d as `tar.zst` with sidecar index, delete raw after compression.
- `config.toml.bak-*`: keep 5 newest.
- `cleanup-backups/`: delete >30d.
- `.tmp/`: clear entries >7d.
- `~/.agents/skills.disabled-*` and `~/.codex/skills.disabled-*` (disabled skill scopes): delete >90d.
- `~/work/docs/evidence/codex-assets/*` (log/session digests): delete >60d via `codex-log-digest.sh --gc`.

## Health check

`~/work/docs/scripts/verify.sh` — non-destructive AI Dev OS docs/handoff check; warns when `~/.codex/` piles exceed soft caps.
