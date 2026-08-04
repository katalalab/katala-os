# Implementation Plan

## Phase 0: Current Deliverable

Status: complete

- Create Codex Ops documentation root.
- Define lightweight APM-style architecture.
- Capture current inventory.
- Define guardrails and antipatterns.
- Seed policy, manifest, preference data, and eval cases.

## Phase 1: Make It Usable In Daily Work

Target outcome: future Codex sessions can read this directory and follow it.

Tasks:

- Add a short pointer from `$HOME/.codex/AGENTS.md` to this directory.
- Add a `CHANGELOG.md` for Codex Ops changes.
- Add `audit-template.jsonl`.
- Add package lock draft with resolved paths for local plugins and system skills.
- Add a one-page quick checklist for backup, GitHub, SSH/Tailscale, settings.

Do not edit global settings until the pointer and rollback plan are clear.

## Phase 2: Advisory Hooks

Target outcome: hooks warn and document; they do not block.

Candidate scripts:

- `scripts/check-drive-backup-completion.sh`
- `scripts/check-github-publish-preflight.sh`
- `scripts/check-tmux-long-job.sh`
- `scripts/classify-rsync-diff.sh`
- `scripts/check-settings-change.sh`

Outputs should be plain text plus optional JSON.

## Phase 3: Eval Runner

Target outcome: run eval cases against candidate responses or future run summaries.

Minimal runner:

- reads `evals/eval-cases.yaml`,
- checks for must-do/must-not-do evidence,
- emits pass/warn/fail,
- supports manual reviewer notes.

Avoid scoring model quality automatically beyond simple evidence checks.

## Phase 4: Package Lock

Target outcome: document reproducible local environment without freezing everything.

Include:

- Codex CLI version,
- config hash excluding secrets,
- plugin cache roots,
- system skill paths,
- important shell tool versions,
- MCP server command path,
- tmux profile path.

Do not hash or copy secret files.

## Phase 5: Selective Enforcement

Target outcome: hard gates only for high-risk repeat failures.

Good candidates:

- GitHub backup-like publication without private/secret-scan boundary.
- reporting Drive backup complete without file-level upload evidence.
- long-running tmux job without log or stop command.

Avoid enforcing:

- all ordinary coding tasks,
- exploratory local reads,
- small documentation edits.

## Success Criteria

Codex Ops is working when:

- future backup tasks cite specific completion evidence,
- GitHub publish tasks verify remote permissions,
- SSH/Tailscale work produces a host-state matrix,
- tmux jobs are observable and cleaned up,
- settings changes come with rollback notes,
- new repeated failure modes become evals or hooks.
