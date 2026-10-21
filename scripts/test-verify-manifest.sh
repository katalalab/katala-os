#!/usr/bin/env bash
# Exercise the verifier against real lock files without touching installed context.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT_DIR/scripts/verify-manifest.sh"
MANIFEST_SHELL="${MANIFEST_TEST_BASH:-$BASH}"
WORK="$(mktemp -d)"
TILDE_ROOT=""
cleanup() {
  rm -rf "$WORK"
  if [ -n "$TILDE_ROOT" ]; then rm -rf "$TILDE_ROOT"; fi
}
trap cleanup EXIT
cd "$WORK"

printf 'manifest fixture\n' > 'artifact data.txt'
cat > valid.json <<'JSON'
{
  "paths_relative_to": "./",
  "artifacts": {
    "fixture": {
      "path": "artifact data.txt",
      "sha256": "fe8701d83d6161484abd97e21c482bb1a737641613cc429dc2f9f067f141a8d9"
    }
  }
}
JSON

pass=0 fail=0
expect() {
  local label="$1" want="$2" pattern="$3" output rc=0
  local test_cwd="${4:-$WORK}" lock_file="${5:-$WORK/lock.json}"
  output="$(cd "$test_cwd" && "$MANIFEST_SHELL" "$VERIFIER" "$lock_file" 2>&1)" || rc=$?
  if [ "$rc" -eq "$want" ] && printf '%s\n' "$output" | grep -qE "$pattern"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: expected exit %s, got %s\n%s\n' "$label" "$want" "$rc" "$output" >&2
  fi
}
reject() {
  jq "$2" valid.json > lock.json
  expect "$1" 2 '^invalid manifest artifacts:'
}

cp valid.json lock.json
expect 'valid lowercase hash and path with spaces' 0 'checked: 1 artifacts; failures: 0'
jq '.artifacts.fixture.sha256 |= ascii_upcase' valid.json > lock.json
expect 'valid uppercase hash' 0 'checked: 1 artifacts; failures: 0'
jq '.artifacts.second = .artifacts.fixture' valid.json > lock.json
expect 'all valid artifacts checked' 0 'checked: 2 artifacts; failures: 0'
jq --arg path "$WORK/artifact data.txt" '.artifacts.fixture.path = $path' valid.json > lock.json
expect 'valid absolute artifact path' 0 'checked: 1 artifacts; failures: 0'

# Distinct contents prove that an absolute declaration wins over the lock tree.
mkdir 'declared root'
cp 'artifact data.txt' 'declared root/artifact data.txt'
printf 'lock tree decoy\n' > 'artifact data.txt'
jq --arg root "$WORK/declared root" '.paths_relative_to = $root' valid.json > lock.json
expect 'existing explicit declared root' 0 'checked: 1 artifacts; failures: 0'
printf 'manifest fixture\n' > 'artifact data.txt'

reject 'null root' 'null'
reject 'array root' '[.]'
reject 'scalar root' '"invalid"'
reject 'missing artifacts' 'del(.artifacts)'
reject 'null artifacts' '.artifacts = null'
reject 'empty artifacts' '.artifacts = {}'
reject 'array artifacts' '.artifacts = []'
reject 'string artifacts' '.artifacts = "invalid"'
reject 'number artifacts' '.artifacts = 1'
reject 'boolean artifacts' '.artifacts = false'
reject 'null entry' '.artifacts.fixture = null'
reject 'array entry' '.artifacts.fixture = []'
reject 'string entry' '.artifacts.fixture = "invalid"'
reject 'empty entry' '.artifacts.fixture = {}'
reject 'invalid entry after valid entry' '.artifacts.second = null'
reject 'empty artifact name' '.artifacts = {"": .artifacts.fixture}'
reject 'tab in artifact name' '.artifacts = {"bad\tname": .artifacts.fixture}'
reject 'newline in artifact name' '.artifacts = {"bad\nname": .artifacts.fixture}'
reject 'missing path' 'del(.artifacts.fixture.path)'
reject 'null path' '.artifacts.fixture.path = null'
reject 'empty path' '.artifacts.fixture.path = ""'
reject 'number path' '.artifacts.fixture.path = 1'
reject 'array path' '.artifacts.fixture.path = []'
reject 'tab in path' '.artifacts.fixture.path = "bad\tpath"'
reject 'newline in path' '.artifacts.fixture.path = "bad\npath"'
reject 'carriage return in path' '.artifacts.fixture.path = "bad\rpath"'
reject 'NUL in path' '.artifacts.fixture.path = "bad\u0000path"'
reject 'missing hash' 'del(.artifacts.fixture.sha256)'
reject 'null hash' '.artifacts.fixture.sha256 = null'
reject 'empty hash' '.artifacts.fixture.sha256 = ""'
reject 'number hash' '.artifacts.fixture.sha256 = 1'
reject 'array hash' '.artifacts.fixture.sha256 = []'
reject 'short hash' '.artifacts.fixture.sha256 = ("a" * 63)'
reject 'long hash' '.artifacts.fixture.sha256 = ("a" * 65)'
reject 'non-hex hash' '.artifacts.fixture.sha256 = ("g" * 64)'
reject 'whitespace in hash' '.artifacts.fixture.sha256 = (("a" * 63) + " ")'

