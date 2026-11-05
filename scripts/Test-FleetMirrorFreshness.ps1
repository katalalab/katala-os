# Test-FleetMirrorFreshness.ps1 - Detect drift between agent-context artifacts
# and the hashes recorded in manifest.lock.json.
#
# Read-only: never modifies any file. Emits drift report to stdout + non-zero
# exit code on mismatch so this can be wired into a Task Scheduler job.
#
# Default lock path: $env:USERPROFILE\work\agent-context\manifest.lock.json
# Override with -LockPath.

[CmdletBinding()]
param(
    [string]$LockPath = (Join-Path $env:USERPROFILE 'work\agent-context\manifest.lock.json')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    [Console]::Error.WriteLine("lock file missing: $LockPath")
    exit 2
}
$LockPath = (Resolve-Path -LiteralPath $LockPath -ErrorAction Stop).ProviderPath

# Windows PowerShell 5.1 can silently fail to autoload Get-FileHash when a
# PS7 WindowsApps package earlier on $env:PSModulePath ships a same-named,
# CLR-incompatible Microsoft.PowerShell.Utility manifest. Force the real one.
if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    Import-Module "$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1" -Force -ErrorAction Stop
}

function Test-AmbiguousPath([string]$Value) {
    # C:foo and \foo depend on the process's current drive/directory.
    return $Value -match '^[A-Za-z]:(?![\\/])|^[\\/](?![\\/])'
}

try {
    $lock = Get-Content -LiteralPath $LockPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($lock -isnot [pscustomobject] -or $lock.artifacts -isnot [pscustomobject]) { throw 'invalid artifacts' }
    $entries = @($lock.artifacts.PSObject.Properties)
    if ($entries.Count -eq 0) { throw 'empty artifacts' }
    foreach ($entry in $entries) {
        $artifact = $entry.Value
        if ([string]::IsNullOrEmpty($entry.Name) -or $entry.Name -match '[\x00-\x1f\x7f]' -or
            $artifact -isnot [pscustomobject] -or $artifact.path -isnot [string] -or
            [string]::IsNullOrEmpty($artifact.path) -or $artifact.path -match '[\x00-\x1f\x7f]' -or (Test-AmbiguousPath $artifact.path) -or
            $artifact.sha256 -isnot [string] -or $artifact.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw 'invalid artifact entry'
        }
    }
    if ($null -ne $lock.paths_relative_to -and $lock.paths_relative_to -isnot [string]) { throw 'invalid declared root' }
    if ($lock.paths_relative_to -is [string] -and ($lock.paths_relative_to -match '[\x00-\x1f\x7f]' -or (Test-AmbiguousPath $lock.paths_relative_to))) { throw 'invalid declared root' }
} catch {
    Write-Output "invalid manifest: $LockPath"
    exit 2
}

# Resolve `paths_relative_to` from lock file; default to lock-file directory.
$root = Split-Path -Parent $LockPath
try {
    $declared = $lock.paths_relative_to
    if ($declared) {
        if ($declared.StartsWith('~')) { $declared = $env:USERPROFILE + $declared.Substring(1) }
        if ([System.IO.Path]::IsPathRooted($declared)) { $root = [System.IO.Path]::GetFullPath($declared) }
        else { $root = [System.IO.Path]::GetFullPath((Join-Path $root $declared)) }
    }
} catch {
    Write-Output "invalid manifest root: $LockPath"
    exit 2
}

$failures = @()
$checks = 0

foreach ($entry in $entries) {
    $artifactName = $entry.Name
    $artifact = $entry.Value
    $checks++

    $rel = $artifact.path
    $abs = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $root $rel }

    if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) {
        Write-Output "[MISSING] $artifactName -> $abs"
        $failures += "$artifactName : file missing"
        continue
    }

    try {
        $actual = (Get-FileHash -LiteralPath $abs -Algorithm SHA256 -ErrorAction Stop).Hash
    } catch {
        Write-Output "[ERROR]   $artifactName -> $abs"
        $failures += "$artifactName : hash unavailable"
        continue
    }
    $expected = $artifact.sha256
    if ($actual -eq $expected) {
        Write-Verbose "[OK]      $artifactName -> $actual"
    } else {
        Write-Output "[DRIFT]   $artifactName"
        Write-Output "          path:     $abs"
        Write-Output "          expected: $expected"
        Write-Output "          actual:   $actual"
        $failures += "$artifactName : drift detected"
    }
}

Write-Output ""
Write-Output "checked: $checks artifacts; failures: $($failures.Count)"
if ($failures.Count -gt 0) {
    Write-Output ""
    Write-Output "Drift response (per manifest.lock.json):"
    Write-Output "  $($lock.drift_response)"
    exit 1
}
exit 0
