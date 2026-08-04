# Codex Ops Architecture

## Executive Summary

The recommended design is a two-layer local operating model:

1. Agent Package layer: package Codex capabilities and task-specific context into versioned, reviewable units.
2. Control Plane layer: govern which packages can run, with what permissions, what preflight checks, and what completion evidence.

This mirrors the useful parts of Microsoft-style APM and Agent 365 without recreating an enterprise platform locally.

## Microsoft-Inspired Mapping

| Microsoft-style concept | Local Codex equivalent | Local artifact |
|---|---|---|
| Agent package | Bundle of skills, prompts, MCP needs, env assumptions, hooks, evals | `packages/<name>/manifest.yaml` |
| Package lock | Resolved paths, plugin versions, tool versions, hashes | future `package-lock.yaml` |
| Agent registry | Known local agent roles and allowed use cases | `inventory.md`, package manifests |
| Control plane | Policies, preflights, audit, evals | `policies/*.yaml`, `hooks-and-guardrails.md` |
| Conditional access | Task-specific permission and confirmation rules | policy `risk_level`, `requires_confirmation` |
| Observability | tmux session state, logs, command summaries, final reports | audit logs and runbooks |
| Evaluation | Regression cases and preference pairs | `evals/*.yaml`, `evals/*.jsonl` |

## Local Package Model

Each package should answer five questions:

- What task family does this package support?
- Which skills, plugins, MCP tools, and shell commands are expected?
- Which paths may be read or written?
- What must be checked before and after work?
- What counts as successful completion?

Minimal package layout:

```text
packages/<package-name>/
  manifest.yaml
  README.md
  evals.yaml
  hooks.yaml
```

The first package is `local-codex-ops`, defined in `packages/local-codex-ops/manifest.yaml`.

## Control Plane Model

Local control is file-based:

- Inventory: what exists now.
- Policy: what is allowed for a task family.
- Hook: what must be checked before or after work.
- Audit: what evidence must be captured.
- Eval: how regressions are caught.

This is intentionally not a daemon. Codex should be able to read these files during future sessions and apply the rules.

## Runtime Model

Use normal Codex for ordinary work. Use tmux only for long-running or restart-sensitive work:

- backups,
- large scans,
- builds and test suites,
- deploys,
- fleet checks,
- long connector sync or export jobs.

Every tmux-managed job should have:

- stable session name,
- command or wrapper path,
- log path,
- progress command,
- stop command,
- completion criteria,
- final report path.

## Subagent Model

Subagents are for bounded parallel work, not ownership transfer.

Good uses:

- independent inventory,
- failure-mode extraction,
- eval design,
- architecture comparison,
- read-only review.

Bad uses:

- handing off final judgment,
- overlapping file edits,
- interpreting skill instructions instead of the main agent reading them,
- spawning agents without clear output contracts.

## Design Boundaries

Do not build these in phase 1:

- central server,
- package registry,
- GUI dashboard,
- custom DSL,
- always-on process supervisor,
- broad RBAC hierarchy,
- mandatory hooks for every action.

Build only what prevents repeatable local failures.
