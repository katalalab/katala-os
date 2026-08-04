#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 || "${1:-}" =~ ^(-h|--help)$ ]]; then
  cat <<'EOF'
Usage:
  fleet-dev-sync.sh user@host [user@host ...]

Syncs lightweight Codex/Claude development context to SSH-reachable POSIX
targets. Windows targets should use a separate PowerShell profile sync.
EOF
  exit 0
fi

AGENT_CONTEXT="${AGENT_CONTEXT:-$HOME/work/agent-context/AGENTS.MD}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"

for target in "$@"; do
  echo "==> $target"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" 'uname -s' >/dev/null
  ssh "$target" 'mkdir -p ~/work/agent-context ~/.codex ~/.claude'
  if [[ -f "$AGENT_CONTEXT" ]]; then
    rsync -az "$AGENT_CONTEXT" "$target:~/work/agent-context/AGENTS.MD"
    ssh "$target" 'ln -sf ~/work/agent-context/AGENTS.MD ~/.claude/CLAUDE.md; ln -sf ~/work/agent-context/AGENTS.MD ~/AGENTS.md'
  fi
  if [[ -f "$CODEX_CONFIG" ]]; then
    rsync -az "$CODEX_CONFIG" "$target:~/.codex/config.toml"
  fi
done
