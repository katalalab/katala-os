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

# scan <label> <ere-pattern> [allowed-ere] [git-grep-flags] [allow-scope]
# Matches tracked files only (git grep), skips binaries (-I), and drops hits that
# <allowed-ere> covers so documented placeholders do not trip the gate.
#
# allow-scope picks what <allowed-ere> is tested against, and the two scans need
# different answers. For a token class (an address, a home path) the allow-list means
# "this token is the documented placeholder", so it has to be tested per match: -o
# narrows each hit to the match itself, because testing the whole line let a real
# leak ride along with any example sharing it — a sentence naming the placeholder
# and a real node dropped the node too, and the gate said clean. For a sentence
# class the allow-list means "this whole sentence is provenance, not a session
# trace", and the allowing word routinely falls outside the matched window, so that
# scan tests the line. It keeps the ride-along weakness, which is the accepted cost
# of a heuristic that reads sentences rather than tokens.
#
# Spell word boundaries out as (^|[^0-9A-Za-z_]) rather than \b: git grep -E hands
# the pattern to the platform regex engine, and \b is a GNU extension. On macOS and
# BSD it matches nothing at all, so the pattern silently stops firing and the gate
# reports clean — a false green in the one place that must not have one.
scan() {
  local label="$1" pattern="$2" allowed="${3:-}" flags="${4:-}" allow_scope="${5:-match}"
  local hits only='-o'
  if [ "$allow_scope" = 'line' ]; then only=''; fi
  hits="$(git grep -nIE $only $flags "$pattern" -- . ":!$SELF" 2>/dev/null || true)"
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
#
# Trailing boundary only, deliberately. A leading (^|[^0-9A-Za-z_]) consumes the
# character in front of the match, so with -o the placeholder in
# "100.100.100.10 <real address>" ate the space the real address needed and the
# real one was never extracted — the allow-list then removed the placeholder and
# the gate said clean. The trailing boundary alone still rejects an address buried
# in a longer token, and erring toward catching is the right direction here.
scan 'private address' \
  '(100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9A-Za-z_]|$)' \
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
  '(owner|user|username|login|account)["'"'"':= ]+[A-Za-z][0-9]{5}([^0-9A-Za-z_]|$)' \
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
  '-i' \
  'line'

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
