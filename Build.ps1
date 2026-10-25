param([switch]$SkipTests)
. (Join-Path $PSScriptRoot 'tools\common.ps1')
Ensure-Godot -Templates
if (-not $SkipTests) { & (Join-Path $ProjectRoot 'Test.ps1') }
$outputDir = Join-Path $ProjectRoot 'build\Windows'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--editor','--import')
Invoke-GodotChecked -GodotArguments @('--headless','--path',$ProjectRoot,'--export-release','Windows Desktop',(Join-Path $outputDir 'SpiritArena.exe'))
foreach ($file in @('README.md','THIRD_PARTY_NOTICES.md')) {
    $source = Join-Path $ProjectRoot $file
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $outputDir $file) -Force }
}
$docsDir = Join-Path $outputDir 'docs'
New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'docs') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $docsDir $_.Name) -Force
}
$exampleDocsDir = Join-Path $outputDir 'examples\wind_pulse'
New-Item -ItemType Directory -Path $exampleDocsDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'examples\wind_pulse\README.md') -Destination (Join-Path $exampleDocsDir 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $outputDir 'FONT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\licenses\GODOT-LICENSE.txt') -Destination (Join-Path $outputDir 'GODOT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\licenses\GODOT-COPYRIGHT.txt') -Destination (Join-Path $outputDir 'GODOT-COPYRIGHT.txt') -Force
foreach ($name in @('SpiritArena.exe','SpiritArena.pck')) {
    $artifact = Join-Path $outputDir $name
    if (-not (Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).Length -le 0) {
        throw "Export did not create the required file: $artifact"
    }
}
Write-Host "Build ready: $outputDir\SpiritArena.exe"
