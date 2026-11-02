# Padding is configured in pubspec.yaml, so direct regeneration is safe too.
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & dart run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw 'Launcher icon generation failed.' }
} finally {
    Pop-Location
}
