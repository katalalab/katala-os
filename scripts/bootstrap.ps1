# bootstrap.ps1 — point top-level CLI context files at the agent-context canonical AGENTS.MD.
# Idempotent: safe to re-run. Replaced entries are retained for five runs.
#
# Requires Windows Developer Mode (Settings -> System -> For developers -> Developer Mode = On)
# OR running as Administrator. Without one of these, New-Item -ItemType SymbolicLink fails.
#
# Scope: home-level and per-CLI context pointers documented in overlays/windows.md.

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$Canonical = Join-Path $RepoRoot 'AGENTS.MD'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = Join-Path $env:LOCALAPPDATA 'agent-context-backups\bootstrap'
$BackupDir = Join-Path $BackupRoot $Timestamp
$BackupKeep = 5
$script:BackupCreated = $false

if (-not (Test-Path -LiteralPath $Canonical -PathType Leaf)) {
    Write-Error "canonical AGENTS.MD not found at $Canonical"
}

function Link-One {
    param([string]$Target)

    $relative = $Target.Substring($env:USERPROFILE.Length).TrimStart('\')
    $backup = Join-Path $BackupDir $relative
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -eq 'SymbolicLink') {
            if ($item.Target -contains $Canonical -or $item.Target -eq $Canonical) {
                Write-Host "  ok    $Target -> $Canonical"
                return
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Write-Host "  backup  $Target -> $backup (was -> $($item.Target))"
            Move-Item -LiteralPath $Target -Destination $backup
            $script:BackupCreated = $true
        }
        else {
            $same = $false
            try {
                $same = (Get-FileHash -LiteralPath $Target).Hash -eq (Get-FileHash -LiteralPath $Canonical).Hash
            } catch { $same = $false }

            if ($same) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Write-Host "  backup  $Target -> $backup (identical content)"
                Move-Item -LiteralPath $Target -Destination $backup
                $script:BackupCreated = $true
            }
            else {
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Write-Host "  backup  $Target -> $backup"
                Move-Item -LiteralPath $Target -Destination $backup
                $script:BackupCreated = $true
            }
        }
    }
    else {
        Write-Host "  create  $Target"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path $Target -Target $Canonical | Out-Null
}

# Symlink creation on Windows needs either Developer Mode or an elevated shell.
# Without it New-Item fails per-target and the failure only surfaces later as a
# confusing verification error, so probe once here and say what to turn on.
$probe = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-context-symlink-probe-" + [guid]::NewGuid())
try {
    New-Item -ItemType SymbolicLink -Path $probe -Target $Canonical -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $probe -Force
}
catch {
    Write-Error "cannot create symlinks: enable Developer Mode (Settings > System > For developers) or run this in an elevated shell. Underlying error: $($_.Exception.Message)"
    exit 1
}

Write-Host "agent-context bootstrap (canonical: $Canonical)"

$targets = @(
    (Join-Path $env:USERPROFILE 'CLAUDE.md'),
    (Join-Path $env:USERPROFILE 'AGENTS.md'),
    (Join-Path $env:USERPROFILE 'GEMINI.md'),
    (Join-Path $env:USERPROFILE '.codex\AGENTS.md'),
    (Join-Path $env:USERPROFILE '.claude\CLAUDE.md'),
    (Join-Path $env:USERPROFILE '.gemini\GEMINI.md')
)

foreach ($t in $targets) { Link-One -Target $t }

Write-Host ""
Write-Host "Verification:"
foreach ($t in $targets) {
    $item = Get-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink' -and ($item.Target -contains $Canonical -or $item.Target -eq $Canonical)) {
        Write-Host "  PASS  $t"
    }
    else {
        Write-Error "  FAIL  $t"
    }
}

if ($script:BackupCreated) {
    Write-Host ""
    Write-Host "Backup: $BackupDir"
    Write-Host "Restore: remove a replacement symlink, then Move-Item the matching file from $BackupDir back under $env:USERPROFILE"
}

if (Test-Path -LiteralPath $BackupRoot) {
    Get-ChildItem -LiteralPath $BackupRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -Skip $BackupKeep |
        Remove-Item -Recurse -Force
}

Write-Host ""
Write-Host "Done. To pick up future changes: cd $RepoRoot; git pull"
