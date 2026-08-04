#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${HOSTS_FILE:-$ROOT/fleet-hosts.tsv}"
USERS_CSV="${FLEET_USERS:-$USER,administrator,Administrator}"

IFS=',' read -r -a USERS <<<"$USERS_CSV"

ssh_try() {
  local user="$1" host="$2"
  perl -e 'alarm shift; exec @ARGV' 12 ssh -n -T \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o ConnectTimeout=12 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=accept-new \
    "${user}@${host}" 'whoami' 2>&1
}

printf 'alias\tdns\tipv4\tos\ttailscale_ping\ttcp22\tssh_auth\tuser\tmessage\n'
tail -n +2 "$HOSTS_FILE" | while IFS=$'\t' read -r alias dns ipv4 os status role node_id expected_hostname dev_session_kind; do
  ping_status="skip"
  tcp22="skip"
  ssh_auth="skip"
  ok_user="-"
  message="-"
  ssh_host="$alias"
  tcp_hosts=("$alias" "$dns" "$ipv4")

  if [[ "$status" != "online" || "$role" == *"no-ssh-expected"* ]]; then
    message="skipped: status=$status role=$role"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$alias" "$dns" "$ipv4" "$os" "$ping_status" "$tcp22" "$ssh_auth" "$ok_user" "$message"
    continue
  fi

  if [[ "$role" == *"current-local"* ]]; then
    ssh_host="localhost"
    tcp_hosts=("localhost" "127.0.0.1" "$ipv4")
  fi

  if tailscale ping --timeout=3s --c=1 "$alias" >/dev/null 2>&1 || tailscale ping --timeout=3s --c=1 "$dns" >/dev/null 2>&1 || tailscale ping --timeout=3s --c=1 "$ipv4" >/dev/null 2>&1; then
    ping_status="ok"
  else
    ping_status="fail"
  fi

  tcp22="closed"
  for tcp_host in "${tcp_hosts[@]}"; do
    if nc -G 12 -z "$tcp_host" 22 >/dev/null 2>&1; then
      tcp22="open"
      break
    fi
  done

  if [[ "$tcp22" == "open" ]]; then
    ssh_auth="fail"
    for user in "${USERS[@]}"; do
      out="$(ssh_try "$user" "$ssh_host" || true)"
      if [[ "$out" == *"Tailscale SSH requires an additional check"* || "$out" == *"To authenticate, visit:"* ]]; then
        ssh_auth="check-required"
        ok_user="$user"
        message="$(printf '%s' "$out" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-180)"
        break
      fi
      if [[ "$out" != *"Permission denied"* && "$out" != *"Connection reset"* && "$out" != *"Host key verification failed"* && "$out" != *"agent refused"* && "$out" != *"timed out"* && "$out" != *"Could not resolve hostname"* && "$out" != *"Name or service not known"* && "$out" != *"No route to host"* && "$out" != *"Connection refused"* && "$out" != *"Connection timed out"* && "$out" != *"Connection closed"* && "$out" != "#"* && -n "$out" ]]; then
        ssh_auth="ok"
        ok_user="$user"
        message="$(printf '%s' "$out" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g')"
        break
      fi
      message="$(printf '%s' "$out" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-180)"
    done
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$alias" "$dns" "$ipv4" "$os" "$ping_status" "$tcp22" "$ssh_auth" "$ok_user" "$message"
done
