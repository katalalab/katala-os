# Baseline — REPLACE THIS WITH YOUR OWN

> **This file is a fictional example, and it is also the file `scripts/bootstrap.sh` mirrors.**
> Rewrite it for your own environment before you rely on it: the fleet table, the routing, and
> the workspace layout below describe a three-machine fleet that does not exist. Nothing here
> describes a real environment. `templates/AGENTS.md.tmpl` is the blank form if you would rather
> start from nothing.

This file is the canonical baseline: `bootstrap.sh` / `bootstrap.ps1` symlink `~/CLAUDE.md`,
`~/AGENTS.md`, and `~/GEMINI.md` to it, so every agent reads one source and divergence is
structurally impossible. Keep it to hard rules; procedures belong in runbooks, skills, or OS
overlays. `CONSTITUTION.md` outranks everything written here.

## Fleet

| Role | Node | OS | Access |
| --- | --- | --- | --- |
| Primary workstation | `mac-node-a` | macOS | local |
| GPU box | `gpu-node-a` | Windows 11 + WSL2 | `ssh gpu-node-a` |
| Secondary | `win-node-b` | Windows 11 | `ssh win-node-b` |

Treat fleet nodes as trusted personal development machines, not production servers. Start remote
work read-only; ask before making remote changes persistent.

## Communication

- Report short and direct. Summarise key lines assuming the operator cannot see raw command output.
- Back technical judgments with evidence: file path, real command result, retrieval date. Never
  assert from stale memory or a single community post.
- Keep internal deliberation out of user-facing replies. Surface results and decisions.
- Depth-shift trigger words are honored literally, not decoratively: `ultrathink` / `take your time`
  → slow, thorough mode; `comprehensive` → cover all related files, not just the direct target;
  `read all related code` → full call-graph traversal before acting.

## Hard rules

- Use `rg` for search. Read project-level instructions before editing.
- Never silently reduce scope. State safety or tooling boundaries before narrowing.
- For destructive operations, produce a backup path and a restore command first. Every backup
  declares a retention rule and a matching prune step in the same script or runbook.
- Verify with the narrowest real command that covers the behavior. Use end-to-end checks when asked.
- Keep CLI histories, logs, auth, tokens, SSH keys, and caches out of shared sources.
- Secrets are referenced only via a secret manager (`op://…`) or already-exported env — never
  written into docs, logs, memory, or prompt examples.
- Destructive change requires a read-only second opinion from a *different* engine over the same
  scope. Dissent escalates to `NEEDS_REVIEW.md`; it is never silently overridden.
- `CONSTITUTION.md` wins over anything here.

## Source order

1. Local reality: files, versions, lockfiles, logs, running processes, current command output.
2. Official docs for the tool in question.
3. Primary sources: upstream releases, schemas, RFCs, security advisories, maintainer comments.
4. Community posts — for symptom discovery and supporting evidence only.

When official docs and local behavior disagree, prefer a minimal reproduction and a reversible
change before editing.

## Agent routing

Use the available engines as complementary specialists rather than interchangeable ones.

- Implementation, tests, repo changes backed by evidence → the engine with the best local tooling.
- Long migrations, hook-driven repair loops, broad generation → the engine with the largest budget.
- Broad-context review, alternate critique, second opinions → a *different* vendor's model, so the
  review is genuinely independent.

Share results through files, commands, diffs, and test output. Do not transfer hidden model
reasoning between tools.

### Parallel dispatch

Count expected file changes before dispatching. Five or fewer files inside one module → parallel is
fine. Cross-module → serial, with explicit file/directory ownership per agent. Stop an agent whose
scope drifts mid-run. Treat databases, caches, and compiled artifacts as non-atomic and serialize
them. Never let two write-capable agents touch the same file or state simultaneously.

## Validation defaults

- Git: `git status --short` and the relevant diff before committing.
- Network/SSH: check status, reachability, and a real handshake separately.
- Frontend: local server, rendered page, screenshot, console errors.
- Docs/config only: hash, line count, parse check, target path, backup path.
- Report verified and unverified scope separately. When verification was impossible, say why and
  what to check next.
- When implementing new behavior, write or update the covering test in the same session — deferring
  it to a later one misses implementation drift.

## Editing policy

- Comments answer WHY, not WHAT. Reserve them for non-obvious constraints and invariants.
- Task references (`fixes #123`) belong in commit messages, never inline.
- Remove backward-compat hacks, dead re-exports, and deprecated aliases once confident.
- Do not add speculative error handling. Validate at system boundaries only.
- Do not mix a bug fix with a refactor. Do not extract a helper for a single use.
- Prefer minimal diffs over rewrites. Match existing naming and directory conventions.

## Execution policy

- State a command's purpose in one line before running it.
- Read-only inspection needs no confirmation. Confirm before anything that writes files, adds or
  removes dependencies, reaches the network, or touches credentials and production config.
- Honor project-defined test, lint, and format commands. Do not introduce a new tooling system on a whim.
- Never commit, push, create branches, or run migrations unless explicitly asked.

## Workspace routing

- `work/`: active development.
- `work/docs/`: durable operational docs, runbooks, evidence, handoffs.
- `lab/`: experiments and prototypes.
- `vendor/`: third-party reference clones — not authoritative.
- `_archive/`: cold storage with rollback notes.
