#!/usr/bin/env bash
# verify-manifest.sh — macOS/Linux drift checker for agent-context artifacts.
# Read-only. Non-zero exit on mismatch. Mirrors Test-FleetMirrorFreshness.ps1.
#
# Usage: scripts/verify-manifest.sh [path/to/manifest.lock.json]
# Default: ~/work/agent-context/manifest.lock.json

set -euo pipefail

LOCK_PATH="${1:-$HOME/work/agent-context/manifest.lock.json}"

if [ ! -f "$LOCK_PATH" ]; then
  printf 'lock file missing: %s\n' "$LOCK_PATH" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq required but not found on PATH\n' >&2
  exit 2
fi

if command -v shasum >/dev/null 2>&1; then
  hash_sha256() {
    shasum -a 256 "$1" | awk '{print toupper($1)}'
  }
elif command -v sha256sum >/dev/null 2>&1; then
  hash_sha256() {
    sha256sum "$1" | awk '{print toupper($1)}'
  }
elif command -v openssl >/dev/null 2>&1; then
  hash_sha256() {
    openssl dgst -sha256 "$1" | awk '{print toupper($NF)}'
  }
else
  printf 'SHA-256 tool required but not found on PATH\n' >&2
  exit 2
fi

# A failing process substitution does not fail its parent loop. Validate and
# extract every row in a checked command before attempting any artifact hashes.
if ! ARTIFACTS=$(jq -ers '
  def field: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
  select(length == 1)
  | .[0] | select(type == "object")
  | .artifacts | select(type == "object" and length > 0)
  | to_entries
  | select(all(.[];
      (.key | field)
      and (.value | type == "object"
        and (.path | field)
        and (.sha256 | field and test("^[0-9A-Fa-f]{64}$")))))
  | .[] | "\(.key)\t\(.value.path)\t\(.value.sha256)"
' "$LOCK_PATH" 2>/dev/null); then
  printf 'invalid manifest artifacts: %s\n' "$LOCK_PATH" >&2
  exit 2
fi

ROOT_DIR=$(dirname "$LOCK_PATH")
DECLARED=$(jq -r '.paths_relative_to // ""' "$LOCK_PATH")
if [ -n "$DECLARED" ]; then
  case "$DECLARED" in
    "~"*) DECLARED="$HOME${DECLARED#\~}" ;;
  esac
  # Resolve declarations against the lock, never the caller or a fallback tree.
  case "$DECLARED" in
    /*) ROOT_DIR="$DECLARED" ;;
    *)  ROOT_DIR="$ROOT_DIR/$DECLARED" ;;
  esac
fi

FAILURES=0
CHECKS=0

while IFS=$'\t' read -r name rel expected; do
  CHECKS=$((CHECKS + 1))
  case "$rel" in
    /*) abs="$rel" ;;
    *)  abs="$ROOT_DIR/$rel" ;;
  esac

  if [ ! -f "$abs" ]; then
    printf '[MISSING] %s -> %s\n' "$name" "$abs"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  actual=$(hash_sha256 "$abs")
  expected_uc=$(printf '%s' "$expected" | tr -d '\r' | tr '[:lower:]' '[:upper:]')
  if [ "$actual" = "$expected_uc" ]; then
    : # ok
  else
    printf '[DRIFT]   %s\n' "$name"
    printf '          path:     %s\n' "$abs"
    printf '          expected: %s\n' "$expected_uc"
    printf '          actual:   %s\n' "$actual"
    FAILURES=$((FAILURES + 1))
  fi
done <<< "$ARTIFACTS"

printf '\nchecked: %d artifacts; failures: %d\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -gt 0 ]; then
  printf '\nDrift response (per manifest.lock.json):\n  '
  jq -r '.drift_response // "no drift_response declared"' "$LOCK_PATH"
  exit 1
fi
exit 0
