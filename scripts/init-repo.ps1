# init-repo.ps1 — bootstrap a new repo into Katala OS agent-context style.
# Copies templates with placeholder substitution, wires the shared pre-commit
# hook, optionally lays down the hash-locked subset (CONSTITUTION + manifest).
#
# Idempotent: existing files are backed up with retention (keep newest, prune >30d).
#
# Usage:
#   .\init-repo.ps1 -Target C:\Users\<u>\work\my-new-repo `
#                   -RepoName my-new-repo `
#                   -Description "data export pipeline v2" `
#                   -WithConstitution

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$RepoName,
    [string]$Description,
    [string]$Operator = $env:USERNAME,
    [switch]$WithConstitution,
    [switch]$NoHooksPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ScriptDir    = Split-Path -Parent $PSCommandPath
$RepoRoot     = Split-Path -Parent $ScriptDir
$TemplatesDir = Join-Path $RepoRoot 'templates'

$Target = [System.IO.Path]::GetFullPath($Target)
if (-not $RepoName)    { $RepoName = Split-Path -Leaf $Target }
if (-not $Description) { $Description = "<one-line description of $RepoName>" }

$Date      = Get-Date -Format 'yyyy-MM-dd'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "init-repo: target=$Target"
Write-Host "           name=$RepoName"
Write-Host "           operator=$Operator"
Write-Host "           constitution=$([int]$WithConstitution.IsPresent) hooks-path=$([int](-not $NoHooksPath)) dry-run=$([int]$DryRun.IsPresent)`n"

if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $Target)) {
        New-Item -ItemType Directory -Path $Target | Out-Null
    }
}

function Render-Template {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-Warning "  missing template: $Source"
        return
    }

    # Use literal .Replace() (not -replace) so Windows paths with backslashes
    # in {{AGENT_CONTEXT_PATH}} aren't interpreted as regex escapes.
    $content = Get-Content -LiteralPath $Source -Raw
    $rendered = $content.Replace('{{REPO_NAME}}',          $RepoName).
                         Replace('{{REPO_DESCRIPTION}}',   $Description).
                         Replace('{{AGENT_CONTEXT_PATH}}', $RepoRoot).
                         Replace('{{DATE}}',               $Date).
                         Replace('{{OPERATOR}}',           $Operator)

    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Content -LiteralPath $Destination -Raw
        if ($existing -ceq $rendered) {
            Write-Host "  ok    $Destination (identical)"
            return
        }
        $backup = "$Destination.bak.$Timestamp"
        Write-Host "  backup $Destination -> $backup"
        if (-not $DryRun) {
            Move-Item -LiteralPath $Destination -Destination $backup -Force
        }
    } else {
        Write-Host "  create $Destination"
    }

    if (-not $DryRun) {
        $destDir = Split-Path -Parent $Destination
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir | Out-Null
        }
        # Write LF for .md/.json/.sh, CRLF for .ps1 — matches .gitattributes.
        $ext = [System.IO.Path]::GetExtension($Destination).ToLowerInvariant()
        $eol = if ($ext -in @('.ps1','.psm1','.psd1','.cmd','.bat')) { "`r`n" } else { "`n" }
        # Normalize whatever the source had to the destination's EOL.
        $normalized = ($rendered -replace "`r`n", "`n") -replace "`n", $eol
        # -NoNewline avoids a stray trailing line. Writers append their own.
        Set-Content -LiteralPath $Destination -Value $normalized -NoNewline -Encoding UTF8
    }
}

# Core files (always written).
Render-Template (Join-Path $TemplatesDir 'AGENTS.md.tmpl')       (Join-Path $Target 'AGENTS.md')
Render-Template (Join-Path $TemplatesDir 'gitattributes.tmpl')   (Join-Path $Target '.gitattributes')
Render-Template (Join-Path $TemplatesDir 'gitignore.tmpl')       (Join-Path $Target '.gitignore')
Render-Template (Join-Path $TemplatesDir 'NEEDS_REVIEW.md.tmpl') (Join-Path $Target 'NEEDS_REVIEW.md')

if ($WithConstitution) {
    Render-Template (Join-Path $TemplatesDir 'CONSTITUTION.md.tmpl')    (Join-Path $Target 'CONSTITUTION.md')
    Render-Template (Join-Path $TemplatesDir 'manifest.lock.json.tmpl') (Join-Path $Target 'manifest.lock.json')
    Render-Template (Join-Path $TemplatesDir 'verify.sh.tmpl')          (Join-Path $Target 'scripts\verify.sh')
}

# Prune backups: keep newest per filename, delete >30 days old.
if (-not $DryRun -and (Test-Path -LiteralPath $Target)) {
    Get-ChildItem -LiteralPath $Target -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.bak\.\d{8}-\d{6}$' } |
        Group-Object { ($_.FullName -split '\.bak\.')[0] } |
        ForEach-Object {
            $_.Group |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip 1 |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
                ForEach-Object {
                    Write-Host "  prune  $($_.FullName)"
                    Remove-Item -LiteralPath $_.FullName -Force
                }
        }
}

# Wire shared pre-commit hook.
if (-not $NoHooksPath) {
    $gitDir = Join-Path $Target '.git'
    if (Test-Path -LiteralPath $gitDir) {
        $hooksPath = Join-Path $RepoRoot 'hooks'
        if (-not $DryRun) {
            git -C $Target config core.hooksPath $hooksPath | Out-Null
        }
        Write-Host "  hooks  core.hooksPath -> $hooksPath"
    } else {
        Write-Host "  hooks  skipped (no .git in $Target -- run ``git init`` first, then re-run init-repo)"
    }
}

Write-Host "`ninit-repo: done."
Write-Host "Next steps:"
Write-Host "  1. cd $Target ; git init  (if not already)"
Write-Host "  2. Edit AGENTS.md (Layout / Build-test-lint / Verification)."
if ($WithConstitution) {
    Write-Host "  3. Compute hashes and update manifest.lock.json:"
    Write-Host "       Get-FileHash AGENTS.md, CONSTITUTION.md -Algorithm SHA256"
    Write-Host "  4. Run scripts\verify.sh (via Git Bash) -- expect OK."
}
