# Runbook: Backup Verification

## Completion Criteria

A backup is complete only when:

- transfer finished,
- stable differences are zero or explained,
- volatile differences are classified,
- destination availability is confirmed,
- cloud upload is confirmed if the target is Drive or another cloud sync folder,
- final report exists when the user asked for one.

## Google Drive

Use file-level evidence:

```sh
fileproviderctl evaluate <artifact>
```

Look for:

```text
isUploaded=1
isUploading=0
```

Do not rely only on folder presence.

## Rsync

Prefer stable verification:

```sh
rsync -an --delete <source> <dest>
```

Known volatile categories:

- Photos cloudsync metadata,
- active logs,
- LevelDB files,
- FileProvider wharf/tombstone paths,
- cache directories,
- app runtime sockets.

## External SSD

Check:

```sh
df -h <dest>
tmux ls
pgrep -af rsync
tail -n 80 <log>
cat <exit-status-file>
```

If `rsync` exits `23`, classify errors before deciding completion.
