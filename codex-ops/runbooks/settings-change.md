# Runbook: Codex Settings Change

Use this before editing Codex global settings, shell startup, SSH config, or MCP definitions.

## Preflight

- Read the existing file.
- Identify whether the change is local, project-level, or global.
- Identify rollback.
- Avoid editing secret-bearing files directly.
- Keep the change minimal.

## Evidence

Record:

```text
file:
reason:
old_behavior:
new_behavior:
rollback:
verification:
```

## High-Risk Files

- `$HOME/.codex/config.toml`
- `$HOME/.codex/tmux-free.config.toml`
- `$HOME/.codex/auth.json`
- `$HOME/.ssh/config`
- shell startup files such as `.zshrc`, `.zprofile`, `.zshenv`

Do not edit `auth.json` or private keys unless explicitly requested and the operation is narrowly defined.
