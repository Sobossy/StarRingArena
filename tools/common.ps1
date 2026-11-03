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
    $logDir = Join-Path $ProjectRoot 'build'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ([IO.Path]::GetRandomFileName() + '.log')
    $errorPath = $logPath + '.stderr.log'
    try {
        # Invoke the engine directly: the console forwarding launcher can hang
        # without starting its child process on some Windows sessions.
        $quotedArguments = $GodotArguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }
        $engineProcess = Start-Process -FilePath $GodotEditor -ArgumentList $quotedArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
        $engineProcess.WaitForExit()
        $engineExitCode = $engineProcess.ExitCode
        $engineOutput = @([IO.File]::ReadAllText($logPath),[IO.File]::ReadAllText($errorPath))
    } finally {
        if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath }
        if (Test-Path -LiteralPath $errorPath) { Remove-Item -LiteralPath $errorPath }
        if ($null -ne $engineProcess) { $engineProcess.Dispose() }
    }
    $engineOutput | Write-Host
    if ($engineExitCode -ne 0 -or (($engineOutput | Out-String) -match 'SCRIPT ERROR:|ERROR:')) {
        throw "Godot failed (exit code $engineExitCode). See the diagnostic output above."
    }
}
