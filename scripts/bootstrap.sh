#!/usr/bin/env bash
# bootstrap.sh — point top-level CLI context files at the agent-context canonical AGENTS.MD.
# Idempotent: safe to re-run. Replaced entries are retained for five runs.
#
# Scope (Phase 1): ~/CLAUDE.md, ~/AGENTS.md, ~/GEMINI.md only.
# Out of scope: ~/.claude/skills/, ~/.codex/skills/, ~/.codex/AGENTS.md (RTK.md pointer).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL="$REPO_ROOT/AGENTS.MD"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.local/state/agent-context-backups/bootstrap"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
BACKUP_KEEP=5
BACKUP_CREATED=0

if [ ! -f "$CANONICAL" ]; then
  echo "error: canonical AGENTS.MD not found at $CANONICAL" >&2
  exit 1
fi

link_one() {
  local target="$1"
  local backup

  backup="$BACKUP_DIR/${target#"$HOME"/}"

  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$CANONICAL" ]; then
      echo "  ok    $target -> $CANONICAL"
      return 0
    fi
    mkdir -p "$(dirname "$backup")"
    echo "  backup  $target -> $backup (was -> $current)"
    mv "$target" "$backup"
    BACKUP_CREATED=1
  elif [ -e "$target" ]; then
    if cmp -s "$target" "$CANONICAL"; then
      mkdir -p "$(dirname "$backup")"
      echo "  backup  $target -> $backup (identical content)"
      mv "$target" "$backup"
      BACKUP_CREATED=1
    else
      mkdir -p "$(dirname "$backup")"
      echo "  backup  $target -> $backup"
      mv "$target" "$backup"
      BACKUP_CREATED=1
    fi
  else
    echo "  create  $target"
  fi

  ln -s "$CANONICAL" "$target"
}

echo "agent-context bootstrap (canonical: $CANONICAL)"
for f in "$HOME/CLAUDE.md" "$HOME/AGENTS.md" "$HOME/GEMINI.md"; do
  link_one "$f"
done

if [ "$BACKUP_CREATED" -eq 1 ]; then
  echo
  echo "Backup: $BACKUP_DIR"
  echo "Restore: remove the replacement symlink, then move the matching file from $BACKUP_DIR back under $HOME"
fi

if [ -d "$BACKUP_ROOT" ]; then
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 \
    | sort -zr \
    | awk -v RS='\0' -v keep="$BACKUP_KEEP" 'NR > keep { printf "%s%c", $0, 0 }' \
    | xargs -0r rm -r
fi

echo
echo "Verification:"
for f in "$HOME/CLAUDE.md" "$HOME/AGENTS.md" "$HOME/GEMINI.md"; do
  if [ -L "$f" ] && [ "$(readlink "$f")" = "$CANONICAL" ]; then
    echo "  PASS  $f"
  else
    echo "  FAIL  $f"
    exit 1
  fi
done

echo
echo "Done. To pick up future changes: cd $REPO_ROOT && git pull"
