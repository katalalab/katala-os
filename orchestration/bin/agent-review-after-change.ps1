<#
.SYNOPSIS
Run independent, read-only adversarial reviews only after a meaningful change.

.DESCRIPTION
Runs Codex, Claude Code, and Antigravity as independent read-only reviewers when a
working-tree change is large enough to warrant review. Small changes are
skipped by design.

.PARAMETER Dir
Git repository to review (default: current directory).

.PARAMETER Force
Review regardless of the size threshold.

.PARAMETER DryRun
Evaluate the trigger and selected reviewers only.

.PARAMETER Engines
Comma-separated engines (codex,claude,antigravity).

.PARAMETER ReportDir
Persist reviewer outputs and a summary (optional).

.PARAMETER Timeout
Per-review timeout in seconds (default: 900).

.PARAMETER Help
Show this help.

.NOTES
Environment model overrides:
  CODEX_REVIEW_MODEL (default: gpt-5.6-sol)
  CLAUDE_REVIEW_MODEL (default: opus)
  ANTIGRAVITY_REVIEW_MODEL (default: agy built-in)

Exit codes:
  0 review skipped or all reviewers approved
  2 one or more reviewers requested changes or returned an invalid verdict
  3 changed paths include a secret-bearing file; use a manual review
  4 a required reviewer was unavailable or timed out
#>

param(
    [string]$Dir = (Get-Location).Path,
    [switch]$Force = $false,
    [switch]$DryRun = $false,
    [string]$Engines = "codex,claude,antigravity",
    [string]$ReportDir = "",
    [int]$Timeout = 900,
    [switch]$Help = $false
)

function Show-Help {
    Write-Host @"
Usage:
  agent-review-after-change.ps1 [options]

Runs Codex, Claude Code, and Antigravity as independent read-only reviewers when a
working-tree change is large enough to warrant review. Small changes are
skipped by design.

Options:
  -Dir DIR              Git repository to review (default: current directory)
  -Force                Review regardless of the size threshold
  -DryRun               Evaluate the trigger and selected reviewers only
  -Engines LIST         Comma-separated engines (codex,claude,antigravity)
  -ReportDir DIR        Persist reviewer outputs and a summary (optional)
  -Timeout SECONDS      Per-review timeout (default: 900)
  -Help                 Show this help

Environment model overrides:
  CODEX_REVIEW_MODEL (default: gpt-5.6-sol)
  CLAUDE_REVIEW_MODEL (default: opus)
  ANTIGRAVITY_REVIEW_MODEL (default: agy built-in)

Exit codes:
  0 review skipped or all reviewers approved
  2 one or more reviewers requested changes or returned an invalid verdict
  3 changed paths include a secret-bearing file; use a manual review
  4 a required reviewer was unavailable or timed out
"@
}

if ($Help) {
    Show-Help
    exit 0
}

if ($Timeout -le 0) {
    [Console]::Error.WriteLine("agent-review-after-change.ps1: --timeout must be a positive integer")
    exit 64
}

$Dir = (Resolve-Path $Dir).Path
if (-not (Test-Path "$Dir/.git")) {
    [Console]::Error.WriteLine("agent-review-after-change.ps1: not a git working tree: $Dir")
    exit 64
}

$report_relative = ""
$report_absolute = ""
if ($ReportDir) {
    if ([System.IO.Path]::IsPathRooted($ReportDir)) {
        $report_absolute = $ReportDir
    } else {
        $report_absolute = Join-Path $Dir $ReportDir
    }
    $report_absolute = (Resolve-Path -LiteralPath (Split-Path $report_absolute)).Path | Join-Path -ChildPath (Split-Path $report_absolute -Leaf)
    if ($report_absolute.StartsWith("$Dir" + [IO.Path]::DirectorySeparatorChar)) {
        $report_relative = $report_absolute.Substring($Dir.Length + 1)
    }
    $ReportDir = $report_absolute
}

$changedFiles = @()
try {
    $modifiedFiles = @(& git -C $Dir diff --name-only HEAD 2>$null | Where-Object { $_ })
    $untrackedFiles = @(& git -C $Dir ls-files --others --exclude-standard 2>$null | Where-Object { $_ })
    $allFiles = @($modifiedFiles + $untrackedFiles) | Select-Object -Unique
    
    foreach ($path in $allFiles) {
        if ($path -and -not ($report_relative -and $path.StartsWith($report_relative))) {
            $changedFiles += $path
        }
    }
    $changedFiles = $changedFiles | Select-Object -Unique
} catch {
    [Console]::Error.WriteLine("agent-review-after-change.ps1: failed to detect git changes")
    exit 64
}

if ($changedFiles.Count -eq 0) {
    Write-Host "REVIEW_STATUS=SKIP_NO_CHANGES"
    exit 0
}

$secret_paths = @()
$code_files = 0
$doc_files = 0
$risk_files = 0
$changed_lines = 0

