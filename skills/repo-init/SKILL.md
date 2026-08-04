---
name: repo-init
description: Bootstrap a new repo into Katala OS agent-context style — AGENTS.md inheriting the global baseline, cross-OS .gitattributes, shared pre-commit hook via core.hooksPath, optional hash-locked CONSTITUTION + manifest.lock.json + verify.sh, NEEDS_REVIEW.md. Use when the operator asks to "start a new repo", "scaffold an agent-context repo", "set up Katala-style", or wants to retrofit an existing repo with the standard layout.
---

# repo-init — Katala OS repo scaffolding

This Skill scaffolds a new (or existing) repo with the agent-context style:

- `AGENTS.md` — repo-specific delta, inherits global baseline (`~/work/agent-context/AGENTS.MD`) and constitution.
- `.gitattributes` — LF for `*.md` / `*.json` / `*.sh` / `*.py` / `*.ts` etc., CRLF for `*.ps1` / `*.cmd`. Stops Windows `autocrlf=true` from breaking hashes.
- `.gitignore` — secrets, keys, backups, shell history, OS cruft, generic build/cache.
- `NEEDS_REVIEW.md` — multi-agent dissent log; append-only, operator ratifies.
- Shared pre-commit hook wired via `git config core.hooksPath ~/work/agent-context/hooks`.
- Optional: `CONSTITUTION.md` + `manifest.lock.json` + `scripts/verify.sh` for repos that need hash-locked artifacts.

## When to use this Skill

Match against operator intent like:

- "新リポを Katala 標準で立てて"
- "scaffold an agent-context repo"
- "このリポに AGENTS.md 一式を足したい"
- "hash-locked な constitution も付けて"
- "set up the shared pre-commit hook here"

Do **not** use for:

- Editing the global baseline (`~/work/agent-context/AGENTS.MD`) — that's a direct edit, not a scaffold.
- One-off `.gitignore` additions in an existing repo — just edit.
- Pure GitHub repo creation (use `gh repo create` directly).

## How to invoke

### macOS / Linux

```bash
~/work/agent-context/scripts/init-repo.sh <target-dir> \
  --name <repo-name> \
  --description "<one line>" \
  --operator <name> \
  [--with-constitution] \
  [--no-hooks-path] \
  [--dry-run]
```

### Windows (PowerShell)

```powershell
& "$env:USERPROFILE\work\agent-context\scripts\init-repo.ps1" `
  -Target <target-dir> `
  -RepoName <repo-name> `
  -Description "<one line>" `
  [-WithConstitution] `
  [-NoHooksPath] `
  [-DryRun]
```

Both are idempotent: existing files are backed up to `*.bak.<yyyyMMdd-HHmmss>` before being overwritten. Backups are pruned automatically when (a) a newer same-base backup exists AND (b) the older one is >30 days old. This matches the Hard Rule "every backup declares a retention rule and a matching prune step."

## Default contents written

Always:

1. `AGENTS.md` (from `templates/AGENTS.md.tmpl`)
2. `.gitattributes` (from `templates/gitattributes.tmpl`)
3. `.gitignore` (from `templates/gitignore.tmpl`)
4. `NEEDS_REVIEW.md` (from `templates/NEEDS_REVIEW.md.tmpl`)

With `--with-constitution`:

5. `CONSTITUTION.md` (from `templates/CONSTITUTION.md.tmpl`)
6. `manifest.lock.json` (from `templates/manifest.lock.json.tmpl`, with `REPLACE_AFTER_INIT` placeholders)
7. `scripts/verify.sh` (from `templates/verify.sh.tmpl`, chmod +x)

## Substitution markers

The renderer rewrites:

- `{{REPO_NAME}}` — `--name` or the target dir's basename.
- `{{REPO_DESCRIPTION}}` — `--description` or `<one-line description of …>`.
- `{{AGENT_CONTEXT_PATH}}` — absolute path to `~/work/agent-context` on the running node.
- `{{DATE}}` — `YYYY-MM-DD` at run time.
- `{{OPERATOR}}` — `--operator` or `$USER` / `$env:USERNAME`.

## Post-init checklist (agent should walk the operator through)

1. `cd <target> && git init` if the dir isn't a repo yet, then re-run init-repo so `core.hooksPath` gets set.
2. Edit `AGENTS.md`: fill in **What this repo is**, **Layout**, **Build / test / lint**, **Verification**.
3. If `--with-constitution` was used, compute real hashes and overwrite the `REPLACE_AFTER_INIT` placeholders:

   ```bash
   shasum -a 256 AGENTS.md CONSTITUTION.md
   ```

   Then edit `manifest.lock.json` and run `scripts/verify.sh` — expect `verify: OK`.
4. Confirm the shared hook is active:

   ```bash
   git config --get core.hooksPath  # should print the agent-context/hooks path
   ```
5. Make the first commit. Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`) per global constitution.

## Hard-rule reminders for the agent

- Do **not** copy secrets / `.env` / `*.key` / `*.pem` into the new repo. The shared pre-commit and `.gitignore` block them; if an operator asks you to commit one, refuse and surface to `NEEDS_REVIEW.md`.
- Do **not** push to a remote without explicit operator confirmation. `gh repo create` and `git push` are third-party-account writes that require explicit intent.
- If the target already has `AGENTS.md` / `CONSTITUTION.md`, the renderer backs them up — but **still report the backup path** in the end-of-turn summary so the operator can restore if needed.
- Hash-locked artifacts (`AGENTS.md`, `CONSTITUTION.md`) need their `manifest.lock.json` entry updated in the same commit as any content change. A mismatch is a stop-the-world signal, not a warning.

## Verification

After running init-repo, the narrowest real verification:

```bash
# With --with-constitution:
cd <target> && bash scripts/verify.sh

# Without --with-constitution:
cd <target> && grep -q 'work/agent-context/AGENTS.MD' AGENTS.md && echo OK
```
