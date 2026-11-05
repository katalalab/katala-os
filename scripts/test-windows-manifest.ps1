param([Parameter(Mandatory = $true)][string]$TestRoot)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($TestRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'TestRoot must be an existing directory' }
$work = Join-Path $root ('manifest-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$verifier = Join-Path $PSScriptRoot 'Test-FleetMirrorFreshness.ps1'
$shell = (Get-Process -Id $PID).Path
$artifact = Join-Path $work 'artifact.txt'
[IO.File]::WriteAllText($artifact, 'SYNTHETIC_DECOY')
$hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
$cases = 0
function Check-Manifest($label, $content, $expectedExit, $pattern) {
    $file = Join-Path $work ($label + '.json')
    [IO.File]::WriteAllText($file, $content)
    $result = & $shell -NoProfile -File $verifier -LockPath $file 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne $expectedExit -or $result -notmatch $pattern) { throw "$label expected $expectedExit / $pattern; actual $code / $result" }
    $script:cases++
}
$valid = @{ artifacts = @{ sample = @{ path = 'artifact.txt'; sha256 = $hash } } }
Check-Manifest 'valid' ($valid | ConvertTo-Json -Depth 5) 0 'checked: 1 artifacts; failures: 0'
Check-Manifest 'empty' '{"artifacts":{}}' 2 'invalid manifest'
Check-Manifest 'missing' '{}' 2 'invalid manifest'
Check-Manifest 'array' '{"artifacts":[]}' 2 'invalid manifest'
Check-Manifest 'null' '{"artifacts":null}' 2 'invalid manifest'
Check-Manifest 'nonobject-entry' '{"artifacts":{"sample":"invalid"}}' 2 'invalid manifest'
Check-Manifest 'missing-path' ('{"artifacts":{"sample":{"sha256":"' + $hash + '"}}}') 2 'invalid manifest'
Check-Manifest 'control-path' ('{"artifacts":{"sample":{"path":"bad\nname","sha256":"' + $hash + '"}}}') 2 'invalid manifest'
Check-Manifest 'bad-root-type' ('{"paths_relative_to":false,"artifacts":{"sample":{"path":"artifact.txt","sha256":"' + $hash + '"}}}') 2 'invalid manifest'
Check-Manifest 'malformed' '{broken' 2 'invalid manifest'
Check-Manifest 'bad-hash' '{"artifacts":{"sample":{"path":"artifact.txt","sha256":"abc"}}}' 2 'invalid manifest'
Check-Manifest 'drive-relative-artifact' ('{"artifacts":{"sample":{"path":"C:artifact.txt","sha256":"' + $hash + '"}}}') 2 'invalid manifest'
Check-Manifest 'drive-relative-root' ('{"paths_relative_to":"C:somewhere","artifacts":{"sample":{"path":"artifact.txt","sha256":"' + $hash + '"}}}') 2 'invalid manifest'
Check-Manifest 'current-drive-root' ('{"paths_relative_to":"\\somewhere","artifacts":{"sample":{"path":"artifact.txt","sha256":"' + $hash + '"}}}') 2 'invalid manifest'
$missingRoot = @{ paths_relative_to = 'not-present'; artifacts = $valid.artifacts }
Check-Manifest 'declared-missing' ($missingRoot | ConvertTo-Json -Depth 5) 1 '\[MISSING\]'
$missingAbsolute = @{ paths_relative_to = (Join-Path $work 'missing-root'); artifacts = $valid.artifacts }
Check-Manifest 'declared-absolute-missing' ($missingAbsolute | ConvertTo-Json -Depth 5) 1 '\[MISSING\]'
$selected = Join-Path $work 'selected root'
[IO.Directory]::CreateDirectory($selected) | Out-Null
[IO.File]::WriteAllText((Join-Path $selected 'artifact.txt'), 'SYNTHETIC_DIFFERENT')
$relative = @{ paths_relative_to = 'selected root'; artifacts = $valid.artifacts }
Check-Manifest 'relative-drift' ($relative | ConvertTo-Json -Depth 5) 1 '\[DRIFT\]'
[IO.File]::WriteAllText((Join-Path $selected 'artifact.txt'), 'SYNTHETIC_DECOY')
Check-Manifest 'relative-valid' ($relative | ConvertTo-Json -Depth 5) 0 'checked: 1 artifacts; failures: 0'
$absolute = @{ paths_relative_to = $selected; artifacts = $valid.artifacts }
Check-Manifest 'absolute-valid' ($absolute | ConvertTo-Json -Depth 5) 0 'checked: 1 artifacts; failures: 0'
[IO.File]::WriteAllText((Join-Path $work 'artifact[1].txt'), 'SYNTHETIC_DECOY')
$literal = @{ artifacts = @{ sample = @{ path = 'artifact[1].txt'; sha256 = $hash } } }
Check-Manifest 'literal-brackets' ($literal | ConvertTo-Json -Depth 5) 0 'checked: 1 artifacts; failures: 0'
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$missingResult = & $shell -NoProfile -File $verifier -LockPath (Join-Path $work 'absent.json') 2>&1 | Out-String
$ErrorActionPreference = $savedPreference
if ($LASTEXITCODE -ne 2 -or $missingResult -notmatch 'lock file missing:') { throw 'missing lock did not return exit 2' }
$cases++
$wrapper = Join-Path $work 'relative-wrapper.ps1'
[IO.File]::WriteAllText($wrapper, 'param($dir, $verifier) Set-Location -LiteralPath $dir; & $verifier -LockPath "valid.json"')
$relativeResult = & $shell -NoProfile -File $wrapper -dir $work -verifier $verifier 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $relativeResult -notmatch 'checked: 1 artifacts; failures: 0') { throw "relative lock from changed location failed: $relativeResult" }
$cases++
Write-Output "windows manifest verifier: $cases passed; fixture=$work"
