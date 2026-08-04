# Katala OS — an agent operating discipline

A constitution-driven operating discipline for running coding agents (Claude Code, Codex CLI, Cursor, OpenCode, Antigravity) across several machines without the rules quietly rotting.

This is the sanitized open-source cut of a setup that runs a real multi-machine, multi-engine development fleet. Fleet-specific data — hostnames, addresses, host inventories, operational logs — is deliberately absent: what is published here is the **shape**, not one instance of it.

## The problem it solves

Agent instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) drift. They get edited by the agents they govern, duplicated per machine, and silently contradict each other. Meanwhile the rules that actually matter — never expose secrets, never mutate state without a second opinion, always leave a rollback — are mixed in with hundreds of lines of situational detail, so nothing is authoritative.

The approach here separates the two:

- **`CONSTITUTION.md`** is a deliberately narrow set of non-negotiable rules that **never drifts**. It is hash-locked. If any other file contradicts it, the constitution wins and the other file is wrong. Changing a constitutional rule requires a signed, dated commit to that file alone.
- **The baseline** (`AGENTS.md`) holds everything else, and is mirrored to every agent's expected filename by **symlink from one canonical source** — no copies, so no divergence.
- **Drift is detected, not hoped away.** `manifest.lock.json` records expected hashes; the verifier fails the session start when the constitution has changed without ratification.

## What's in the box

| Component | What it does |
| --- | --- |
| `CONSTITUTION.md` | The hash-locked, non-negotiable subset. Three unwritten rules + operating defaults. |
| `AGENTS.MD` | The baseline that gets mirrored to every agent's filename. Ships as a **fictional example** — rewrite it for your own environment. |
| `AGENTS-COMMUNICATION.md` | The operator↔agent communication contract: goal contracts, how to read terse instructions, when to ask vs. proceed. |
| `templates/` | Fill-in-the-blank versions of every governing file (`{{PLACEHOLDER}}` variables), so a new repo or a new machine starts compliant. |
| `hooks/` | `PreToolUse` safety valves for shell commands, plus a `pre-commit` gate that blocks staged secrets (`.env`, `*.pem`, high-confidence key patterns) and validates JSON config syntax. |
| `orchestration/` | `agent-dispatch` — run GPT/Codex, Cursor, OpenCode, or Antigravity as headless subagents from whichever agent is leading, with read-only modes and per-engine adapters. |
| `scripts/` | Bootstrap (macOS/Windows), the drift verifiers, skill validation, and repo initialization. |
| `codex-ops/` | Operating policy: architecture, anti-patterns, guardrails, runbooks (log retention, settings changes, long-running jobs), and evaluation cases. |
| `skills/` | Reusable agent skills (repo init, GitHub review/triage, goal contracts, skill hygiene). |

## Quick start

Requires `bash`, `git`, and `jq`. The clone path matters: the verifiers default to
`~/work/agent-context`.

```bash
git clone https://github.com/katalalab/katala-os ~/work/agent-context
cd ~/work/agent-context
$EDITOR AGENTS.MD          # ships as a fictional example — rewrite it for your machines first
./scripts/bootstrap.sh     # symlinks ~/CLAUDE.md, ~/AGENTS.md, ~/GEMINI.md to AGENTS.MD
./scripts/verify.sh        # hash-lock check + skill validation
```

`bootstrap.sh` backs up any existing file at those three paths before replacing it (under
`~/.local/state/agent-context-backups/`, five generations) — but read it before running it, since
it does write to your home directory.

Windows needs Developer Mode enabled, because the mirror uses symlinks rather than copies:

```powershell
pwsh -File .\scripts\bootstrap.ps1
pwsh -File .\scripts\Test-FleetMirrorFreshness.ps1
```

`AGENTS.MD` is deliberately **not** hash-locked — it is meant to evolve as your setup does. Only
`CONSTITUTION.md` and `AGENTS-COMMUNICATION.md` are recorded in `manifest.lock.json`; editing
either one fails `verify.sh` until you update the recorded hash in the same commit, which is the
whole point: an agent cannot quietly rewrite the rules it is governed by.

## Ideas worth stealing even if you don't adopt the whole thing

- **A constitution that outranks everything, and is small enough to actually hold.** Most agent setups have one giant instruction file where every line has equal weight, which means none of them do.
- **Symlink mirroring instead of copies.** One canonical file, N expected filenames. Divergence becomes structurally impossible instead of merely discouraged.
- **Hash-locked drift detection at session start.** A changed constitution blocks write work until a human ratifies it — the agent cannot quietly rewrite its own rules.
- **Multi-agent consensus before destructive change.** Runtime, auth, or state mutation requires a read-only second opinion from a *different* engine over the same scope. Dissent escalates to a review file; it is never silently overridden.
- **Blast-radius gating for parallel agents.** Count expected file changes before dispatch; declare file/directory ownership explicitly; never let two write-capable agents touch the same file or state at once.
- **Backups must declare a retention rule.** If no retention rule fits, don't create the backup — otherwise you've built a disk-filling machine with extra steps.

## Scope and honesty

This is one operator's working system, published because the patterns generalize — not a framework with a stable API. Expect to fork and edit rather than configure. The `codex-ops/` policy documents in particular encode choices (high-autonomy inside trusted project roots, specific log-retention caps) that you should re-decide for your own environment rather than inherit.

## License

MIT. See [LICENSE](LICENSE).
