param([switch]$Install,[string]$Device)
. (Join-Path $PSScriptRoot 'tools\android-tools.ps1')
Ensure-Godot -Templates
Ensure-Android
Set-AndroidEditorSettings
$outputDir = Join-Path $ProjectRoot 'build\Android'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import','--quit')
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--export-debug','Android Test',(Join-Path $outputDir 'StarRingArena.apk'))
& (Join-Path $AndroidSdk 'build-tools\36.0.0\apksigner.bat') verify --verbose (Join-Path $outputDir 'StarRingArena.apk')
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
$docsDir = Join-Path $outputDir 'docs'
New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'docs') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $docsDir -Force }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'THIRD_PARTY_NOTICES.md') -Destination $outputDir -Force
Write-Host "Android test APK ready: $outputDir\StarRingArena.apk"
if ($Install) { & (Join-Path $ProjectRoot 'InstallAndroid.ps1') -Device $Device }
