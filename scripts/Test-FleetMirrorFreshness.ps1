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

if (-not (Test-Path $LockPath)) {
    Write-Error "lock file missing: $LockPath"
    exit 2
}

# Windows PowerShell 5.1 can silently fail to autoload Get-FileHash when a
# PS7 WindowsApps package earlier on $env:PSModulePath ships a same-named,
# CLR-incompatible Microsoft.PowerShell.Utility manifest. Force the real one.
if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    Import-Module "$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1" -Force -ErrorAction Stop
}

$lock = Get-Content $LockPath -Raw | ConvertFrom-Json

# Resolve `paths_relative_to` from lock file; default to lock-file directory.
$root = Split-Path -Parent $LockPath
if ($lock.PSObject.Properties.Name -contains 'paths_relative_to') {
    $declared = $lock.paths_relative_to
    if ($declared -match '^~') {
        $declared = $declared -replace '^~', $env:USERPROFILE
    }
    $declared = $declared.TrimEnd('/', '\')
    if (Test-Path $declared) { $root = (Resolve-Path $declared).Path }
}

$failures = @()
$checks = 0

foreach ($artifactName in $lock.artifacts.PSObject.Properties.Name) {
    $artifact = $lock.artifacts.$artifactName
    $checks++

    $rel = $artifact.path
    $abs = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $root $rel }

    if (-not (Test-Path $abs)) {
        Write-Output "[MISSING] $artifactName -> $abs"
        $failures += "$artifactName : file missing"
        continue
    }

    $actual = (Get-FileHash $abs -Algorithm SHA256).Hash
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
