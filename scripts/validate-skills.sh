#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
status=0
count=0

while IFS= read -r -d '' skill_file; do
  count=$((count + 1))

  if [[ -L "$skill_file" && ! -e "$skill_file" ]]; then
    echo "broken symlink: $skill_file" >&2
    status=1
    continue
  fi

  if ! awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { frontmatter_closed = 1; exit }
    in_frontmatter && $0 ~ /^name[[:space:]]*:/ { has_name = 1 }
    in_frontmatter && $0 ~ /^description[[:space:]]*:/ { has_description = 1 }
    END { exit !(frontmatter_closed && has_name && has_description) }
  ' "$skill_file"; then
    echo "invalid SKILL.md frontmatter (requires name and description): $skill_file" >&2
    status=1
  fi
done < <(find "$ROOT_DIR" -name SKILL.md -not -path '*/.git/*' -print0)

if [[ "$count" -eq 0 ]]; then
  echo "No SKILL.md files found under $ROOT_DIR"
elif [[ "$status" -eq 0 ]]; then
  echo "Skill validation passed: $count file(s)"
fi

exit "$status"
