param([string]$Device,[switch]$Logs)
. (Join-Path $PSScriptRoot 'tools\android-tools.ps1')
Ensure-Android
if (-not $Device) {
    $available = @(& $AndroidAdb devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
    if ($available.Count -ne 1) { & $AndroidAdb devices -l; throw 'Connect and authorize exactly one phone, or specify -Device SERIAL.' }
    $Device = $available[0]
}
$apk = Join-Path $ProjectRoot 'build\Android\StarRingArena.apk'
if (-not (Test-Path -LiteralPath $apk)) { throw 'Run BuildAndroid.ps1 first.' }
& $AndroidAdb -s $Device install --no-streaming -r $apk
if ($LASTEXITCODE -ne 0) { throw 'Phone installation failed. Check the confirmation on the phone; existing saves were not removed.' }
$activity = @(& $AndroidAdb -s $Device shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 'com.starringarena.game' | Where-Object { $_ -match '^com\.starringarena\.game/' })
if ($activity.Count -ne 1) { throw 'Cannot resolve the game launcher activity.' }
& $AndroidAdb -s $Device shell am start -n $activity[0].Trim()
if ($LASTEXITCODE -ne 0) { throw 'Phone launch failed.' }
if ($Logs) { & $AndroidAdb -s $Device logcat -s godot }
