---
name: mac-maintenance
description: Run routine macOS maintenance on the local machine or a Tailscale fleet node — disk cleanup, log rotation, Homebrew update, Codex GC, launch daemon audit. Use when the operator asks to "clean up the Mac", "run maintenance", or reports disk/performance issues.
---

# mac-maintenance — macOS fleet node maintenance

Runs the standard Katala OS maintenance checklist for a macOS node.

## When to use

- "Mac のメンテナンスして"
- "ディスクが圧迫されてる、整理して"
- "ログが溜まってるから回転させて"
- "Homebrew を最新にして"
- "Codex ログ GC して"

Do **not** use for:
- Windows node maintenance (use PowerShell scripts directly)
- Production server maintenance
- Tailscale network configuration changes

## Checklist

### Disk

```bash
df -h /
du -sh ~/work ~/.codex ~/.claude/sessions/ /private/var/log/ 2>/dev/null
```

### Codex GC (`~/work/docs/scripts/codex-home-gc.sh`)

```bash
# dry-run first
bash ~/work/docs/scripts/codex-home-gc.sh
# then apply
bash ~/work/docs/scripts/codex-home-gc.sh --apply
```

### Log rotation

```bash
# Claude daemon log
wc -c ~/.claude/daemon.log
# If >50MB: archive and truncate
```

### Homebrew

```bash
brew update && brew upgrade && brew cleanup
```

### Launch daemons audit

```bash
# List user agents
launchctl list | grep -v com.apple | head -20
```

### Tailscale health

```bash
tailscale status --json | jq '.Self | {Online: .Online, LastSeen: .LastSeen}'
```

## Hard-rule reminders

- Always dry-run GC scripts before `--apply`.
- Do not `bootout` launchd services unless the operator explicitly names the service.
- Report disk before/after for any cleanup over 1 GB.
- Keep backup paths and restore commands for anything moved or deleted.
