. (Join-Path $PSScriptRoot 'common.ps1')
$script:AndroidRoot = Join-Path $ProjectRoot 'tools\android'
$script:AndroidSdk = Join-Path $AndroidRoot 'sdk'
$script:AndroidJava = Join-Path $AndroidRoot 'java\jdk-17.0.20.1+1'
$script:AndroidAdb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$script:AndroidKey = Join-Path $AndroidRoot 'development.keystore'

function Set-AndroidEnvironment {
    $env:JAVA_HOME = $AndroidJava
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:PATH = "$AndroidJava\bin;$AndroidSdk\platform-tools;$env:PATH"
}

function Ensure-Android {
    if (-not (Test-Path -LiteralPath $AndroidAdb) -or -not (Test-Path -LiteralPath $AndroidKey) -or -not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'build-tools\36.0.0\apksigner.bat')) -or -not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools\templates\4.7.2\android_debug.apk'))) {
        & (Join-Path $ProjectRoot 'SetupAndroid.ps1')
    }
    Set-AndroidEnvironment
    Start-AndroidServer
}

function Start-AndroidServer {
    # Separate log handles keep the persistent daemon from holding a build's output pipe.
    $starter = Start-Process -FilePath $AndroidAdb -ArgumentList 'start-server' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $AndroidRoot 'adb-start.log') -RedirectStandardError (Join-Path $AndroidRoot 'adb-start-errors.log')
    if (-not $starter.WaitForExit(10000)) { throw 'Android debugging service did not start.' }
    $starter.Refresh()
    if ($null -ne $starter.ExitCode -and $starter.ExitCode -ne 0) { throw 'Android debugging service did not start.' }
}

function Set-AndroidEditorSettings {
    $settingsDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Godot'
    $settingsFile = Join-Path $settingsDir 'editor_settings-4.7.tres'
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    $settingsText = "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n"
    if (Test-Path -LiteralPath $settingsFile) {
        if (-not (Test-Path -LiteralPath "$settingsFile.before-starring-android")) { Copy-Item -LiteralPath $settingsFile -Destination "$settingsFile.before-starring-android" }
        $settingsText = [IO.File]::ReadAllText($settingsFile)
    }
    $values = [ordered]@{
        'export/android/android_sdk_path' = $AndroidSdk.Replace('\','/')
        'export/android/java_sdk_path' = $AndroidJava.Replace('\','/')
        'export/android/debug_keystore' = $AndroidKey.Replace('\','/')
        'export/android/debug_keystore_user' = 'androiddebugkey'
        'export/android/debug_keystore_pass' = 'android'
        'export/android/shutdown_adb_on_exit' = $false
    }
    foreach ($key in $values.Keys) {
        $serialized = if ($values[$key] -is [bool]) { $values[$key].ToString().ToLowerInvariant() } else { '"' + $values[$key] + '"' }
        $entry = $key + ' = ' + $serialized
        $pattern = '(?m)^' + [regex]::Escape($key) + ' = .*\r?$'
        if ([regex]::IsMatch($settingsText,$pattern)) {
            $settingsText = [regex]::Replace($settingsText,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($match) $entry })
        } else { $settingsText += "`n$entry`n" }
    }
    [IO.File]::WriteAllText($settingsFile,$settingsText,(New-Object Text.UTF8Encoding($false)))
}
