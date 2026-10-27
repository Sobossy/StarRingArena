param([switch]$SkipTemplates,[switch]$WebTemplates)
. (Join-Path $PSScriptRoot 'tools\common.ps1')
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cacheDir = Join-Path $ProjectRoot 'tools\cache'
$templateDir = Join-Path $ProjectRoot 'tools\templates\4.7.2'
New-Item -ItemType Directory -Path $cacheDir,$GodotDir,$templateDir -Force | Out-Null
$releaseUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable'
$editorArchive = 'Godot_v4.7.2-stable_win64.exe.zip'
$templateArchive = 'Godot_v4.7.2-stable_export_templates.tpz'
# Pinned SHA-512 values from the official release's SHA512-SUMS.txt.
$editorSha = '83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993'
$templateSha = 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079'

function Get-VerifiedArchive {
    param([string]$Name, [string]$Sha)
    $destination = Join-Path $cacheDir $Name
    if (-not (Test-Path -LiteralPath $destination)) {
        Write-Host "Downloading official Godot file: $Name"
        $partial = "$destination.partial"
        Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$Name" -OutFile $partial
        $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA512).Hash.ToLowerInvariant()
        if ($hash -ne $Sha) { throw "Checksum mismatch for $Name. Partial file retained for diagnosis." }
        Move-Item -LiteralPath $partial -Destination $destination -Force
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Sha) {
        throw "Checksum mismatch for cached $Name. Remove that cache file and run Setup.ps1 again."
    }
    return $destination
}

if (-not (Test-Path -LiteralPath $GodotConsole)) {
    $zipPath = Get-VerifiedArchive $editorArchive $editorSha
    Expand-Archive -LiteralPath $zipPath -DestinationPath $GodotDir -Force
}
$versionOutput = & $GodotConsole --version
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^4\.7\.2\.stable\.official\.') { throw 'Unexpected Godot executable version.' }
Write-Host "Engine ready: $versionOutput"

if (-not $SkipTemplates -and (-not (Test-Path -LiteralPath (Join-Path $templateDir 'windows_release_x86_64.exe')) -or -not (Test-Path -LiteralPath (Join-Path $templateDir 'windows_debug_x86_64.exe')))) {
    $zipPath = Get-VerifiedArchive $templateArchive $templateSha
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($name in @('windows_debug_x86_64.exe','windows_release_x86_64.exe','version.txt')) {
            $entry = $archive.GetEntry("templates/$name")
            if ($null -eq $entry) { throw "Official template archive missing $name." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDir $name), $true)
        }
    } finally { $archive.Dispose() }
    Write-Host 'Matching Windows x64 export templates ready.'
}

$fontsDir = Join-Path $ProjectRoot 'assets\fonts'
if ($WebTemplates) {
    $zipPath = Get-VerifiedArchive $templateArchive $templateSha
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($name in @('web_nothreads_debug.zip','web_nothreads_release.zip')) {
            $entry = $archive.GetEntry("templates/$name")
            if ($null -eq $entry) { throw "Official template archive missing $name." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDir $name), $true)
        }
    } finally { $archive.Dispose() }
    Write-Host 'Matching single-threaded Web export templates ready.'
}
New-Item -ItemType Directory -Path $fontsDir -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $fontsDir 'NotoSansSC.ttf'))) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf' -OutFile (Join-Path $fontsDir 'NotoSansSC.ttf')
}
if (-not (Test-Path -LiteralPath (Join-Path $fontsDir 'OFL.txt'))) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt' -OutFile (Join-Path $fontsDir 'OFL.txt')
}
Write-Host 'Setup complete. Run StartGame.cmd or OpenEditor.cmd.'