$secretPatterns = @(
    "\.env",
    "\.env\.",
    "[/\\]secrets[/\\]",
    "[/\\]credentials[/\\]",
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "\.pem$",
    "\.key$",
    "\.p12$",
    "\.pfx$",
    "\.npmrc$",
    "service-account.*\.json$",
    "[/\\]\.aws[/\\]credentials$",
    "[/\\]\.kube[/\\]config$",
    "\.tfvars$",
    "[/\\]\.docker[/\\]config\.json$"
)

$codeExtensions = @("ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "java", "kt", "cs", "c", "cc", "cpp", "h", "hpp", "rb", "php", "sh", "ps1")
$docPatterns = @("\.md$", "\.mdx$", "docs[/\\]", "^README", "^CHANGELOG", "^CONTRIBUTING")
$riskPatterns = @("auth", "security", "permission", "migration", "schema", "deploy", "infra", "config")

foreach ($path in $changedFiles) {
    $isSecret = $false
    foreach ($pattern in $secretPatterns) {
        if ($path -match $pattern) {
            $isSecret = $true
            break
        }
    }
    if ($isSecret) {
        $secret_paths += $path
    }
    
    $ext = [System.IO.Path]::GetExtension($path).TrimStart(".")
    if ($codeExtensions -contains $ext) {
        $code_files++
    }
    
    $isDoc = $false
    foreach ($pattern in $docPatterns) {
        if ($path -match $pattern) {
            $isDoc = $true
            break
        }
    }
    if ($isDoc) {
        $doc_files++
    }
    
    $isRisk = $false
    foreach ($pattern in $riskPatterns) {
        if ($path -match $pattern) {
            $isRisk = $true
            break
        }
    }
    if ($isRisk) {
        $risk_files++
    }
}

try {
    $diffNumstat = @(& git -C $Dir diff --numstat HEAD 2>$null)
    foreach ($line in $diffNumstat) {
        if ($line -match "^(\d+)\s+(\d+)\s+") {
            if ($matches[1] -match "^\d+$") { $changed_lines += [int]$matches[1] }
            if ($matches[2] -match "^\d+$") { $changed_lines += [int]$matches[2] }
        }
    }
    
    foreach ($path in $changedFiles) {
        if (Test-Path "$Dir/$path" -PathType Leaf) {
            $lineCount = @(Get-Content "$Dir/$path" 2>$null).Count
            if ($lineCount -match "^\d+$") { $changed_lines += [int]$lineCount }
        }
    }
} catch {
}

if ($secret_paths.Count -gt 0) {
    Write-Host "REVIEW_STATUS=MANUAL_SECRET_BOUNDARY"
    foreach ($path in $secret_paths) {
        Write-Host "SECRET_PATH=$path"
    }
    Write-Host "Model review was not started. Remove the secret-bearing path from the change or perform a manual review."
    exit 3
}

$should_review = 0
$trigger = "small-change"
if ($Force) {
    $should_review = 1
    $trigger = "forced"
} elseif ($risk_files -gt 0) {
    $should_review = 1
    $trigger = "risk-path"
} elseif ($changedFiles.Count -ge 3 -and $code_files -ge 2) {
    $should_review = 1
    $trigger = "implementation-slice"
} elseif ($changed_lines -ge 120 -and $code_files -ge 1) {
    $should_review = 1
    $trigger = "large-code-change"
}

Write-Host "REVIEW_SCOPE=files:$($changedFiles.Count) code:$code_files docs:$doc_files lines:$changed_lines risk:$risk_files"
if ($should_review -eq 0) {
    Write-Host "REVIEW_STATUS=SKIP_SMALL_CHANGE"
    Write-Host "REVIEW_TRIGGER=$trigger"
    exit 0
}

$selectedEngines = $Engines -split ","
if ($selectedEngines.Count -lt 2) {
    [Console]::Error.WriteLine("agent-review-after-change.ps1: at least two independent engines are required")
    exit 64
}
foreach ($engine in $selectedEngines) {
    if ($engine -notmatch "^(codex|claude|antigravity)$") {
        [Console]::Error.WriteLine("agent-review-after-change.ps1: unsupported engine: $engine")
        exit 64
    }
}

Write-Host "REVIEW_STATUS=READY"
Write-Host "REVIEW_TRIGGER=$trigger"
Write-Host "REVIEW_ENGINES=$($selectedEngines -join ',')"
if ($DryRun) {
    exit 0
}

if ($ReportDir) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

$changedPathList = $changedFiles -join "`n"
$reviewPrompt = @"
Act as an adversarial, read-only reviewer. Review the uncommitted change in this repository against HEAD, including changed documentation and implementation. Do not edit files, do not run network commands, and do not inspect secret-bearing paths such as .env, credentials, keys, or auth stores.

Challenge the change rather than explaining it. Trace callers and affected contracts where useful. Assess correctness, regressions, security and permissions, data-loss or migration safety, concurrency, test coverage, and consistency between code and documentation. Report only findings grounded in the changed files or their direct callers.

Changed paths:
$changedPathList

End with exactly one line: VERDICT: APPROVE, VERDICT: REQUEST_CHANGES, or VERDICT: NEEDS_DISCUSSION.
Before that line, use short sections named BLOCKERS, NON_BLOCKERS, COVERAGE_GAPS, and DOC_CONSISTENCY.
"@

$failedEngines = @()
$changeEngines = @()

foreach ($engine in $selectedEngines) {
    $outputFile = [System.IO.Path]::GetTempFileName()
    $errorFile = [System.IO.Path]::GetTempFileName()
    $model = ""
    $command = @()
    
    try {
        switch ($engine) {
            "codex" {
                $model = $env:CODEX_REVIEW_MODEL -or "gpt-5.6-sol"
                $command = @("codex", "exec", "--sandbox", "read-only", "--ephemeral", "--model", $model, "--output-last-message", $outputFile, $reviewPrompt)
            }
            "claude" {
                $model = $env:CLAUDE_REVIEW_MODEL -or "opus"
                $command = @("claude", "--print", "--permission-mode", "bypassPermissions", "--no-session-persistence", "--max-turns", "8", "--max-budget-usd", "5", "--model", $model, "--output-format", "text", $reviewPrompt)
            }
            "antigravity" {
                $model = $env:ANTIGRAVITY_REVIEW_MODEL
                $command = @("agy", "--mode", "plan", "--dangerously-skip-permissions")
                if ($model) { $command += @("--model", $model) }
                $command += @("--add-dir", $Dir, "-p", $reviewPrompt)
            }
        }
        
        $commandExists = $null
        try {
            $commandExists = Get-Command $command[0] -ErrorAction SilentlyContinue
        } catch {
        }
        
        if (-not $commandExists) {
            Write-Host "REVIEWER=$engine MODEL=$model STATUS=UNAVAILABLE reason=command-missing"
            $failedEngines += $engine
            Remove-Item $outputFile, $errorFile -Force -ErrorAction SilentlyContinue
            continue
        }
        
        $runStatus = 0
        try {
            Push-Location $Dir
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            if ($engine -eq "claude" -or $engine -eq "antigravity") {
                $proc = Start-Process -FilePath $command[0] -ArgumentList $command[1..($command.Count-1)] -NoNewWindow -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -PassThru
                $timedOut = -not $proc.WaitForExit($Timeout * 1000)
                if ($timedOut) {
                    $proc.Kill()
                    $runStatus = 124
                } else {
                    $runStatus = $proc.ExitCode
                }
            } else {
                $proc = Start-Process -FilePath $command[0] -ArgumentList $command[1..($command.Count-1)] -NoNewWindow -RedirectStandardOutput $null -RedirectStandardError $errorFile -PassThru
                $timedOut = -not $proc.WaitForExit($Timeout * 1000)
                if ($timedOut) {
                    $proc.Kill()
                    $runStatus = 124
                } else {
                    $runStatus = $proc.ExitCode
                }
            }
            Pop-Location
        } catch {
            $runStatus = 1
            Pop-Location
        }
        
        if ($runStatus -ne 0 -or (Get-Item $outputFile).Length -eq 0) {
            Write-Host "REVIEWER=$engine MODEL=$model STATUS=UNAVAILABLE exit=$runStatus"
            $failedEngines += $engine
        } else {
            $output = Get-Content $outputFile -Raw
            $verdict = ""
            if ($output -match "VERDICT:\s*(APPROVE|REQUEST_CHANGES|NEEDS_DISCUSSION)") {
                $verdict = $matches[1]
            }
            
            if ([string]::IsNullOrWhiteSpace($verdict)) {
                Write-Host "REVIEWER=$engine MODEL=$model STATUS=INVALID_VERDICT"
                $failedEngines += $engine
            } else {
                Write-Host "REVIEWER=$engine MODEL=$model VERDICT=$verdict"
                if ($verdict -ne "APPROVE") {
                    $changeEngines += $engine
                }
            }
        }
        
        if ($ReportDir) {
            Copy-Item $outputFile "$ReportDir/$engine.md" -Force -ErrorAction SilentlyContinue
            Copy-Item $errorFile "$ReportDir/$engine.stderr.txt" -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item $outputFile, $errorFile -Force -ErrorAction SilentlyContinue
    }
}

if ($ReportDir) {
    $summary = @"
# Adversarial Review Summary

- trigger: $trigger
- changed_files: $($changedFiles.Count)
- code_files: $code_files
- documentation_files: $doc_files
- changed_lines: $changed_lines
- engines: $($selectedEngines -join ',')
"@
    Set-Content -Path "$ReportDir/summary.md" -Value $summary
}

if ($failedEngines.Count -gt 0 -and $changeEngines.Count -gt 0) {
    Write-Host "REVIEW_STATUS=UNAVAILABLE_AND_CHANGES_REQUESTED unavailable=$($failedEngines -join ',') changes=$($changeEngines -join ',')"
    exit 4
}
if ($failedEngines.Count -gt 0) {
    Write-Host "REVIEW_STATUS=UNAVAILABLE reviewers=$($failedEngines -join ',')"
    exit 4
}
if ($changeEngines.Count -gt 0) {
    Write-Host "REVIEW_STATUS=CHANGES_REQUESTED reviewers=$($changeEngines -join ',')"
    exit 2
}
Write-Host "REVIEW_STATUS=APPROVED"
exit 0
