param([switch]$SkipBuild)
. (Join-Path $PSScriptRoot 'tools\common.ps1')
if (-not $SkipBuild) { & (Join-Path $ProjectRoot 'Build.ps1') }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$buildDir = Join-Path $ProjectRoot 'build'
$windowsDir = Join-Path $buildDir 'Windows'
$windowsZip = Join-Path $buildDir 'StarRingArena-Windows.zip'
$sourceZip = Join-Path $buildDir 'StarRingArena-Source.zip'
$androidZip = Join-Path $buildDir 'StarRingArena-Android.zip'
foreach ($required in @('SpiritArena.exe','SpiritArena.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $windowsDir $required))) { throw 'Build the Windows version before packaging.' }
}
# Only replace these two named artifacts inside this project's build directory.
if (Test-Path -LiteralPath $windowsZip) { Remove-Item -LiteralPath $windowsZip }
[IO.Compression.ZipFile]::CreateFromDirectory($windowsDir,$windowsZip,[IO.Compression.CompressionLevel]::Optimal,$true)
$androidDir = Join-Path $buildDir 'Android'
if (Test-Path -LiteralPath (Join-Path $androidDir 'StarRingArena.apk')) {
    if (Test-Path -LiteralPath $androidZip) { Remove-Item -LiteralPath $androidZip }
    [IO.Compression.ZipFile]::CreateFromDirectory($androidDir,$androidZip,[IO.Compression.CompressionLevel]::Optimal,$true)
}
$sourceFiles = @()
foreach ($folder in @('assets','data','docs','examples','scenes','scripts','tests')) {
    $sourceFiles += Get-ChildItem -LiteralPath (Join-Path $ProjectRoot $folder) -Recurse -File
}
$sourceFiles += Get-ChildItem -LiteralPath $ProjectRoot -File | Where-Object { $_.Extension -in @('.ps1','.cmd','.md','.godot','.tscn','.cfg') -or $_.Name -eq '.gitignore' }
$sourceFiles += Get-Item -LiteralPath (Join-Path $ProjectRoot 'tools\common.ps1'),(Join-Path $ProjectRoot 'tools\.gdignore')
$sourceFiles += Get-Item -LiteralPath (Join-Path $ProjectRoot 'tools\android-tools.ps1')
$sourceFiles += Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tools\licenses') -File
$stream = [IO.File]::Open($sourceZip,[IO.FileMode]::Create)
$archive = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $sourceFiles | Sort-Object FullName -Unique) {
        $relative = $file.FullName.Substring($ProjectRoot.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,('StarRingArena-Source/' + $relative),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
Get-Item -LiteralPath $windowsZip,$sourceZip | Select-Object Name,Length | Format-Table -AutoSize
