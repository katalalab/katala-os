#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="${SCRIPT_DIR}/cli-dev-team-doctor.sh"
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.bun/bin:$HOME/.lmstudio/bin:/Applications/Codex.app/Contents/Resources:${PATH}:/opt/homebrew/bin:/usr/local/bin"

TARGET_DIR="${PWD}"
OUTPUT=""
STRICT=1
REQUIRE_READY=""
REQUIRE_KNOWN_PROBES=0
PARALLEL_TMUX_SOCKET="${PARALLEL_AI_TMUX_SOCKET:-$HOME/.local/state/parallel-ai-runtime/tmux.sock}"
LMSTUDIO_URL="${LMSTUDIO_URL:-http://127.0.0.1:1234}"

usage() {
  cat <<'EOF'
Usage: cli-dev-team-status.sh [options]

Generate machine-readable JSON status for the local CLI development team. It
runs cli-dev-team-doctor.sh, parses its TSV checks, and emits readiness booleans
for automation. It does not start services, edit config, log in, or run agents.

Options:
  --target PATH       Workspace path. Defaults to current directory.
  --output FILE       Also write JSON to FILE.
  --inventory         Run doctor without strict mode.
  --require NAME      Return nonzero unless ready.NAME is true.
                      NAME: core, readonly, write, or full.
  --require-known-probes
                     Return nonzero if any doctor row has an unknown or legacy
                     category/impact classification.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--target requires a path\n' >&2
        exit 2
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--output requires a path\n' >&2
        exit 2
      fi
      OUTPUT="$2"
      shift 2
      ;;
    --inventory)
      STRICT=0
      shift
      ;;
    --require-known-probes)
      REQUIRE_KNOWN_PROBES=1
      shift
      ;;
    --require)
      if [[ $# -lt 2 ]]; then
        printf 'arg\tfail\t--require requires core, readonly, write, or full\n' >&2
        exit 2
      fi
      REQUIRE_READY="$2"
      case "$REQUIRE_READY" in
        core|readonly|write|full)
          ;;
        *)
          printf 'arg\tfail\t--require must be core, readonly, write, or full: %s\n' "$REQUIRE_READY" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'arg\tfail\tunknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$DOCTOR" ]]; then
  printf 'doctor\tfail\tnot executable: %s\n' "$DOCTOR" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq\tfail\tjq not found\n' >&2
  exit 2
fi

doctor_tmp="$(mktemp "${TMPDIR:-/tmp}/cli-dev-team-doctor.XXXXXX")"
json_tmp="$(mktemp "${TMPDIR:-/tmp}/cli-dev-team-status.XXXXXX")"
cleanup() {
  rm -f "$doctor_tmp" "$json_tmp"
}
trap cleanup EXIT

doctor_rc=0
if [[ "$STRICT" -eq 1 ]]; then
  PARALLEL_AI_TMUX_SOCKET="$PARALLEL_TMUX_SOCKET" LMSTUDIO_URL="$LMSTUDIO_URL" "$DOCTOR" --strict --target "$TARGET_DIR" > "$doctor_tmp" || doctor_rc=$?
else
  PARALLEL_AI_TMUX_SOCKET="$PARALLEL_TMUX_SOCKET" LMSTUDIO_URL="$LMSTUDIO_URL" "$DOCTOR" --target "$TARGET_DIR" > "$doctor_tmp" || doctor_rc=$?
fi

awk 'index($0, "\t") > 0 { print }' "$doctor_tmp" | jq -Rn \
  --arg generated_at "$(date '+%Y-%m-%d %H:%M:%S %Z')" \
  --arg target "$TARGET_DIR" \
  --arg doctor "$DOCTOR" \
  --arg mode "$(if [[ "$STRICT" -eq 1 ]]; then printf strict; else printf inventory; fi)" \
  --argjson doctor_rc "$doctor_rc" '
    [inputs
      | split("\t")
      | select(length >= 3)
      | {
          name: .[0],
          status: .[1],
          detail: .[2],
          category: (.[3] // "legacy_unclassified"),
          impact: (.[4] // "legacy_unspecified")
        }
    ] as $checks
    | def check($n): ($checks[] | select(.name == $n)) // {name: $n, status: "missing", detail: ""};
      def ok($n): ((check($n).status) == "ok");
      def counts_by($field):
        reduce $checks[] as $check
          ({}; .[$check[$field]] = ((.[$check[$field]] // 0) + 1));
      def unknown_probe($check):
        (($check.category // "") as $category
          | ($check.impact // "") as $impact
          | ($category == "legacy_unclassified"
             or $category == "uncategorized"
             or $impact == "legacy_unspecified"
             or $impact == "read_only_probe"));
      def unknown_probes:
        [$checks[] | select(unknown_probe(.)) | {name, status, category, impact}];
      {
        generated_at: $generated_at,
        target: $target,
        mode: $mode,
        doctor: {
          command: $doctor,
          rc: $doctor_rc
        },
        ready: {
          core: ok("team.core_ready"),
          readonly: ok("team.readonly_ready"),
          write: ok("team.write_ready"),
          full: ok("team.full_ready")
        },
        summary: {
          core: check("team.core_ready"),
          readonly: check("team.readonly_ready"),
          write: check("team.write_ready"),
          full: check("team.full_ready")
        },
        probe_summary: {
          by_category: counts_by("category"),
          by_impact: counts_by("impact"),
          unknown_probe_count: (unknown_probes | length),
          unknown_probes: unknown_probes
        },
        notable: {
          lmstudio: {
            status: check("lmstudio.status"),
            api: check("lmstudio.api")
          },
          opencode: {
            auth: check("opencode.auth"),
            models: check("opencode.models")
          },
          antigravity: {
            models: check("antigravity.models"),
            plugins: check("antigravity.plugins")
          },
          tmux: {
            dedicated: check("tmux.parallel_socket"),
            default: check("tmux.default")
          },
          target: {
            git_status: check("target.git_status"),
            instructions: check("target.instructions")
          },
          support_cli: {
            go: check("support.go.version"),
            aider: check("support.aider.version"),
            gemini: check("support.gemini.version"),
            ollama: check("support.ollama.version"),
            cmux: check("support.cmux.version"),
            gh: check("support.gh.version"),
            gcloud: check("support.gcloud.version"),
            wrangler: check("support.wrangler.version"),
            vercel: check("support.vercel.version"),
            bun: check("support.bun.version"),
            node: check("support.node.version"),
            npm: check("support.npm.version"),
            uv: check("support.uv.version"),
            python3: check("support.python3.version"),
            op: check("support.op.version")
          }
        },
        checks: $checks
      }
  ' > "$json_tmp"

cat "$json_tmp"

if [[ -n "$OUTPUT" ]]; then
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$json_tmp" "$OUTPUT"
fi

if [[ -n "$REQUIRE_READY" ]]; then
  if ! jq -e --arg key "$REQUIRE_READY" '.ready[$key] == true' "$json_tmp" >/dev/null; then
    exit 1
  fi
fi

if [[ "$REQUIRE_KNOWN_PROBES" -eq 1 ]]; then
  if ! jq -e '.probe_summary.unknown_probe_count == 0' "$json_tmp" >/dev/null; then
    exit 1
  fi
fi

exit "$doctor_rc"
