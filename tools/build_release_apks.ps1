# Universal APK is the primary download; optional smaller per-ABI downloads.
param([switch]$IncludeArchitectureApks)

$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Universal release APK build failed.' }
    $outputs = @('build/app/outputs/flutter-apk/app-release.apk')
    if ($IncludeArchitectureApks) {
        & flutter build apk --release --split-per-abi
        if ($LASTEXITCODE -ne 0) { throw 'Architecture APK build failed.' }
        $outputs += 'build/app/outputs/flutter-apk/app-*-release.apk'
    }
    Get-ChildItem -Path $outputs |
        Select-Object Name, @{Name='DownloadMB'; Expression={[math]::Round($_.Length / 1000000, 2)}}
} finally {
    Pop-Location
}
