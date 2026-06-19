# Package the Medio Community Windows x64 release into a redistributable zip.
#
# Usage:
#   .\tool\pack_medio_zip.ps1 [-Version 1.0.0] [-SkipBuild]
#
# Version defaults to the `version:` field in pubspec.yaml (without build number).
# Override with -Version if needed.
#
# Steps:
#   1. (unless -SkipBuild) run build.ps1 windows
#   2. assemble dist/medio-community-<ver>-windows-x64/ with:
#        - medio.exe + DLLs + data/   (from build/windows/x64/runner/Release)
#        - LICENSE                    (GPLv3-or-later, repo root)
#        - THIRD_PARTY_NOTICES.md
#        - DISCLAIMER.md
#        - README.txt                 (short pointer file, generated)
#   3. zip into dist/medio-community-<ver>-windows-x64.zip
#
# Notes:
#   - Requires the Windows binary to have been renamed to `medio.exe` via the
#     CMakeLists.txt change (BINARY_NAME=medio). The script will fail loudly
#     if it does not find medio.exe in the Release directory.

param(
    [string]$Version = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$repoRoot   = Split-Path -Parent $PSScriptRoot

# Resolve version: explicit -Version wins, otherwise read from pubspec.yaml
if (-not $Version) {
    $pubspec = Join-Path $repoRoot "pubspec.yaml"
    $match = Select-String -Path $pubspec -Pattern "^version:\s*(\S+)"
    if (-not $match) { throw "Could not read version from pubspec.yaml" }
    $Version = $match.Matches.Groups[1].Value
    if ($Version -match "\+") { $Version = $Version.Split("+")[0] }
}
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$distDir    = Join-Path $repoRoot "dist"
$stageName  = "medio-community-$Version-windows-x64"
$stageDir   = Join-Path $distDir $stageName
$zipPath    = Join-Path $distDir "$stageName.zip"

function Write-Step($msg) { Write-Host "[pack] $msg" -ForegroundColor Cyan }

# 1. Build community windows release
if (-not $SkipBuild) {
    Write-Step "Building Medio Community (windows)..."
    & (Join-Path $PSScriptRoot "build.ps1") windows
    if ($LASTEXITCODE -ne 0) {
        throw "build.ps1 windows failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Step "Skipping build (--SkipBuild)."
}

# 2. Sanity-check the produced binary
$exePath = Join-Path $releaseDir "medio.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    $existing = Get-ChildItem -LiteralPath $releaseDir -Filter *.exe -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
    throw "Expected medio.exe in '$releaseDir' but found: $($existing -join ', '). Did windows/CMakeLists.txt set BINARY_NAME=medio? Re-run a clean flutter build."
}

# 3. Stage directory
if (Test-Path -LiteralPath $stageDir) {
    Write-Step "Removing stale stage dir: $stageDir"
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}
Write-Step "Staging release into $stageDir"
New-Item -ItemType Directory -Path $stageDir | Out-Null

# Copy everything from Release/ except msix and any leftover media_client.exe
Get-ChildItem -LiteralPath $releaseDir | Where-Object {
    $_.Name -notlike "*.msix" -and $_.Name -ne "media_client.exe"
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stageDir -Recurse -Force
}

# Copy legal/info files from repo root
foreach ($file in @("LICENSE", "DISCLAIMER.md", "THIRD_PARTY_NOTICES.md")) {
    $src = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing required file at repo root: $file"
    }
    Copy-Item -LiteralPath $src -Destination $stageDir -Force
}

# Generate README.txt
$readme = @"
Medio Community $Version (Windows x64)
========================================

This archive contains the open-source community build of Medio,
a cross-platform self-hosted media client.

Run:           medio.exe
License:       see LICENSE  (GNU GPL v3 or later)
Disclaimer:    see DISCLAIMER.md
3rd-party:     see THIRD_PARTY_NOTICES.md
Third-party:   see THIRD_PARTY_NOTICES.md

Source code and issue tracker: see the project repository.
"@
$readmePath = Join-Path $stageDir "README.txt"
[System.IO.File]::WriteAllText($readmePath, $readme, (New-Object System.Text.UTF8Encoding $false))

# 4. Zip
if (Test-Path -LiteralPath $zipPath) {
    Write-Step "Removing stale zip: $zipPath"
    Remove-Item -LiteralPath $zipPath -Force
}
Write-Step "Compressing -> $zipPath"
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

# 5. Summary
$zipSize = (Get-Item -LiteralPath $zipPath).Length
$mb = [Math]::Round($zipSize / 1MB, 2)
Write-Host ""
Write-Host "[pack] Done." -ForegroundColor Green
Write-Host "[pack] Stage : $stageDir"
Write-Host "[pack] Zip   : $zipPath  ($mb MB)"
Write-Host ""
