#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root/bin/agent-review-after-change"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local target="$1"
  mkdir -p "$target/src" "$target/docs"
  git -C "$target" init -q
  git -C "$target" config user.email test@example.invalid
  git -C "$target" config user.name test
  printf 'export const stable = true;\n' > "$target/src/stable.ts"
  git -C "$target" add .
  git -C "$target" commit -qm baseline
}

review_repo="$tmp/review"
make_repo "$review_repo"
printf 'export const feature = 1;\n' > "$review_repo/src/feature-a.ts"
printf 'export const feature = 2;\n' > "$review_repo/src/feature-b.ts"
printf '# Feature\n' > "$review_repo/docs/feature.md"
review_output="$(bash "$runner" --dir "$review_repo" --dry-run)"
grep -qx 'REVIEW_STATUS=READY' <<< "$review_output"
grep -qx 'REVIEW_TRIGGER=implementation-slice' <<< "$review_output"

small_repo="$tmp/small"
make_repo "$small_repo"
printf '# Typo\n' > "$small_repo/docs/typo.md"
small_output="$(bash "$runner" --dir "$small_repo" --dry-run)"
grep -qx 'REVIEW_STATUS=SKIP_SMALL_CHANGE' <<< "$small_output"

secret_repo="$tmp/secret"
make_repo "$secret_repo"
printf 'token=not-a-real-secret\n' > "$secret_repo/id_ed25519_test"
set +e
bash "$runner" --dir "$secret_repo" --dry-run > "$tmp/secret.out"
secret_status=$?
set -e
[[ "$secret_status" -eq 3 ]]
grep -qx 'REVIEW_STATUS=MANUAL_SECRET_BOUNDARY' "$tmp/secret.out"

delete_repo="$tmp/delete"
make_repo "$delete_repo"
printf 'export const deleted = true;\n' > "$delete_repo/src/delete.ts"
git -C "$delete_repo" add .
git -C "$delete_repo" commit -qm add-delete-target
git -C "$delete_repo" rm -q src/delete.ts
delete_output="$(bash "$runner" --dir "$delete_repo" --dry-run)"
grep -qx 'REVIEW_STATUS=SKIP_SMALL_CHANGE' <<< "$delete_output"

invalid_repo="$tmp/invalid"
make_repo "$invalid_repo"
printf 'export const feature = 1;\n' > "$invalid_repo/src/feature-a.ts"
printf 'export const feature = 2;\n' > "$invalid_repo/src/feature-b.ts"
printf '# Feature\n' > "$invalid_repo/docs/feature.md"
mkdir -p "$tmp/fake-bin"
printf '#!/usr/bin/env bash\nout=""; while [[ $# -gt 0 ]]; do [[ "$1" = "--output-last-message" ]] && { out="$2"; shift 2; continue; }; shift; done; printf "not structured\\n" > "$out"\n' > "$tmp/fake-bin/codex"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$CLAUDE_REVIEW_ARGS_FILE"\nprintf "not structured\\n"\n' > "$tmp/fake-bin/claude"
chmod +x "$tmp/fake-bin/codex" "$tmp/fake-bin/claude"
set +e
PATH="$tmp/fake-bin:$PATH" CLAUDE_REVIEW_ARGS_FILE="$tmp/claude-args" \
  bash "$runner" --dir "$invalid_repo" --force --engines codex,claude > "$tmp/invalid.out"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 4 ]]
grep -qx 'REVIEWER=codex MODEL=gpt-5.6-sol STATUS=INVALID_VERDICT' "$tmp/invalid.out"
grep -qx 'REVIEWER=claude MODEL=opus STATUS=INVALID_VERDICT' "$tmp/invalid.out"
grep -qx 'dontAsk' "$tmp/claude-args"
grep -qx 'Read,Glob,Grep,Bash' "$tmp/claude-args"
! grep -qx 'plan' "$tmp/claude-args"

echo 'agent-review-after-change tests: PASS'
