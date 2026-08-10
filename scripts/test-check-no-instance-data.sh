#!/usr/bin/env bash
# Self-test for check-no-instance-data.sh. Every scan class gets a canary that
# must be caught AND a placeholder that must pass, so a pattern edit that opens
# a gap — or starts rejecting documented placeholders — fails here, in CI.
#
# Canary strings are assembled from fragments at runtime: the gate scans this
# repo's tracked files, and this file must never itself contain a catchable form.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT_DIR/scripts/check-no-instance-data.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/repo/scripts"
cp "$GATE" "$WORK/repo/scripts/"
cd "$WORK/repo"
git init -q
git add scripts/check-no-instance-data.sh

pass=0 fail=0

# expect <0|1> <label> <filename> <line> — stage one canary file, run the gate,
# compare exit codes, unstage.
expect() {
  local want="$1" label="$2" file="$3" line="$4" got=0
  printf '%s\n' "$line" > "$file"
  git add "$file"
  ./scripts/check-no-instance-data.sh >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-28s want exit %s, got %s\n' "$label" "$want" "$got" >&2
  fi
  git rm -q --cached "$file"
  rm -f "$file"
}

# Fragments. Concatenation keeps the assembled (catchable) form out of this file.
u="realuser""99"
ghp="ghp_""aaaaBBBBccccDDDDeeee1234"
pat="github_pat_""11AAAAAA0abcdefghijklmnopqr"
cg="100.""75.10.20"
rfc="192.16""8.1.50"
ula="fd7a:115c:""a1e0:ab12::1"
idv="k123""45"
vb="obs""erv"
avb="au""dit"
wh="hooks.slack.com""/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# --- must be caught ---------------------------------------------------------
expect 1 'macos home path'        canary.md "docs at /Users/$u/work"
expect 1 'linux home path'        canary.md "docs at /home/$u/work"
expect 1 'windows home path'      canary.md "docs at C:\\Users\\$u\\work"
expect 1 'windows fwd-slash path' canary.md "docs at D:/Users/$u/work"
expect 1 'cgnat v4 address'       canary.md "node reachable at $cg today"
expect 1 'rfc1918 v4 address'     canary.md "lan host $rfc"
expect 1 'tailscale ipv6 ula'     canary.md "node addr $ula"
expect 1 'github classic token'   canary.md "token $ghp"
expect 1 'github fine-grained'    canary.md "token $pat"
expect 1 'account identifier'     canary.md "owner: $idv"
expect 1 'identifier capitalized' canary.md "Owner: $idv"
expect 1 'dated narrative'        canary.md "${vb}ed the regression on 2026-01-15"
expect 1 'dated narrative caps'   canary.md "${vb^}ed the regression on 2026-01-15"
expect 1 'slack webhook'          canary.md "post to https://$wh"
expect 1 'host inventory file'    fleet-hosts.tsv "name,role"

# --- must pass (documented placeholders and provenance) ---------------------
expect 0 'placeholder macos home' canary.md "docs at /Users/youruser/work"
expect 0 'placeholder win home'   canary.md "docs at C:\\Users\\youruser\\work"
expect 0 'ci runner home'         canary.md "ci path /home/runner/work"
expect 0 'placeholder address'    canary.md "example net 100.100.100.10"
expect 0 'version string'         canary.md "requires macOS 10.15.7 or newer"
expect 0 'provenance dating'      canary.md "$avb checklist published 2026-01-15"
expect 0 'retrieval dating'       canary.md "retrieved 2026-01-15 from vendor docs"

printf 'gate self-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
