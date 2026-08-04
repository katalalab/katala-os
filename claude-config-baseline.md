# Claude Config Baseline (per-role)

Fleet baseline for `~/.claude/settings.json` and related state. Measured reality as of 2026-07-31 (all 6 nodes audited live); evidence: `~/work/docs/agent-reliability/latest.md`.

## Hard (every node)

- `permissions.defaultMode = "bypassPermissions"` + PreToolUse safety valves (`claude-safety-valve.js` for Edit|Write, `claude-bash-safety-valve.js` for Bash) — confirmed present on all 6 nodes.
- `disableClaudeAiConnectors: true` — blocks claude.ai connector auto-fetch for terminal CLI sessions.
- Telemetry off: `DISABLE_TELEMETRY=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- Secret-path deny rules (`.env`, `~/.ssh`, `~/.aws`, credential files) and `git push --force` deny.
- SessionStart `orchestration-context` hook.

## Profiles

- `standard` (mac-node-a, home-mac, win-node-a, gpu-node-b): MCP = standard-7 (`chrome-devtools, codebase-memory-mcp, context7, exa, microsoft-learn, openaiDeveloperDocs, playwright`); enabledPlugins core = `superpowers`, `ppt-master`, `claude-code-setup`.
- `dev-hub` (gpu-node-a): standard + dev/LSP plugin set (security-guidance, document-skills, feature-dev, LSPs, mcp-dev, etc.) + orca relay hooks. Intentional superset, not drift.
- `light` (win-node-b): hard rules only; minimal MCP (`mcpdoc`), no plugins. Do not force standard-7 here without operator need.

Recorded exceptions (not drift): mac-node-a adds `project-beta` MCP (project-gamma business); home-mac adds `multiagent-bridge` MCP (codex custom-mcp asset); home-mac skills dir is the fleet superset.

## Context hygiene (the context-rot gates)

- `CLAUDE.md` (= canonical `AGENTS.MD`): keep ≤200 lines — official adherence guidance.
- Auto-memory `MEMORY.md`: official load cap is first 200 lines / 25KB, overflow is silently dropped. Alert line: 15KB. Compact by moving dead memories to `memory/_archive/` (never delete; backup with retention first).
- Skills/agents dirs inject names+descriptions per session: keep them intentional per profile.
- Check with `/context` and `/usage`; regression-probe with `~/work/docs/agent-reliability/eval-tasks/` (10 code-graded tasks) or harbor (`harbor-setup.md`).

## Claude Code Desktop (CCD) caveat

CCD injects claude.ai connectors (10) and remote marketplace plugins (26, `knowledge-work-plugins`) at the SDK layer — local settings cannot remove them permanently (RemotePluginManager re-syncs every 10 min). Permanent removal is claude.ai UI only: Settings → Connectors (disconnect) and Settings → Capabilities (uninstall plugins). Local levers: per-session tool toggles, `skillOverrides` in settings.json.
