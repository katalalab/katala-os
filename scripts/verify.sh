#!/usr/bin/env bash
# Repo-local GitHub Flow verifier. Keep this thin; the hash contract lives in verify-manifest.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/verify-manifest.sh" "$ROOT_DIR/manifest.lock.json"
"$ROOT_DIR/scripts/validate-skills.sh" "$ROOT_DIR"
