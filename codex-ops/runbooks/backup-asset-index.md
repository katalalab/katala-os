# Runbook: Backup Asset Index

Use this after a backup transfer finishes and before calling the backup easy to restore.

## Purpose

Create a metadata-only index for a backup tree:

- what major asset groups exist,
- where restore-critical docs and agent state live,
- which Codex SQLite files pass integrity checks,
- what should never be published to GitHub.

The index is not a second backup and does not move the original assets.

## Generate

```sh
codex-ops/scripts/backup-asset-index.sh <backup-root>
```

By default it writes under:

```text
<backup-root>/_index/
```

Expected files:

- `README.md`
- `asset-map.tsv`
- `sqlite-integrity.tsv`
- `restore-checklist.md`
- `by-category/<category>/README.md`

## Safety Boundary

The generated index must stay metadata-only. It may contain paths, sizes,
counts, and integrity status. It must not contain:

- raw SQLite rows,
- auth JSON,
- SSH private keys,
- tokens,
- cookies,
- shell snapshots,
- unredacted session logs.

Treat `credentials-local-only` entries as local restore material only.

## Verification

Check the index and SQLite report:

```sh
test -s <backup-root>/_index/asset-map.tsv
test -s <backup-root>/_index/sqlite-integrity.tsv
awk -F '\t' '$1=="BAD"{bad++} END{exit bad ? 1 : 0}' <backup-root>/_index/sqlite-integrity.tsv
```

If the SQLite check fails, preserve the broken DB and sidecars before repair,
then replace from a healthy source with `sqlite3 .backup`.
