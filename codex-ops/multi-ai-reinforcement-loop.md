# Multi-AI Reinforcement Loop

Date: 2026-06-28 JST

This loop coordinates Codex, Claude, Cursor, Antigravity, GitHub Copilot, Oracle, GitHub, Google Drive, OpenAI docs, agmsg, Superpowers, and local Skills without doing local model RLHF.

## Definition

RLHF here means an operational feedback loop:

1. Capture task outcomes and review findings.
2. Normalize them into constraints, preferences, antipatterns, and verification gates.
3. Score results with the Codex Ops rubric.
4. Add safe evidence to evals, runbooks, skill guidance, or approval packets.
5. Reuse those assets in later sessions.

It does not mean training model weights or running reward-model training locally.

## Current Safe Loop

- Lead: Codex.
- Messaging: agmsg via scripts only.
- Codex docs: official manual and OpenAI docs MCP.
- Review: CLI `/review`, GitHub issue/PR review, Oracle dry-run/browser/API only when scoped.
- Superpowers: use planning, parallel dispatch, subagent-driven development, and verification skills as process guidance.
- GitHub: read first; issue/PR comments only when sanitized and relevant.
- Google Drive: metadata or explicit user-selected docs only; no broad file/body sweeps.
- Antigravity: GUI handoff only unless a headless CLI becomes available.
- GitHub Copilot: IDE-local assistant surface; do not treat it as a headless loop participant.

## Fanout Policy

The user may request unlimited subagents, but local resource evidence shows Codex/MCP/helper pressure. The operational policy is bounded fanout:

- normal: 1-3 read-only agents;
- implementation: disjoint write scopes only;
- external writes: approval required;
- process cleanup, auth, MCP, hooks, global config, GitHub publication, Google Drive writes: approval required;
- stop and refresh the control board if monitor or lease gates report attention.

## First Verifier

Run:

```sh
python3 $HOME/work/docs/scripts/agent-reinforcement-loop-board.py --format md
```

Expected outcome:

- writes a board under `$HOME/work/docs/agent-team-design/evidence/reinforcement-loop-board/`;
- confirms agmsg identity, core CLI surfaces, Codex Ops loop docs, participant board, and control board;
- records incomplete requirements instead of silently broadening scope.

## Feedback Ledger

Run:

```sh
python3 $HOME/work/docs/scripts/agent-reinforcement-feedback-ledger.py --format md
```

The ledger scores feedback events by signal strength, actionability, privacy risk, and public shareability. It is the current handoff point from raw measurements into the operational feedback loop.

Current event classes:

- Codex performance deltas between normal and clean `CODEX_HOME`.
- Local Codex state pressure that may need backup-first maintenance before experiments.
- GitHub issue/comment sharing status.
- agmsg local coordination status.
- Google Drive connector reachability, metadata-only by default.
- Oracle dry-run readiness for second-model review without model spend or browser control.

Do not paste raw logs, full machine inventory, connector body content, tokens, hostnames, emails, or local path dumps into the ledger or public issue comments.

## Promotion Rule

A tool can be promoted from "available" to "loop participant" only when all are true:

- it has a non-secret invocation path;
- it has a bounded output contract;
- its writes are disabled or explicitly approved;
- its result is verified by the main agent;
- residual risks are recorded in the board or runbook.