printf '{broken json\n' > lock.json
expect 'malformed JSON' 2 '^invalid manifest artifacts:'
: > lock.json
expect 'empty JSON input' 2 '^invalid manifest artifacts:'
cat valid.json valid.json > lock.json
expect 'multiple JSON documents' 2 '^invalid manifest artifacts:'

jq '.artifacts.fixture.sha256 = ("0" * 64)' valid.json > lock.json
expect 'well-formed hash with drift' 1 '^\[DRIFT\]'
cp valid.json lock.json
mv 'artifact data.txt' saved.txt
expect 'missing artifact' 1 '^\[MISSING\]'
mv saved.txt 'artifact data.txt'

selected="$WORK/selected tree"
caller="$WORK/caller decoy"
mkdir "$selected" "$caller"
printf 'manifest fixture\n' > "$selected/artifact.txt"
printf 'caller decoy\n' > "$caller/artifact.txt"
jq '.artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"

expect 'repo lock in repo cwd' 0 'checked: 2 artifacts; failures: 0' "$ROOT_DIR" "$ROOT_DIR/manifest.lock.json"
expect 'repo lock from another cwd' 0 'checked: 2 artifacts; failures: 0' "$caller" "$ROOT_DIR/manifest.lock.json"
expect 'selected tree from another cwd' 0 'checked: 1 artifacts; failures: 0' "$caller" "$selected/lock.json"
expect 'relative explicit lock with spaces' 0 'checked: 1 artifacts; failures: 0' "$caller" '../selected tree/lock.json'

printf 'selected drift\n' > "$selected/artifact.txt"
printf 'manifest fixture\n' > "$caller/artifact.txt"
expect 'caller cannot hide selected drift' 1 '^\[DRIFT\]' "$caller" "$selected/lock.json"
mv "$selected/artifact.txt" "$selected/saved.txt"
expect 'caller cannot hide selected missing file' 1 '^\[MISSING\]' "$caller" "$selected/lock.json"
mv "$selected/saved.txt" "$selected/artifact.txt"

mkdir "$selected/nested root" "$caller/nested root"
printf 'manifest fixture\n' > "$selected/nested root/artifact.txt"
printf 'caller nested decoy\n' > "$caller/nested root/artifact.txt"
jq '.paths_relative_to = "nested root" | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'relative declared root uses lock directory' 0 'checked: 1 artifacts; failures: 0' "$caller" "$selected/lock.json"
printf 'selected nested drift\n' > "$selected/nested root/artifact.txt"
printf 'manifest fixture\n' > "$caller/nested root/artifact.txt"
expect 'caller cannot hide relative declared drift' 1 '^\[DRIFT\]' "$caller" "$selected/lock.json"

printf 'manifest fixture\n' > "$selected/artifact.txt"
printf 'caller decoy\n' > "$caller/artifact.txt"
jq 'del(.paths_relative_to) | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'missing declaration uses lock directory' 0 'checked: 1 artifacts; failures: 0' "$caller" "$selected/lock.json"
printf 'selected drift\n' > "$selected/artifact.txt"
printf 'manifest fixture\n' > "$caller/artifact.txt"
expect 'missing declaration still detects drift' 1 '^\[DRIFT\]' "$caller" "$selected/lock.json"
printf 'manifest fixture\n' > "$selected/artifact.txt"
jq '.paths_relative_to = "" | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'empty declaration uses lock directory' 0 'checked: 1 artifacts; failures: 0' "$caller" "$selected/lock.json"

jq --arg root "$WORK/absent absolute root" '.paths_relative_to = $root | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'missing absolute root cannot fall back' 1 '^\[MISSING\]' "$caller" "$selected/lock.json"
jq '.paths_relative_to = "absent relative root" | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'missing relative root cannot fall back' 1 '^\[MISSING\]' "$caller" "$selected/lock.json"

jq --arg path "${WORK#/}/artifact data.txt" '.paths_relative_to = "/" | .artifacts.fixture.path = $path' valid.json > lock.json
expect 'filesystem root declaration is preserved' 0 'checked: 1 artifacts; failures: 0'

# A disposable directory below the real HOME permits a literal tilde declaration
# without overriding HOME or touching an installed context tree.
TILDE_ROOT="$(mktemp -d "$HOME/.katala-manifest-root-test.XXXXXX")"
printf 'manifest fixture\n' > "$TILDE_ROOT/artifact.txt"
printf 'selected decoy\n' > "$selected/artifact.txt"
jq --arg root "~${TILDE_ROOT#"$HOME"}" '.paths_relative_to = $root | .artifacts.fixture.path = "artifact.txt"' valid.json > "$selected/lock.json"
expect 'tilde root wins over lock tree' 0 'checked: 1 artifacts; failures: 0' "$caller" "$selected/lock.json"
printf 'tilde root drift\n' > "$TILDE_ROOT/artifact.txt"
printf 'manifest fixture\n' > "$selected/artifact.txt"
expect 'lock tree cannot hide tilde root drift' 1 '^\[DRIFT\]' "$caller" "$selected/lock.json"

printf 'manifest verifier test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
