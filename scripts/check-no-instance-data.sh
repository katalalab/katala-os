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
ALLOW_FILE='.instance-data-allow'

# Repositories whose subject matter *is* the thing a scan looks for need a way to
# say so. A tool that implements tailnet addressing has to name the CGNAT block;
# refusing it leaves the choice between a false red and no gate at all, and a gate
# that gets switched off protects nothing.
#
# Format, one per line: "<scan label>: <ERE>". The exemption applies to that scan
# only, so excusing a range cannot also excuse a home path. The file is tracked, so
# every exemption arrives through a diff someone reads, and the gate prints the ones
# it honoured — an allowance that widens quietly is the failure mode to avoid.
# Most labels have no exemption, and grep exits 1 on no match. Under pipefail that
# made the whole pipeline fail, and set -e then killed the gate at the first such
# scan — before any output. Swallow the empty case explicitly.
repo_allow() {
  local label="$1"
  [ -f "$ALLOW_FILE" ] || return 0
  { sed -n "s/^${label}:[[:space:]]*//p" "$ALLOW_FILE" || true; } \
    | { grep -v '^[[:space:]]*$' || true; } \
    | paste -sd '|' -
}

if [ -f "$ALLOW_FILE" ]; then
  printf 'check-no-instance-data: honouring %s exemption(s) from %s\n' \
    "$(grep -cvE '^[[:space:]]*(#|$)' "$ALLOW_FILE" || true)" "$ALLOW_FILE"
fi

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
  local label="$1" pattern="$2" allowed="${3:-}" flags="${4:-}" allow_scope="${5:-match}" redact="${6:-1}"
  local hits rc=0 only='-o' extra
  if [ "$allow_scope" = 'line' ]; then only=''; fi
  extra="$(repo_allow "$label")"
  if [ -n "$extra" ]; then allowed="${allowed:+$allowed|}$extra"; fi
  # git grep exits 1 for "no match" and 2+ for "could not run" — an unreadable
  # object, a bad pathspec, no repository at all. Discarding stderr and treating
  # every non-zero the same made those report as nothing to see, which is this
  # gate promising a clean tree it never managed to read.
  hits="$(git grep -nIE $only $flags "$pattern" -- . ":!$SELF")" || rc=$?
  if [ "$rc" -gt 1 ]; then
    printf '\ncheck-no-instance-data: [%s] scan could not run (git grep exit %s). Refusing to report clean.\n' "$label" "$rc" >&2
    exit 2
  fi
  if [ -n "$allowed" ] && [ -n "$hits" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$allowed" || true)"
  fi
  if [ -n "$hits" ]; then
    fail=1
    # Print where, not what. On a public repository the Actions log is public, so
    # echoing the matched text means a failing run republishes the very string the
    # gate exists to keep out — and does it somewhere with no history to rewrite.
    # The location plus the scan name is enough to find it locally; the classes
    # that carry no identifier stay readable so the diagnosis is not guesswork.
    if [ "$redact" = 1 ]; then
      hits="$(printf '%s\n' "$hits" | sed -E 's/^([^:]*:[0-9]+:).*/\1<redacted — run the gate locally to see it>/')"
    fi
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
# test-check-no-instance-data.sh asserts the two are identical rather than trusting
# this comment; the classes below were added from one file first and the drift would
# otherwise be invisible until the wrong gate was the only one that fired.
#
# The classes here are the ones this fleet can actually issue. Stripe, Twilio and
# SendGrid shapes are deliberately absent — carrying patterns for credentials nobody
# here holds buys nothing and makes the set look more complete than it is.
scan 'credential' \
  '(gho_|ghp_|ghr_|ghs_|github_pat_)[A-Za-z0-9_]{20,}|sk-(ant|proj|live)-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{30,}|xox[abpsr]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|npm_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|[MN][A-Za-z0-9_-]{23,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}|discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]{20,}|hooks\.slack\.com/services/[A-Za-z0-9]+/[A-Za-z0-9]+/[A-Za-z0-9]{20,}|(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp|mssql)://[^:/@[:space:]]+:[^@[:space:]]+@|aws_secret_access_key[[:space:]]*[:=][[:space:]]*.?[A-Za-z0-9/+=]{40}|"type"[[:space:]]*:[[:space:]]*"service_account"'

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
  'line' \
  0

# Host inventories must stay out of the published tree; ship a .example instead.
# Listed separately from the filter for the same reason the scans check their exit
# status: piping straight into grep and closing with || true would let a failed
# listing read as an empty tree.
tracked="$(git ls-files)" || {
  printf '\ncheck-no-instance-data: [host inventory] listing could not run (git ls-files exit %s). Refusing to report clean.\n' "$?" >&2
  exit 2
}
inventory="$(printf '%s\n' "$tracked" | grep -E '(^|/)(fleet-hosts\.tsv|fleet-env-manifest\.json)$' || true)"
if [ -n "$inventory" ]; then
  fail=1
  printf '\n[host inventory]\n%s\n' "$inventory" >&2
fi

if [ "$fail" -ne 0 ]; then
  printf '\ncheck-no-instance-data: instance data found. Replace with a placeholder ($HOME, youruser, 100.100.100.10) or remove the file.\n' >&2
  exit 1
fi

printf 'check-no-instance-data: clean\n'
