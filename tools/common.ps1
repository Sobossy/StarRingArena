$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:GodotVersion = '4.7.2'
$script:GodotDir = Join-Path $ProjectRoot 'tools\godot\4.7.2'
$script:GodotConsole = Join-Path $GodotDir 'Godot_v4.7.2-stable_win64_console.exe'
$script:GodotEditor = Join-Path $GodotDir 'Godot_v4.7.2-stable_win64.exe'

function Ensure-Godot {
    param([switch]$Templates)
    if (-not (Test-Path -LiteralPath $GodotConsole)) {
        & (Join-Path $ProjectRoot 'Setup.ps1') -SkipTemplates:(-not $Templates)
    } elseif ($Templates -and -not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools\templates\4.7.2\windows_release_x86_64.exe'))) {
        & (Join-Path $ProjectRoot 'Setup.ps1')
    }
    if (-not (Test-Path -LiteralPath $GodotConsole)) { throw 'Godot setup did not finish.' }
}

function Invoke-GodotChecked {
    param([string[]]$GodotArguments)
    $engineOutput = & $GodotConsole @GodotArguments 2>&1
    $engineExitCode = $LASTEXITCODE
    $engineOutput | Write-Host
    if ($engineExitCode -ne 0 -or (($engineOutput | Out-String) -match 'SCRIPT ERROR:|ERROR:')) {
        throw "Godot failed (exit code $engineExitCode). See the diagnostic output above."
    }
}
