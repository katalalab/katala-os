#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: backup-asset-index.sh <backup-root> [output-dir]

Build a metadata-only index for a high-value backup tree.
The script does not move or delete backup data. It writes:

- README.md
- asset-map.tsv
- sqlite-integrity.tsv
- restore-checklist.md

The index intentionally records paths, sizes, counts, and integrity status only.
It does not copy secrets or print file contents.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

ROOT=$1
OUT=${2:-"$ROOT/_index"}

if [[ ! -d "$ROOT" ]]; then
  printf 'backup root not found: %s\n' "$ROOT" >&2
  exit 1
fi

mkdir -p "$OUT"

CREATED_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ASSET_MAP="$OUT/asset-map.tsv"
SQLITE_REPORT="$OUT/sqlite-integrity.tsv"
README="$OUT/README.md"
RESTORE="$OUT/restore-checklist.md"
CATEGORY_DIR="$OUT/by-category"

path_status() {
  local path=$1
  if [[ -e "$path" ]]; then
    printf 'present'
  else
    printf 'missing'
  fi
}

approx_kib() {
  local path=$1
  if [[ -e "$path" ]]; then
    du -sk "$path" 2>/dev/null | awk '{print $1}'
  else
    printf '0'
  fi
}

entry_count() {
  local path=$1
  if [[ -d "$path" ]]; then
    find "$path" -mindepth 1 2>/dev/null | wc -l | tr -d ' '
  elif [[ -f "$path" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

add_asset() {
  local category=$1
  local rel_path=$2
  local note=$3
  local full_path="$ROOT/$rel_path"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$category" \
    "$rel_path" \
    "$(path_status "$full_path")" \
    "$(approx_kib "$full_path")" \
    "$(entry_count "$full_path")" \
    "$note" >> "$ASSET_MAP"
}

{
  printf 'category\trelative_path\tstatus\tapprox_kib\tentry_count\tnote\n'
  add_asset control '_logs' 'run logs, target list, final reports'
  add_asset control '_repair-backups' 'pre-repair rollback copies'
  add_asset control '_repair-work' 'generated repair work products'
  add_asset control '_index' 'generated backup index'
  add_asset user-data 'home/Desktop' 'desktop files'
  add_asset user-data 'home/Documents' 'documents'
  add_asset user-data 'home/Downloads' 'downloads'
  add_asset media 'home/Pictures' 'photos and image libraries'
  add_asset media 'home/Movies' 'video projects and movies'
  add_asset media 'home/Music' 'music and audio assets'
  add_asset development 'home/work' 'working docs, fleet tools, project data'
  add_asset development 'home/work/docs' 'AI Dev OS docs and evidence'
  add_asset development 'home/work/agent-context' 'shared agent context framework'
  add_asset development 'home/work/fleet' 'fleet SSH and maintenance tools'
  add_asset agent-state 'home/.codex' 'Codex config, sessions, plugin cache, sqlite state'
  add_asset agent-state 'home/.claude' 'Claude config and sessions'
  add_asset credentials-local-only 'home/.ssh' 'SSH public/private material; do not publish'
  add_asset app-state 'home/Library/Preferences' 'macOS preferences'
  add_asset app-state 'home/Library/Application Support' 'application support data'
  add_asset app-state 'home/Library/Group Containers' 'group container state'
  add_asset app-state 'home/Library/Containers' 'container state'
  add_asset communications 'home/Library/Mail' 'local mail data'
  add_asset communications 'home/Library/Messages' 'local messages data'
} > "$ASSET_MAP"

ICLOUD_DIR=$(find "$ROOT/home" -maxdepth 1 -type d -name 'iCloud Drive*' 2>/dev/null | head -n 1 || true)
if [[ -n "$ICLOUD_DIR" ]]; then
  rel=${ICLOUD_DIR#"$ROOT/"}
  add_asset cloud-archive "$rel" 'local iCloud archive directory'
fi

mkdir -p "$CATEGORY_DIR"
awk -F '\t' 'NR > 1 {print $1}' "$ASSET_MAP" | sort -u | while IFS= read -r category; do
  mkdir -p "$CATEGORY_DIR/$category"
  {
    printf '# %s\n\n' "$category"
    printf '| relative_path | status | approx_kib | entry_count | note |\n'
    printf '| --- | --- | ---: | ---: | --- |\n'
    awk -F '\t' -v category="$category" '
      NR > 1 && $1 == category {
        printf "| `%s` | %s | %s | %s | %s |\n", $2, $3, $4, $5, $6
      }
    ' "$ASSET_MAP"
  } > "$CATEGORY_DIR/$category/README.md"
done

{
  printf 'status\tpath\tdetail\n'
  if command -v sqlite3 >/dev/null 2>&1 && [[ -d "$ROOT/home/.codex" ]]; then
    while IFS= read -r -d '' db; do
      detail=$(sqlite3 "$db" 'pragma integrity_check;' 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
      if [[ "$detail" == "ok" ]]; then
        printf 'OK\t%s\t%s\n' "${db#"$ROOT/"}" "$detail"
      else
        printf 'BAD\t%s\t%s\n' "${db#"$ROOT/"}" "$detail"
      fi
    done < <(find "$ROOT/home/.codex" -type f \( -name '*.sqlite' -o -name '*.db' \) -print0 2>/dev/null)
  else
    printf 'SKIP\thome/.codex\tsqlite3 missing or Codex tree missing\n'
  fi
} > "$SQLITE_REPORT"

{
  printf '# Backup Asset Index\n\n'
  printf 'generated_utc: %s\n\n' "$CREATED_UTC"
  printf 'backup_root: `%s`\n\n' "$ROOT"
  printf '## Files\n\n'
  printf '%s\n' '- `asset-map.tsv`: category, relative path, presence, approximate KiB, entry count, and note.'
  printf '%s\n' '- `sqlite-integrity.tsv`: `pragma integrity_check` for Codex SQLite/DB files.'
  printf '%s\n' '- `restore-checklist.md`: restore order and safety notes.'
  printf '%s\n\n' '- `by-category/`: generated category hierarchy for restore navigation.'
  printf '## Rules\n\n'
  printf '%s\n' '- This index is metadata only; it must not include raw secrets, tokens, cookies, or DB contents.'
  printf '%s\n' '- Treat `credentials-local-only` and agent state as local restore material, not GitHub material.'
  printf '%s\n' '- If SQLite integrity reports `BAD`, repair by preserving the broken files first, then replace from a healthy source using `sqlite3 .backup`.'
} > "$README"

{
  printf '# Restore Checklist\n\n'
  printf 'Use this as a restore order, not as an automatic restore script.\n\n'
  printf '1. Confirm the destination machine and operator intent.\n'
  printf '2. Restore documents and project trees first: `home/work`, `home/Documents`, media folders as needed.\n'
  printf '3. Restore agent framework docs: `home/work/agent-context`, `home/work/docs`, `home/work/fleet`.\n'
  printf '4. Restore app state selectively; avoid overwriting live app data blindly.\n'
  printf '5. Restore SQLite DBs only after `pragma integrity_check` reports `ok`.\n'
  printf '6. Restore SSH/auth material manually and verify permissions before use.\n'
  printf '7. Run the narrow verifier for each restored system before declaring completion.\n'
} > "$RESTORE"

printf 'index_dir=%s\n' "$OUT"
printf 'asset_map=%s\n' "$ASSET_MAP"
printf 'sqlite_report=%s\n' "$SQLITE_REPORT"
