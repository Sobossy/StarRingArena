. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'test-results') -Force | Out-Null
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import')
$output = & $GodotConsole --headless --path $ProjectRoot --script res://tests/test_runner.gd 2>&1
$exitCode = $LASTEXITCODE
$output | Tee-Object -FilePath (Join-Path $ProjectRoot 'test-results\latest.log') | Write-Host
if ($exitCode -ne 0 -or (($output | Out-String) -match 'SCRIPT ERROR:|ERROR:') -or (($output | Out-String) -notmatch 'ALL TESTS PASSED')) {
    throw 'Regression tests failed. See test-results/latest.log.'
}
$uiOutput = & $GodotConsole --headless --path $ProjectRoot --script res://tests/ui_smoke.gd 2>&1
$uiExitCode = $LASTEXITCODE
$uiOutput | Tee-Object -FilePath (Join-Path $ProjectRoot 'test-results\ui-latest.log') | Write-Host
if ($uiExitCode -ne 0 -or (($uiOutput | Out-String) -match 'SCRIPT ERROR:|ERROR:') -or (($uiOutput | Out-String) -notmatch 'UI TESTS PASSED')) {
    throw 'UI integration tests failed. See test-results/ui-latest.log.'
}
