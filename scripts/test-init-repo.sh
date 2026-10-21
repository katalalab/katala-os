#!/usr/bin/env bash
# Exercise literal template values and existing-file protection in owned fixtures.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INIT_SHELL="${INIT_REPO_TEST_BASH:-$BASH}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FILES=(AGENTS.md .gitattributes .gitignore NEEDS_REVIEW.md CONSTITUTION.md manifest.lock.json scripts/verify.sh)
TODAY="$(date +%Y-%m-%d)"
pass=0 fail=0 case_id=0

make_source() {
  local source="$1" template
  mkdir -p "$source/scripts" "$source/templates"
  cp "$ROOT_DIR/scripts/init-repo.sh" "$source/scripts/init-repo.sh"
  for template in AGENTS.md gitattributes gitignore NEEDS_REVIEW.md CONSTITUTION.md manifest.lock.json verify.sh; do
    printf 'name={{REPO_NAME}}\ndescription={{REPO_DESCRIPTION}}\ncontext={{AGENT_CONTEXT_PATH}}\ndate={{DATE}}\noperator={{OPERATOR}}\nrepeat={{REPO_NAME}}/{{REPO_NAME}}/{{OPERATOR}}\n' \
      > "$source/templates/$template.tmpl"
  done
}

invoke() {
  local source="$1" target="$2" name="$3" description="$4" operator="$5" output
  shift 5
  if ! output="$(TMPDIR="$WORK" "$INIT_SHELL" "$source/scripts/init-repo.sh" "$target" \
      --name "$name" --description "$description" --operator "$operator" \
      --with-constitution --no-hooks-path "$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
}

matches() {
  local target="$1" source="$2" name="$3" description="$4" operator="$5" file
  printf 'name=%s\ndescription=%s\ncontext=%s\ndate=%s\noperator=%s\nrepeat=%s/%s/%s\n' \
    "$name" "$description" "$source" "$TODAY" "$operator" "$name" "$name" "$operator" > "$WORK/expected"
  for file in "${FILES[@]}"; do
    if ! cmp -s "$WORK/expected" "$target/$file"; then
      printf 'output differs: %s\n' "$file" >&2
      return 1
    fi
  done
}

expect() {
  local label="$1"
  shift
  case_id=$((case_id + 1))
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$label" >&2
  fi
}

SOURCE="$WORK/source tree"
make_source "$SOURCE"

literal_case() {
  local value="$1" target="$WORK/target $case_id space"
  invoke "$SOURCE" "$target" "$value" "$value" "$value" || return 1
  matches "$target" "$SOURCE" "$value" "$value" "$value"
}

source_case() {
  local source="$WORK/$1" target="$WORK/target $case_id space"
  make_source "$source"
  invoke "$source" "$target" 'plain name' 'plain description' 'plain operator' || return 1
  matches "$target" "$source" 'plain name' 'plain description' 'plain operator'
}

empty_case() {
  local target="$WORK/empty defaults"
  invoke "$SOURCE" "$target" '' '' '' || return 1
  matches "$target" "$SOURCE" 'empty defaults' '<one-line description of empty defaults>' ''
}

no_backups() {
  [ -z "$(find "$1" -type f -name '*.bak.*' -print)" ]
}

identical_case() {
  local target="$WORK/identical target"
  invoke "$SOURCE" "$target" 'same value' 'same value' 'same value' || return 1
  invoke "$SOURCE" "$target" 'same value' 'same value' 'same value' || return 1
  matches "$target" "$SOURCE" 'same value' 'same value' 'same value' || return 1
  no_backups "$target"
}

backup_case() {
  local target="$WORK/backup target" file
  local value=$'changed & | \\value\nlast\\'
  invoke "$SOURCE" "$target" 'original' 'original' 'original' || return 1
  mkdir -p "$WORK/original/scripts"
  for file in "${FILES[@]}"; do cp "$target/$file" "$WORK/original/$file"; done
  invoke "$SOURCE" "$target" "$value" "$value" "$value" || return 1
  matches "$target" "$SOURCE" "$value" "$value" "$value" || return 1
  for file in "${FILES[@]}"; do
    set -- "$target/$file".bak.*
    if [ "$#" -ne 1 ] || [ ! -f "$1" ] || ! cmp -s "$WORK/original/$file" "$1"; then
      printf 'original backup differs: %s\n' "$file" >&2
      return 1
    fi
  done
}

dry_existing_case() {
  local target="$WORK/dry existing" file
  mkdir -p "$target/scripts"
  for file in "${FILES[@]}"; do printf 'owned existing file\n' > "$target/$file"; done
  invoke "$SOURCE" "$target" 'dry & | \name' $'dry\ntext' '' --dry-run || return 1
  printf 'owned existing file\n' > "$WORK/existing"
  for file in "${FILES[@]}"; do cmp -s "$WORK/existing" "$target/$file" || return 1; done
  no_backups "$target"
}

dry_new_case() {
  local target="$WORK/dry new"
  invoke "$SOURCE" "$target" 'dry & | \name' $'dry\ntext' '' --dry-run || return 1
  [ ! -e "$target" ]
}

expect 'plain values and multiple placeholders' literal_case 'plain value'
expect 'ampersand' literal_case 'left & right'
expect 'sed delimiter' literal_case 'left|right'
expect 'backslash sequences' literal_case 'literal \1 \n \t'
expect 'embedded newline' literal_case $'first\nsecond'
expect 'trailing newlines' literal_case $'first\n\n'
expect 'trailing backslash' literal_case $'trailing\\'
expect 'combined metacharacters' literal_case $'A & B | C\\D\nlast\\'
expect 'empty values retain defaults and empty operator' empty_case
expect 'source path with ampersand' source_case 'source & tree'
expect 'source path with delimiter' source_case 'source | tree'
expect 'source path with backslash' source_case 'source \ tree'
expect 'source path with newline' source_case $'source\n tree'
expect 'identical existing files create no backups' identical_case
expect 'changed files preserve original backups' backup_case
expect 'dry run preserves existing files' dry_existing_case
expect 'dry run creates no target' dry_new_case

printf 'init-repo literal test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
