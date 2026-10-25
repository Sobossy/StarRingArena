param([switch]$Extended)
. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'test-results') -Force | Out-Null
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import')
foreach ($suite in @('current_rules','yunli_tests','current_ui_smoke','mobile_tests')) {
    $arguments = @('--headless','--path',$ProjectRoot,'--script',"res://tests/$suite.gd")
    if ($Extended -and $suite -eq 'current_rules') { $arguments += @('--','--extended') }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = & $GodotConsole @arguments 2>&1
        $resultCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    $result | Tee-Object -FilePath (Join-Path $ProjectRoot "test-results\$suite-latest.log") | Write-Host
    if ($resultCode -ne 0 -or (($result | Out-String) -match 'SCRIPT ERROR:|ERROR:|leaked at exit') -or (($result | Out-String) -notmatch 'TESTS PASSED')) { throw "$suite failed." }
}
foreach ($phase in @('write','read')) {
    $arguments = @('--headless','--path',$ProjectRoot,'--script','res://tests/persistence_roundtrip.gd')
    if ($phase -eq 'write') { $arguments += @('--','--write') }
    Invoke-GodotChecked -GodotArguments $arguments
}
