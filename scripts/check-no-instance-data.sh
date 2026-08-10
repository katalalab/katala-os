#!/usr/bin/env bash
# check-no-instance-data.sh — refuse to publish one instance of the discipline.
#
# This repo publishes the shape (templates, hooks, policy, orchestration), never a
# real fleet. Once a real hostname or home path is cloned it cannot be recalled, so
# this runs as a CI gate rather than a review checklist item.
#
# Read-only. Non-zero exit on any hit. Add a new scan line when a leak class appears.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
SELF='scripts/check-no-instance-data.sh'

# scan <label> <ere-pattern> [allowed-ere]
# Matches tracked files only (git grep), skips binaries (-I), and drops lines
# matching <allowed-ere> so documented placeholders do not trip the gate.
scan() {
  local label="$1" pattern="$2" allowed="${3:-}" flags="${4:-}"
  local hits
  hits="$(git grep -nIE $flags "$pattern" -- . ":!$SELF" 2>/dev/null || true)"
  if [ -n "$allowed" ] && [ -n "$hits" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$allowed" || true)"
  fi
  if [ -n "$hits" ]; then
    fail=1
    printf '\n[%s]\n%s\n' "$label" "$hits" >&2
  fi
}

# Home directories carrying a real account name. Placeholders ($HOME, youruser,
# <user>, ${VAR}, /Users/me) are the supported way to write these.
scan 'real home path' \
  '(/Users/|/home/)[A-Za-z][A-Za-z0-9_-]{2,}' \
  '/Users/(youruser|me|secret|private|\$|<)|/home/(youruser|runner|\$|<)|/Users/\{|/home/\{'

# Same class, Windows spelling: a drive letter in front and either slash kind.
# The fleet runs Windows nodes, so C:\Users\<realname> is exactly the form a
# Windows-side excerpt would carry ($env:USERPROFILE is the placeholder there).
scan 'real home path (windows)' \
  '[A-Za-z]:[\\/][Uu]sers[\\/][A-Za-z][A-Za-z0-9_-]{2,}' \
  '[\\/][Uu]sers[\\/](youruser|me|secret|private|Public|\$|<|\{)'

# Tailscale CGNAT range and RFC1918, excluding the documented placeholder. Full
# dotted quads only: requiring four octets keeps version strings like 10.15.7
# from tripping the gate in a docs-heavy tree.
scan 'private address' \
  '\b(100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b' \
  '100\.100\.100\.'

# Tailscale also assigns every node a ULA in fd7a:115c:a1e0::/48; the v6 form
# identifies a tailnet node as precisely as the CGNAT v4 one.
scan 'private address (tailscale ipv6)' \
  'fd7a:115c:a1e0:[0-9a-f:]+' \
  '' \
  '-i'

# High-confidence credential shapes. Keep in sync with SECRET_RE in
# hooks/pre-commit — the commit-time and publish-time gates cover the same set.
scan 'credential' \
  '(gho_|ghp_|ghs_|github_pat_)[A-Za-z0-9_]{20,}|sk-(ant|proj|live)-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{30,}|xox[abpsr]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# Employee/account identifier shape (letter + 5 digits) assigned to a user field.
# Case-insensitive: the field name is prose ("Owner:", "USER=") and capitalization
# varies, unlike token prefixes whose issued form is fixed.
scan 'account identifier' \
  '(owner|user|username|login|account)["'"'"':= ]+[A-Za-z][0-9]{5}\b' \
  '' \
  '-i'

# Real inbound webhook endpoints.
scan 'webhook endpoint' \
  'hooks\.slack\.com/services/[A-Za-z0-9/]+|discord(app)?\.com/api/webhooks/[0-9]+'

# "I saw X on my machine on DATE" narratives. A regex cannot see semantic leaks in
# general, but this one class is mechanical and it is the class that survived the
# first sanitization pass: an observation verb next to a calendar date turns a
# reusable rule into a trace of one real session. Provenance dating (ratified,
# retrieved, generated, published) is legitimate and stays allowed.
scan 'dated observation' \
  '(observ|measur|identif|benchmark|audit|detect|notic|reproduc|encounter)[a-z]*.{0,80}[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2}.{0,80}(observ|measur|identif|benchmark|audit|detect|notic|reproduc|encounter)[a-z]*' \
  '(ratified|retrieved|generated|published)' \
  '-i'

# Host inventories must stay out of the published tree; ship a .example instead.
inventory="$(git ls-files | grep -E '(^|/)(fleet-hosts\.tsv|fleet-env-manifest\.json)$' || true)"
if [ -n "$inventory" ]; then
  fail=1
  printf '\n[host inventory]\n%s\n' "$inventory" >&2
fi

if [ "$fail" -ne 0 ]; then
  printf '\ncheck-no-instance-data: instance data found. Replace with a placeholder ($HOME, youruser, 100.100.100.10) or remove the file.\n' >&2
  exit 1
fi

printf 'check-no-instance-data: clean\n'
