# Codex Ops

This directory is the operating model for local Codex work on a primary workstation.

The goal is not to fine-tune GPT locally. The goal is to make Codex behavior more repeatable by turning working practice into packages, policies, hooks, audits, and evals.

## Scope

- Skills: when to use them, how to read `SKILL.md`, and how to avoid overloading context.
- Hooks: preflight, postflight, error handling, and long-running task monitors.
- MCP and connectors: when external context is required, and when local search is enough.
- Settings: `~/.codex/config.toml`, tmux profiles, plugin state, and risk boundaries.
- Environment setup: shell, GitHub, Drive, SSH, Tailscale, tmux, and backup workflows.
- Subagents: bounded parallel analysis with main-agent integration responsibility.
- Evals: RLHF-style preference data and regression checks without local model training.

## Operating Model

Codex Ops is organized like a lightweight Agent Package Manager plus local control plane:

- `architecture.md`: Microsoft APM / Agent 365 inspired design adapted to local Codex.
- `assets/asset-catalog.yaml`: reusable asset catalog for scripts, runbooks, datasets, and local evidence.
- `inventory.md`: current Codex configuration, plugin, skill, memory, automation, and tmux state.
- `hooks-and-guardrails.md`: guardrails and hook candidates for high-risk workflows.
- `antipatterns.md`: failure modes observed or inferred from prior local operations.
- `post-training-loop.md`: RLHF-style preference/eval loop for improving operations without model training.
- `multi-ai-reinforcement-loop.md`: bounded loop policy for Codex, Claude, Cursor, Antigravity, GitHub Copilot, Oracle, GitHub, Google Drive, OpenAI docs, agmsg, Superpowers, and Skills.
- `$HOME/work/docs/scripts/agent-reinforcement-feedback-ledger.py`: scored feedback ledger that turns measurements, GitHub discussion, agmsg status, Drive reachability, and Oracle dry-runs into reusable loop events.
- `implementation-plan.md`: phased rollout plan.
- `packages/local-codex-ops/manifest.yaml`: package manifest for the first local ops package.
- `policies/default.yaml`: starter policy for local Codex operational work. A human/agent-facing document, not Codex `config.toml` syntax — nothing parses it. For the keys Codex does read, see the [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- `scripts/backup-asset-index.sh`: metadata-only backup index generator.
- `scripts/validate-learning-data.sh`: JSONL/YAML validator for agent learning data.
- `retrospectives/`: backup, rollout, and incident reviews with repeat/avoid rules.
- `runbooks/backup-asset-index.md`: restore-oriented index workflow and safety boundary.
- `runbooks/learning-data-assetization.md`: workflow for turning operations into safe learning data.
- `runbooks/windows-codex-remote-and-log-retention.md`: Windows SSH discovery and bounded Codex diagnostic-log maintenance.
- `evals/preference-dataset.jsonl`: seed preference examples.
- `evals/agent-learning-dataset.jsonl`: structured trigger -> behavior -> evidence examples.
- `evals/antipattern-cases.yaml`: machine-readable antipattern cases.
- `evals/eval-cases.yaml`: regression eval definitions.

## Practical Rule

Use documentation for decision support, not ceremony. Add guardrails where a past failure would have been prevented:

- backup completion checks,
- GitHub publication gates,
- secret-scan boundaries,
- Tailscale/SSH preflight,
- tmux observability for long-running tasks,
- settings-change review,
- subagent responsibility boundaries.
- assetization and learning data boundaries.

Avoid building a central server, custom registry, GUI, or complex RBAC until the local package/policy/eval loop has proven value.
