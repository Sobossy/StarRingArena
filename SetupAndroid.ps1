. (Join-Path $PSScriptRoot 'tools\android-tools.ps1')
Ensure-Godot -Templates
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Path $AndroidRoot,$AndroidSdk,(Join-Path $AndroidRoot 'java') -Force | Out-Null

function Get-AndroidArchive {
    param([string]$Url,[string]$Name,[string]$Hash,[string]$Algorithm)
    $destination = Join-Path $ProjectRoot "tools\cache\$Name"
    if (-not (Test-Path -LiteralPath $destination)) {
        Write-Host "Downloading $Name"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile "$destination.partial"
        if ((Get-FileHash -LiteralPath "$destination.partial" -Algorithm $Algorithm).Hash.ToLowerInvariant() -ne $Hash) { throw "Checksum mismatch: $Name" }
        Move-Item -LiteralPath "$destination.partial" -Destination $destination -Force
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm $Algorithm).Hash.ToLowerInvariant() -ne $Hash) { throw "Cached checksum mismatch: $Name" }
    return $destination
}

if (-not (Test-Path -LiteralPath (Join-Path $AndroidJava 'bin\java.exe'))) {
    $jdkArchive = Get-AndroidArchive 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip' 'OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip' 'e53a79c3c3d86865bd7e787903884331068e71321714ffd44f145785affc7cb0' 'SHA256'
    Expand-Archive -LiteralPath $jdkArchive -DestinationPath (Join-Path $AndroidRoot 'java') -Force
}
$manager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $manager)) {
    $sdkArchive = Get-AndroidArchive 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip' 'commandlinetools-win-16111833_latest.zip' '57d04f2d75eb8e8fffc5000a987e5de4b5a63e9d' 'SHA1'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($sdkArchive)
    $destinationRoot = [IO.Path]::GetFullPath((Join-Path $AndroidSdk 'cmdline-tools\latest'))
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.StartsWith('cmdline-tools/') -and $entry.Name) {
                $relative = $entry.FullName.Substring('cmdline-tools/'.Length)
                $destination = [IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
                if (-not $destination.StartsWith($destinationRoot + '\')) { throw 'Archive entry escapes Android tools folder.' }
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination,$true)
            }
        }
    } finally { $archive.Dispose() }
}
Set-AndroidEnvironment
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'build-tools\36.0.0\apksigner.bat')) -or -not (Test-Path -LiteralPath $AndroidAdb)) {
    # Pinned command-line tools use slash package IDs; Godot 4.7 targets SDK 36.
    & (Join-Path $AndroidSdk 'cmdline-tools\latest\bin\android.exe') --no-metrics --sdk=$AndroidSdk sdk install 'platform-tools' 'build-tools/36.0.0' 'platforms/android-36'
    if ($LASTEXITCODE -ne 0) { throw 'Android SDK installation failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'build-tools\36.0.0\apksigner.bat'))) { throw 'Android build tools were not installed.' }
}
if (-not (Test-Path -LiteralPath $AndroidKey)) {
    & (Join-Path $AndroidJava 'bin\keytool.exe') -genkeypair -keystore $AndroidKey -storepass android -keypass android -alias androiddebugkey -dname 'CN=StarRingArena Development' -keyalg RSA -keysize 2048 -validity 10000
    if ($LASTEXITCODE -ne 0) { throw 'Development signing key generation failed.' }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$templateArchive = Join-Path $ProjectRoot 'tools\cache\Godot_v4.7.2-stable_export_templates.tpz'
if ((Get-FileHash -LiteralPath $templateArchive -Algorithm SHA512).Hash.ToLowerInvariant() -ne 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079') { throw 'Godot template checksum mismatch.' }
$archive = [IO.Compression.ZipFile]::OpenRead($templateArchive)
try {
    foreach ($name in @('android_debug.apk','android_release.apk')) {
        $destination = Join-Path $ProjectRoot "tools\templates\4.7.2\$name"
        if (-not (Test-Path -LiteralPath $destination)) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry("templates/$name"),$destination,$true)
        }
    }
} finally { $archive.Dispose() }
Write-Host 'Android tools ready. Connect a phone with USB debugging to install the test APK.'
Start-AndroidServer
& $AndroidAdb devices -l
