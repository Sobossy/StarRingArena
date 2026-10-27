. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot
$templateDir = Join-Path $ProjectRoot 'tools\templates\4.7.2'
if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'web_nothreads_release.zip')) -or -not (Test-Path -LiteralPath (Join-Path $templateDir 'web_nothreads_debug.zip'))) {
    & (Join-Path $ProjectRoot 'Setup.ps1') -SkipTemplates -WebTemplates
}
$outputDir = Join-Path $ProjectRoot 'build\Web'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import','--quit')
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--export-release','Web',(Join-Path $outputDir 'index.html'))
foreach ($name in @('index.html','index.js','index.wasm','index.pck')) {
    $artifact = Join-Path $outputDir $name
    if (-not (Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).Length -le 0) {
        throw "Missing Web export: $artifact"
    }
}
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'THIRD_PARTY_NOTICES.md') -Destination $outputDir -Force
$licenseDir = Join-Path $outputDir 'licenses'
New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
Copy-Item -Path (Join-Path $ProjectRoot 'tools\licenses\*.txt') -Destination $licenseDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $licenseDir 'FONT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets\licenses\CONTENT-NOTICES.txt') -Destination $licenseDir -Force
$zipPath = Join-Path $ProjectRoot 'build\StarRingArena-Web.zip'
Compress-Archive -Path (Join-Path $outputDir '*') -DestinationPath $zipPath -Force
Write-Host "Web upload ready: $zipPath"
