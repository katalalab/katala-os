# SessionStart hook (Windows): Claude を「マルチエンジンのリード」として常時起動させる姿勢注入。
# インストール済みの外部CLIエージェントだけを案内する。bash 版 orchestration-context と同等。
$ErrorActionPreference = 'SilentlyContinue'
$engines = @()
foreach ($pair in @(@('codex','gpt'),@('cursor-agent','cursor'),@('opencode','opencode'),@('agy','antigravity'))) {
  if (Get-Command $pair[0] -ErrorAction SilentlyContinue) { $engines += $pair[1] }
}
if ($engines.Count -eq 0) { exit 0 }
$list = ($engines -join ' ')
@"
Orchestration posture (default ON):
You are the LEAD engineer. These external CLI engines are available as headless
subagents you can delegate to: $list.
- Delegate via the Task tool (subagent_type = gpt | cursor | opencode | antigravity),
  or directly via Bash: agent-dispatch <engine> --dir "`$PWD" [--read-only] -- "<task>".
- Default to orchestration when it genuinely helps: parallel fan-out for independent
  subtasks, an independent second opinion / consensus before any risky or destructive
  change, and offloading bounded implementation. Do NOT add latency for trivial work.
- Follow the agent-orchestration skill for routing, parallel-write file ownership, and
  consensus rules. Always verify a delegated result before reporting done.
- Antigravity CLI (agy) is the Google-model seat and runs headless via agent-dispatch
  for the Google-model perspective (agent-handoff remains for GUI handoffs).
"@
