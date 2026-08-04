# templates/

Substitution templates consumed by `scripts/init-repo.sh` and `scripts/init-repo.ps1`.

Placeholders:

- `{{REPO_NAME}}`
- `{{REPO_DESCRIPTION}}`
- `{{AGENT_CONTEXT_PATH}}` — absolute path to `~/work/agent-context` on the running node
- `{{DATE}}` — `YYYY-MM-DD`
- `{{OPERATOR}}`

Files:

- `AGENTS.md.tmpl` — repo-specific delta that inherits the global baseline.
- `gitattributes.tmpl` — copied to `.gitattributes`. LF for text, CRLF for `*.ps1`.
- `gitignore.tmpl` — copied to `.gitignore`. Secrets / backups / OS cruft / shell history blocked by default.
- `CONSTITUTION.md.tmpl` — optional, per-repo constitutional subset. Layers on top of the global constitution.
- `manifest.lock.json.tmpl` — optional, hash-lock for `AGENTS.md` + `CONSTITUTION.md`. Hashes start as `REPLACE_AFTER_INIT`.
- `verify.sh.tmpl` — optional repo-local drift checker that delegates to the shared `scripts/verify-manifest.sh`.
- `NEEDS_REVIEW.md.tmpl` — multi-agent dissent log (append-only).

Templates are themselves agent-context — they should not contain secrets, hard-coded usernames, or node-specific paths. The renderer fills those in at init time.
