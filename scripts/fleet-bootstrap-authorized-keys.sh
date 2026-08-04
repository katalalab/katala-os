#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fleet-bootstrap-authorized-keys.sh user@host [user@host ...]

Installs the public keys currently exposed by the local SSH agent into each
target account's authorized_keys. This requires SSH auth to the target to
already work at least once.

Set SSH_AUTH_SOCK before running if you want a specific agent.
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ || $# -eq 0 ]]; then
  usage
  exit 0
fi

agent_sock="${SSH_AUTH_SOCK:-$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock}"
keys="$(SSH_AUTH_SOCK="$agent_sock" ssh-add -L 2>/dev/null | awk '!seen[$0]++')"
if [[ -z "$keys" ]]; then
  echo "No public keys available from SSH agent: $agent_sock" >&2
  exit 1
fi

keys_b64="$(printf '%s\n' "$keys" | base64 | tr -d '\n')"

for target in "$@"; do
  echo "==> $target"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" 'uname -s' >/tmp/fleet-remote-uname.$$ 2>/dev/null; then
    remote_os="$(cat /tmp/fleet-remote-uname.$$)"
    rm -f /tmp/fleet-remote-uname.$$
  else
    remote_os="windows"
  fi

  case "$remote_os" in
    Darwin|Linux|FreeBSD)
      ssh "$target" "KEYS_B64='$keys_b64' sh -s" <<'REMOTE_POSIX'
set -eu
umask 077
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
tmp="$(mktemp)"
printf '%s' "$KEYS_B64" | base64 -d >"$tmp"
while IFS= read -r key; do
  [ -n "$key" ] || continue
  grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf '%s\n' "$key" >>"$HOME/.ssh/authorized_keys"
done <"$tmp"
rm -f "$tmp"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"
REMOTE_POSIX
      ;;
    *)
      ssh "$target" "powershell -NoProfile -ExecutionPolicy Bypass -Command \"\$keys=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$keys_b64')) -split [Environment]::NewLine; \$dir=Join-Path \$HOME '.ssh'; New-Item -ItemType Directory -Force -Path \$dir | Out-Null; \$ak=Join-Path \$dir 'authorized_keys'; New-Item -ItemType File -Force -Path \$ak | Out-Null; foreach(\$key in \$keys){ \$k=\$key.Trim(); if(\$k -and -not (Select-String -Path \$ak -SimpleMatch \$k -Quiet)){ Add-Content -Path \$ak -Value \$k } }\""
      ;;
  esac
done
