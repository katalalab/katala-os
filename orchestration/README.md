# Orchestration — Claude as lead, external CLIs as headless subagents

Lets Claude Code orchestrate **GPT (Codex), Cursor CLI, OpenCode, and Antigravity (agy)** as headless
subagents, with an always-on posture. Fleet-distributed via this repo (`git pull` + installer).

## Components

- `bin/agent-dispatch` — unified headless dispatcher. `agent-dispatch <gpt|claude|cursor|opencode|antigravity|grok> --dir D [--read-only] [--model M] [--timeout S] -- "<prompt>"`. Returns the engine's final answer on stdout. The `claude` backend is the reverse direction (another engine — typically Codex via its `ask-claude` skill — calling Claude Code headless on the Max subscription); the callee must not re-dispatch.
- `bin/agent-review-after-change` — post-implementation adversarial review gate. It skips small changes, refuses secret-bearing diffs, and runs independent read-only Codex, Claude Code, and Antigravity reviews for eligible code-plus-documentation changes.
- `bin/agent-handoff` — GUI handoff path for desktop-only flows; `agent-dispatch antigravity` now covers Antigravity headlessly.
- `agents/*.md` — Claude Code subagent definitions (`Task` `subagent_type` = gpt/cursor/opencode/antigravity). Thin Bash proxies to `agent-dispatch`.
- `hooks/orchestration-context[.ps1]` — SessionStart hook injecting the orchestration posture; advertises only engines installed on that node.
- The routing/consensus policy lives in the `agent-orchestration` skill (synced via `agent-skills-private`).

## Install / update on a node

```bash
cd ~/work/agent-context && git pull
./orchestration/install.sh         # macOS / Linux / git-bash / WSL
# Windows (native): pwsh -File orchestration/install.ps1
```

Idempotent. Then **restart the Claude session** (subagents and the hook load at session start).
The dispatcher and hook auto-detect which engines exist on the node, so a missing CLI is simply
not advertised — no per-node editing needed.

## Post-implementation adversarial review

Run this after implementation and its focused tests, before asking for a merge
or declaring a risky change ready. It deliberately does **not** review small
changes. A review starts for a high-risk path, at least three changed files with
two code files, or 120+ changed lines alongside source code. `--force` starts a
review regardless of the threshold.

```bash
agent-review-after-change --dir /path/to/repo
agent-review-after-change --dir /path/to/repo --force --report-dir .review/adversarial
# Windows PowerShell
& "$HOME/bin/agent-review-after-change.ps1" --dir C:\path\to\repo
```

The default gate runs all three independent model families: Codex
(`gpt-5.6-sol` by default), Claude (`opus`), and Antigravity (`agy` built-in). At least two
engines are required when using `--engines` for an intentionally scoped review.
Override those model aliases through `CODEX_REVIEW_MODEL`, `CLAUDE_REVIEW_MODEL`,
and `ANTIGRAVITY_REVIEW_MODEL` when a node's entitlement differs. It runs each CLI in
its read-only mode; Claude uses `dontAsk` with read tools only, avoiding Plan Mode's
automatic files under `~/.claude/plans/`. An unavailable reviewer, timeout, malformed verdict, or
request for changes returns non-zero and is never interpreted as approval.

Do not use `--report-dir` where model output could be sensitive: it persists
review text. Default output is transient and is only written to the terminal.

## Claude Backend Permission Model

Claude Code uses `--permission-mode bypassPermissions` for write-capable orchestration. `agent-dispatch claude --read-only` instead uses `dontAsk`, exposes only `Read`, `Glob`, `Grep`, and `Bash`, and disables session persistence. This keeps headless repository review fail-closed without Plan Mode's automatic writes under `~/.claude/plans/`. Other backends use their own read-only modes: Codex/GPT uses its read-only sandbox, Cursor uses ask mode, and Antigravity uses plan mode.

## Frontier models (local cheat sheet)

Operator catalog: `~/work/docs/frontier-models/latest.md` (evidence: `~/work/docs/official-docs-evidence/frontier-models-2026-07-31.md`).

- Codex everyday: `gpt-5.6-terra` (this node's `~/.codex/config.toml` default). Hard review: `gpt-5.6-sol`. Cheap/bulk: `gpt-5.6-luna`.
- Claude lead: `opus[1m]` (this node's Claude default). Fast: `sonnet` / `haiku`. Costly flagship: `fable[1m]` (reserve).
- Cursor: pass IDs from `cursor-agent models` (e.g. `gpt-5.6-sol-medium`, `claude-opus-5-thinking-high`). Fable via Cursor is **NO ZDR**.
- Antigravity: `agy models` (Gemini 3.6 Flash / Claude / gpt-oss). Gemini CLI itself is retired — Google seat is `agy`.
- Override per call: `agent-dispatch <backend> --model <id> ...`. Do not silently change machine defaults.

## Notes

- Default mode is full/non-interactive (writes allowed), matching the fleet high-autonomy posture. `--read-only` for review/opinion/consensus.
- Parallel writes: never let two engines touch the same file/dir/module; declare ownership (see skill).
- Always verify a delegated result before reporting done.
- Antigravity (`agy`) runs headless and is the Google-perspective seat. Headless runs need `--dangerously-skip-permissions` (or a `permissions.allow` rule), otherwise every tool call is auto-denied and the run returns empty.
