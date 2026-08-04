# install.ps1 — このノード(Windows)に Claudeリードのマルチエンジン・オーケストレーションを導入する。
# 冪等。再実行安全。bin スクリプトは bash 実装なので git-bash / WSL の bash から実行される前提。
param()
$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home_ = $env:USERPROFILE
$ClaudeDir = Join-Path $Home_ '.claude'
$BinDir = Join-Path $Home_ 'bin'
New-Item -ItemType Directory -Force -Path $BinDir, (Join-Path $ClaudeDir 'agents'), (Join-Path $ClaudeDir 'hooks') | Out-Null

Write-Host "orchestration install (source: $Dir)"

# 1. bin (Windows は symlink 権限が無いことがあるためコピー)
foreach ($b in 'agent-dispatch','agent-handoff','agent-review-after-change') {
  Copy-Item -Force (Join-Path $Dir "bin/$b") (Join-Path $BinDir $b)
  Write-Host "  copy  ~/bin/$b"
}
Copy-Item -Force (Join-Path $Dir 'bin/agent-review-after-change.ps1') (Join-Path $BinDir 'agent-review-after-change.ps1')
Write-Host "  copy  ~/bin/agent-review-after-change.ps1"

# 2. agents
Get-ChildItem (Join-Path $Dir 'agents') -Filter *.md | ForEach-Object {
  Copy-Item -Force $_.FullName (Join-Path $ClaudeDir 'agents')
  Write-Host "  copy  ~/.claude/agents/$($_.Name)"
}

# 3. hook (Windows は ps1 版を使う)
Copy-Item -Force (Join-Path $Dir 'hooks/orchestration-context.ps1') (Join-Path $ClaudeDir 'hooks/orchestration-context.ps1')
Write-Host "  copy  ~/.claude/hooks/orchestration-context.ps1"

# 4. settings.json に SessionStart hook を冪等追加
$Settings = Join-Path $ClaudeDir 'settings.json'
$HookCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($ClaudeDir)\hooks\orchestration-context.ps1`""
if (Test-Path $Settings) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  Copy-Item -Force $Settings "$Settings.bak-$ts-orchestration"
  $cfg = Get-Content $Settings -Raw | ConvertFrom-Json
  if (-not $cfg.hooks) { $cfg | Add-Member -NotePropertyName hooks -NotePropertyValue (@{}) -Force }
  if (-not $cfg.hooks.SessionStart) { $cfg.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() -Force }
  $exists = $false
  foreach ($e in $cfg.hooks.SessionStart) { foreach ($h in $e.hooks) { if ($h.command -like '*orchestration-context*') { $exists = $true } } }
  if (-not $exists) {
    $cfg.hooks.SessionStart += [pscustomobject]@{ matcher='startup|resume'; hooks=@([pscustomobject]@{ type='command'; command=$HookCmd }) }
    [IO.File]::WriteAllText($Settings, ($cfg | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    Write-Host "  patch ~/.claude/settings.json (SessionStart hook added)"
  } else {
    Write-Host "  ok    settings.json already has orchestration hook"
  }
} else {
  Write-Host "  skip  settings.json missing — add hook manually"
}

# Retention: keep the newest five orchestration settings backups.
$backupDir = Split-Path -Parent $Settings
$oldBackups = @(Get-ChildItem -LiteralPath $backupDir -Filter 'settings.json.bak-*-orchestration' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5)
foreach ($backup in $oldBackups) {
  Remove-Item -LiteralPath $backup.FullName -Force
  Write-Host "  prune $($backup.Name)"
}

Write-Host ""
Write-Host "Done. Restart your Claude session to load the new subagents and hook."
Write-Host "Available engines on this node:"
foreach ($c in 'codex','cursor-agent','opencode','agy') {
  $p = if (Get-Command $c -ErrorAction SilentlyContinue) { 'present' } else { 'absent' }
  Write-Host ("  {0,-13} {1}" -f $c, $p)
}
