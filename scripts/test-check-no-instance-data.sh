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
rvb="repro""duc"
avb="au""dit"
cidr="100.""64.0.0/"
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

# Every canary above sits inside a sentence, so the spaces around it satisfy any
# boundary condition — including none at all. These three pin the boundary itself:
# a bare address exercises the ^ and $ alternatives, and the two negatives fail if
# the boundary is dropped or its character class stops covering the underscore.
expect 1 'address alone on line'  canary.md "$rfc"

# Prose names the placeholder and the real thing in one breath, so the allow-list
# has to be applied per match. These fail if it goes back to dropping whole lines.
expect 1 'leak beside placeholder' canary.md "example net 100.100.100.10 and node $cg"
expect 1 'leak beside placeholder home' canary.md "docs at /Users/youruser/work plus /Users/$u/work"
# Adjacent, one separator between them: a leading boundary group would consume that
# separator for the placeholder and leave the real address unmatchable.
expect 1 'leak abutting placeholder' canary.md "100.100.100.10 $cg"
expect 1 'leak abutting placeholder comma' canary.md "100.100.100.10,$cg"

# --- must pass (documented placeholders and provenance) ---------------------
expect 0 'placeholder macos home' canary.md "docs at /Users/youruser/work"
expect 0 'placeholder win home'   canary.md "docs at C:\\Users\\youruser\\work"
expect 0 'ci runner home'         canary.md "ci path /home/runner/work"
expect 0 'placeholder address'    canary.md "example net 100.100.100.10"
expect 0 'version string'         canary.md "requires macOS 10.15.7 or newer"
expect 0 'address inside a token' canary.md "artifact${rfc}build"
expect 0 'identifier word suffix' canary.md "owner: ${idv}_secret"
expect 0 'provenance dating'      canary.md "$avb checklist published 2026-01-15"
# Same sentence, date first. The match window then ends at the verb and never
# reaches the allowing word, so this fails the moment that scan starts testing
# the allow-list against the match instead of the line.
expect 0 'provenance dating rev'  canary.md "2026-01-15 $avb checklist published"
expect 0 'retrieval dating'       canary.md "retrieved 2026-01-15 from vendor docs"

# --- credential classes this fleet can actually issue -------------------------
# Added after reading github/awesome-copilot's secrets-scanner. Only the shapes
# something here can hand out: the Discord bot tokens and webhook in the agents
# vault, npm and JWT from the node and auth paths, database URIs because psql is a
# preferred CLI, and the GCP service-account marker because the fleet holds several.
ghr="ghr_""aaaaBBBBccccDDDDeeee1234"
npmt="npm_""aaaaBBBBccccDDDDeeeeFFFFgggg1234hhhh"
jwt="eyJ""hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ1234567890x"
dbot="MTA""xNzI4OTk5OTk5OTk5OTk5OQ.GaBcDe.f1234567890abcdefghijklmnopqrstuvw"
dhook="discord.com""/api/webhooks/1234567890123456789/aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
dburi="postgres""ql://svcuser:hunter2hunter2@db.internal:5432/app"
gcpsa='"type"'": "'"service_account"'
awssec="aws_secret_access_key"" = wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEYabcd"

expect 1 'github refresh token'   canary.md "token $ghr"
expect 1 'npm token'              canary.md "//registry.npmjs.org/:_authToken=$npmt"
expect 1 'jwt'                    canary.md "session $jwt"
expect 1 'discord bot token'      canary.md "bot $dbot"
expect 1 'discord webhook'        canary.md "post to https://$dhook"
expect 1 'database uri with creds' canary.md "DATABASE_URL=$dburi"
expect 1 'gcp service account'    canary.json "{$gcpsa}"
expect 1 'aws secret assignment'  canary.md "$awssec"

# A URI without credentials is a hostname, not a secret, and docs are full of them.
expect 0 'database uri no creds'  canary.md "connect to postgresql://localhost:5432/app"
expect 0 'jwt-ish short string'   canary.md "prefix eyJshort.eyJshort.sig"

