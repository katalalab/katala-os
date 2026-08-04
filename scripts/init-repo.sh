#!/usr/bin/env bash
# init-repo.sh — bootstrap a new repo into Katala OS agent-context style.
# Copies templates with placeholder substitution, wires the shared pre-commit
# hook, optionally lays down the hash-locked subset (CONSTITUTION + manifest).
#
# Idempotent: existing files are backed up with retention (keep newest, prune >30d).
#
# Usage:
#   init-repo.sh <target-dir> [--name <repo>] [--description <text>] [--operator <name>]
#                              [--with-constitution] [--no-hooks-path] [--dry-run]
#
# Example:
#   ~/work/agent-context/scripts/init-repo.sh ~/work/my-new-repo \
#     --name my-new-repo --description "data export pipeline v2" \
#     --with-constitution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates"

usage() {
  sed -n '2,16p' "$0"
  exit 1
}

TARGET=""
REPO_NAME=""
REPO_DESCRIPTION=""
OPERATOR="${USER:-operator}"
WITH_CONSTITUTION=0
SET_HOOKS_PATH=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name)              REPO_NAME="$2"; shift 2 ;;
    --description)       REPO_DESCRIPTION="$2"; shift 2 ;;
    --operator)          OPERATOR="$2"; shift 2 ;;
    --with-constitution) WITH_CONSTITUTION=1; shift ;;
    --no-hooks-path)     SET_HOOKS_PATH=0; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           usage ;;
    -*)                  printf 'unknown flag: %s\n' "$1" >&2; usage ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"; shift
      else
        printf 'unexpected positional arg: %s\n' "$1" >&2; usage
      fi
      ;;
  esac
done

[ -z "$TARGET" ] && usage

TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")"
[ -z "$REPO_NAME" ] && REPO_NAME="$(basename "$TARGET")"
[ -z "$REPO_DESCRIPTION" ] && REPO_DESCRIPTION="<one-line description of $REPO_NAME>"

DATE="$(date +%Y-%m-%d)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

printf 'init-repo: target=%s\n' "$TARGET"
printf '           name=%s\n' "$REPO_NAME"
printf '           operator=%s\n' "$OPERATOR"
printf '           constitution=%s hooks-path=%s dry-run=%s\n\n' \
  "$WITH_CONSTITUTION" "$SET_HOOKS_PATH" "$DRY_RUN"

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$TARGET"

# Substitute {{REPO_NAME}}, {{REPO_DESCRIPTION}}, {{AGENT_CONTEXT_PATH}}, {{DATE}}, {{OPERATOR}}.
render() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    printf '  missing template: %s\n' "$src" >&2
    return 1
  fi

  if [ -e "$dst" ]; then
    local same=0
    local tmp
    tmp="$(mktemp)"
    sed \
      -e "s|{{REPO_NAME}}|$REPO_NAME|g" \
      -e "s|{{REPO_DESCRIPTION}}|$REPO_DESCRIPTION|g" \
      -e "s|{{AGENT_CONTEXT_PATH}}|$REPO_ROOT|g" \
      -e "s|{{DATE}}|$DATE|g" \
      -e "s|{{OPERATOR}}|$OPERATOR|g" \
      "$src" > "$tmp"
    if cmp -s "$tmp" "$dst"; then
      printf '  ok    %s (identical)\n' "$dst"
      rm -f "$tmp"
      return 0
    fi
    local backup="${dst}.bak.${TIMESTAMP}"
    printf '  backup %s -> %s\n' "$dst" "$backup"
    run mv "$dst" "$backup"
    if [ "$DRY_RUN" -eq 0 ]; then
      mv "$tmp" "$dst"
    else
      rm -f "$tmp"
    fi
  else
    printf '  create %s\n' "$dst"
    if [ "$DRY_RUN" -eq 0 ]; then
      sed \
        -e "s|{{REPO_NAME}}|$REPO_NAME|g" \
        -e "s|{{REPO_DESCRIPTION}}|$REPO_DESCRIPTION|g" \
        -e "s|{{AGENT_CONTEXT_PATH}}|$REPO_ROOT|g" \
        -e "s|{{DATE}}|$DATE|g" \
        -e "s|{{OPERATOR}}|$OPERATOR|g" \
        "$src" > "$dst"
    fi
  fi
}

# Core files (always written).
render "$TEMPLATES_DIR/AGENTS.md.tmpl"     "$TARGET/AGENTS.md"
render "$TEMPLATES_DIR/gitattributes.tmpl" "$TARGET/.gitattributes"
render "$TEMPLATES_DIR/gitignore.tmpl"     "$TARGET/.gitignore"
render "$TEMPLATES_DIR/NEEDS_REVIEW.md.tmpl" "$TARGET/NEEDS_REVIEW.md"

# Optional: hash-locked subset.
if [ "$WITH_CONSTITUTION" -eq 1 ]; then
  render "$TEMPLATES_DIR/CONSTITUTION.md.tmpl"    "$TARGET/CONSTITUTION.md"
  render "$TEMPLATES_DIR/manifest.lock.json.tmpl" "$TARGET/manifest.lock.json"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$TARGET/scripts"
  fi
  render "$TEMPLATES_DIR/verify.sh.tmpl" "$TARGET/scripts/verify.sh"
  [ "$DRY_RUN" -eq 0 ] && chmod +x "$TARGET/scripts/verify.sh"
fi

# Prune old backups (>30d) inside target. Keep newest 1 per filename.
if [ "$DRY_RUN" -eq 0 ] && [ -d "$TARGET" ]; then
  find "$TARGET" -maxdepth 4 -type f -name '*.bak.*' 2>/dev/null | while read -r bak; do
    base="${bak%.bak.*}"
    # delete this backup if older than 30 days AND a newer same-base backup exists
    if find "$base".bak.* -newer "$bak" 2>/dev/null | grep -q . && \
       find "$bak" -mtime +30 2>/dev/null | grep -q .; then
      printf '  prune  %s\n' "$bak"
      rm -f "$bak"
    fi
  done
fi

# Wire shared pre-commit hook.
if [ "$SET_HOOKS_PATH" -eq 1 ]; then
  if [ -d "$TARGET/.git" ]; then
    run git -C "$TARGET" config core.hooksPath "$REPO_ROOT/hooks"
    printf '  hooks  core.hooksPath -> %s/hooks\n' "$REPO_ROOT"
  else
    printf '  hooks  skipped (no .git in %s — run `git init` first, then re-run init-repo)\n' "$TARGET"
  fi
fi

printf '\ninit-repo: done.\n'
printf 'Next steps:\n'
printf '  1. cd %s && git init  (if not already)\n' "$TARGET"
printf '  2. Edit AGENTS.md (Layout / Build-test-lint / Verification).\n'
if [ "$WITH_CONSTITUTION" -eq 1 ]; then
  printf '  3. Compute hashes and update manifest.lock.json:\n'
  printf '       shasum -a 256 AGENTS.md CONSTITUTION.md\n'
  printf '  4. Run scripts/verify.sh — expect OK.\n'
fi