# --- the two gates must cover the same set ------------------------------------
# The sync between hooks/pre-commit and the credential scan is stated in a comment
# in both files. A comment does not fail when someone adds a class to one of them,
# and the gate that still fires would hide the one that no longer does.
gate_re="$(sed -n "s/^  '\(.*\)'\$/\1/p" "$ROOT_DIR/scripts/check-no-instance-data.sh" | grep -F 'AKIA[0-9A-Z]{16}' | head -1)"
hook_re="$(sed -n "s/^SECRET_RE='(\(.*\))'\$/\1/p" "$ROOT_DIR/hooks/pre-commit")"
norm() { printf '%s\n' "$1" | tr '|' '\n' | sed 's/^(//;s/)$//' | sort -u; }
if [ -n "$gate_re" ] && [ -n "$hook_re" ] && [ -z "$(comm -3 <(norm "$gate_re") <(norm "$hook_re"))" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  printf 'FAIL %-28s credential classes differ between the gate and hooks/pre-commit\n' 'gates in sync' >&2
  comm -3 <(norm "$gate_re") <(norm "$hook_re") >&2
fi

# --- the report must not republish what it caught -----------------------------
# A public repository's Actions log is public. Printing the matched text there
# hands the leak to a second place, one with no history to rewrite, every time
# the gate does its job. Location and scan name are what a developer needs.
report() {
  local want="$1" label="$2" file="$3" line="$4" out
  printf '%s\n' "$line" > "$file"
  git add "$file"
  out="$(./scripts/check-no-instance-data.sh 2>&1 || true)"
  if printf '%s' "$out" | grep -qF -- "$want"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-28s report did not contain %s\n' "$label" "$want" >&2
  fi
  git rm -q --cached "$file"; rm -f "$file"
}
notreport() {
  local forbidden="$1" label="$2" file="$3" line="$4" out
  printf '%s\n' "$line" > "$file"
  git add "$file"
  out="$(./scripts/check-no-instance-data.sh 2>&1 || true)"
  if printf '%s' "$out" | grep -qF -- "$forbidden"; then
    fail=$((fail+1))
    printf 'FAIL %-28s report republished %s\n' "$label" "$forbidden" >&2
  else
    pass=$((pass+1))
  fi
  git rm -q --cached "$file"; rm -f "$file"
}

notreport "$u"        'home path not echoed'   canary.md "docs at /Users/$u/work"
report    'canary.md' 'home path location kept' canary.md "docs at /Users/$u/work"
notreport "$cg"       'address not echoed'     canary.md "node reachable at $cg today"
notreport "$ghp"      'token not echoed'       canary.md "token $ghp"
notreport "$idv"      'identifier not echoed'  canary.md "owner: $idv"
# The dated-observation class carries no identifier, and masking it would leave a
# developer guessing which sentence tripped a heuristic. It stays readable.
report 'regression'   'dated line stays readable' canary.md "${vb}ed the regression on 2026-01-15"

# --- repo-local exemptions ---------------------------------------------------
# An exemption has to cover exactly what it names and nothing else. The dangerous
# version is one that widens past its own scan class, so each case below pairs the
# thing being excused with a leak that must still be caught while it is in effect.
exempt() {
  printf '%s\n' "$@" > .instance-data-allow
  git add .instance-data-allow
}
unexempt() { git rm -q --cached .instance-data-allow; rm -f .instance-data-allow; }

exempt 'private address: 100\.64\.0\.0/'
expect 0 'exempted cidr block'    canary.md "CGNAT is ${cidr}10"
# Same scan, a different value: excusing the block must not excuse a node inside it.
expect 1 'exemption is not blanket' canary.md "node reachable at $cg today"
# Different scan: the exemption names 'private address', so a home path is untouched.
expect 1 'exemption stays in class' canary.md "docs at /Users/$u/work"
unexempt

exempt 'dated observation: ROADMAP'
expect 0 'exempted dated line'     canary.md "ROADMAP row ${rvb}ible in CI, done 2026-08-01"
expect 1 'same line unexempted later' canary.md "plain row ${rvb}ible in CI, done 2026-08-01"
expect 1 'other dated line still caught' canary.md "${vb}ed the regression on 2026-01-15"
unexempt

# A comment-only file must not be read as an exemption of everything.
exempt '# nothing exempted here'
expect 1 'comments exempt nothing' canary.md "lan host $rfc"
unexempt

# --- the gate must not report clean when it could not read the tree -----------
# Running it outside a repository is the cheapest way to make git grep fail for
# real (exit 128) rather than simply find nothing.
NOREPO="$(mktemp -d)"
mkdir -p "$NOREPO/scripts"
cp "$GATE" "$NOREPO/scripts/"
if "$NOREPO/scripts/check-no-instance-data.sh" >/dev/null 2>&1; then
  fail=$((fail+1))
  printf 'FAIL %-28s reported success with no repository to scan\n' 'scan failure is loud' >&2
else
  pass=$((pass+1))
fi
rm -rf "$NOREPO"

printf 'gate self-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
