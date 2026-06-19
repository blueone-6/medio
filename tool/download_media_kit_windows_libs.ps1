# Pre-download and pre-extract libmpv + ANGLE for media_kit_libs_windows_video.
#
# Archives and extracted trees must live under build\windows\x64\ (plugin
# CMAKE_BINARY_DIR). CMake 4.x (VS 2026+) often fails to extract .7z via
# `cmake -E tar xzf`; pre-extracting here skips that step when libmpv/ and
# ANGLE/ are already populated.
param(
  [string] $FullLibMpvArchivePath = '',
  [string] $FullLibMpvArchiveName = 'mpv-dev-x86_64-20250202-git-38ad1ed.7z'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outDir = Join-Path $repoRoot 'build\windows\x64'
$legacyPluginDir = Join-Path $repoRoot 'build\windows\x64\plugins\media_kit_libs_windows_video'
$cacheDir = Join-Path $PSScriptRoot '.cache'
New-Item -ItemType Directory -Force -Path $outDir, $cacheDir | Out-Null

function Get-SevenZip {
  $candidates = @(
    (Join-Path $cacheDir '7zr.exe'),
    "${env:ProgramFiles}\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
  )
  foreach ($path in $candidates) {
    if (Test-Path $path) { return $path }
  }
  $7zr = Join-Path $cacheDir '7zr.exe'
  Write-Host "Downloading 7zr.exe -> $7zr"
  Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $7zr -UseBasicParsing
  return $7zr
}

function Ensure-VerifiedArchive {
  param(
    [Parameter(Mandatory = $true)][string] $Url,
    [Parameter(Mandatory = $true)][string] $ExpectedMd5Lower,
    [Parameter(Mandatory = $true)][string] $DestPath
  )
  if (Test-Path $DestPath) {
    $existing = (Get-FileHash -Path $DestPath -Algorithm MD5).Hash.ToLowerInvariant()
    if ($existing -eq $ExpectedMd5Lower) {
      Write-Host "Skip (already valid): $DestPath"
      return
    }
    Write-Host "Removing bad archive (md5 $existing): $DestPath"
    Remove-Item -Force $DestPath
  }
  Write-Host "Downloading:`n  $Url`n  -> $DestPath"
  Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing
  $hash = (Get-FileHash -Path $DestPath -Algorithm MD5).Hash.ToLowerInvariant()
  if ($hash -ne $ExpectedMd5Lower) {
    Remove-Item -Force $DestPath -ErrorAction SilentlyContinue
    throw "MD5 mismatch for $DestPath expected $ExpectedMd5Lower got $hash"
  }
  Write-Host "Verified: $DestPath"
}

function Test-Is7zArchive {
  param([Parameter(Mandatory = $true)][string] $Path)
  if (-not (Test-Path $Path)) { return $false }
  $len = (Get-Item $Path).Length
  if ($len -lt 1MB) { return $false }
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $buf = New-Object byte[] 6
    if ($fs.Read($buf, 0, 6) -lt 3) { return $false }
    return ($buf[0] -eq 0x37 -and $buf[1] -eq 0x7A -and $buf[2] -eq 0xBC)
  }
  finally {
    $fs.Dispose()
  }
}

function Ensure-SevenZipArchive {
  param(
    [Parameter(Mandatory = $true)][string] $Url,
    [Parameter(Mandatory = $true)][string] $DestPath,
    [Parameter(Mandatory = $true)][string] $ArchiveName
  )
  if (Test-Is7zArchive $DestPath) {
    Write-Host "Skip (valid 7z already): $DestPath"
    return
  }
  if (Test-Path $DestPath) {
    Write-Host "Removing invalid archive (not a 7z): $DestPath"
    Remove-Item -Force $DestPath
  }

  Write-Host "Downloading full libmpv archive:`n  $Url`n  -> $DestPath"
  $headers = @{ 'User-Agent' = 'media_client-download-libmpv/1.0' }
  Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing -Headers $headers
  if (-not (Test-Is7zArchive $DestPath)) {
    Remove-Item -Force $DestPath -ErrorAction SilentlyContinue
    throw @"
Downloaded full libmpv file is not a valid .7z archive.
Try manually:
  1. Download $ArchiveName from https://sourceforge.net/projects/mpv-player-windows/files/libmpv/
  2. Run: .\tool\download_media_kit_windows_libs.ps1 -FullLibMpvArchivePath <path-to-.7z>
"@
  }
  Write-Host "Verified 7z archive: $DestPath"
}

function Migrate-LegacyArchive {
  param(
    [Parameter(Mandatory = $true)][string] $FileName,
    [Parameter(Mandatory = $true)][string] $ExpectedMd5Lower,
    [Parameter(Mandatory = $true)][string] $DestPath
  )
  if (Test-Path $DestPath) { return }
  foreach ($legacyDir in @($legacyPluginDir, $outDir)) {
    $legacyPath = Join-Path $legacyDir $FileName
    if (-not (Test-Path $legacyPath)) { continue }
    $hash = (Get-FileHash -Path $legacyPath -Algorithm MD5).Hash.ToLowerInvariant()
    if ($hash -ne $ExpectedMd5Lower) { continue }
    Write-Host "Moving legacy archive -> $DestPath"
    Move-Item -Force $legacyPath $DestPath
    return
  }
}

function Test-DirNotEmpty {
  param([Parameter(Mandatory = $true)][string] $Dir)
  return (Test-Path $Dir) -and ((Get-ChildItem -Path $Dir -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
}

function Extract-SevenZip {
  param(
    [Parameter(Mandatory = $true)][string] $ArchivePath,
    [Parameter(Mandatory = $true)][string] $DestDir,
    [Parameter(Mandatory = $true)][string] $SevenZip,
    [switch] $ForceRefresh
  )
  if ((-not $ForceRefresh) -and (Test-DirNotEmpty $DestDir)) {
    Write-Host "Skip extract (already populated): $DestDir"
    return
  }
  if (Test-Path $DestDir) {
    Remove-Item -Recurse -Force $DestDir
  }
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  Write-Host "Extracting $ArchivePath -> $DestDir"
  & $SevenZip x $ArchivePath "-o$DestDir" -y | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Remove-Item -Recurse -Force $DestDir -ErrorAction SilentlyContinue
    throw "7-Zip failed (exit $LASTEXITCODE) for $ArchivePath"
  }
}

function Test-FullLibMpvReady {
  param(
    [Parameter(Mandatory = $true)][string] $LibMpvDir,
    [Parameter(Mandatory = $true)][string] $MarkerPath,
    [Parameter(Mandatory = $true)][string] $ArchiveName
  )
  if (-not (Test-Path (Join-Path $LibMpvDir 'libmpv-2.dll'))) { return $false }
  if (-not (Test-Path $MarkerPath)) { return $false }
  $marker = (Get-Content -LiteralPath $MarkerPath -Raw).Trim()
  return $marker -eq $ArchiveName
}

function Sync-LibMpvRuntimeDlls {
  param([Parameter(Mandatory = $true)][string] $LibMpvDir)
  foreach ($sub in @('Debug', 'Release', 'Profile')) {
    $runnerDir = Join-Path $repoRoot "build\windows\x64\runner\$sub"
    if (-not (Test-Path $runnerDir)) { continue }
    try {
      Get-ChildItem -Path $LibMpvDir -Filter '*.dll' |
        Copy-Item -Force -Destination $runnerDir -ErrorAction Stop
      Write-Host "Synced full libmpv DLLs -> $runnerDir"
    }
    catch {
      Write-Warning "Could not sync full libmpv DLLs to $runnerDir. Close the running app and rebuild to refresh it. $($_.Exception.Message)"
    }
  }
}

function Normalize-LibMpvLayout {
  param([Parameter(Mandatory = $true)][string] $LibMpvDir)
  $includeMpv = Join-Path $LibMpvDir 'include\mpv'
  if (-not (Test-Path $includeMpv)) { return }
  $mpvTemp = Join-Path $LibMpvDir 'mpv'
  Copy-Item -Path $includeMpv -Destination $mpvTemp -Recurse -Force
  Remove-Item -Recurse -Force (Join-Path $LibMpvDir 'include')
  Rename-Item -Path $mpvTemp -NewName 'include'
}

# Must match media_kit_libs_windows_video windows/CMakeLists.txt (package 1.0.11).
# CMake verifies this archive even when libmpv/ is already populated. Keep it
# present, but use the fuller SourceForge mpv-dev build below for runtime DLLs.
$mediaKitMpvName = 'mpv-dev-x86_64-20230924-git-652a1dd.7z'
$mediaKitMpvDest = Join-Path $outDir $mediaKitMpvName
Migrate-LegacyArchive -FileName $mediaKitMpvName -ExpectedMd5Lower 'a832ef24b3a6ff97cd2560b5b9d04cd8' -DestPath $mediaKitMpvDest
Ensure-VerifiedArchive `
  -Url 'https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z' `
  -ExpectedMd5Lower 'a832ef24b3a6ff97cd2560b5b9d04cd8' `
  -DestPath $mediaKitMpvDest

if ([string]::IsNullOrWhiteSpace($FullLibMpvArchivePath)) {
  $FullLibMpvArchivePath = Join-Path $cacheDir $FullLibMpvArchiveName
  Ensure-SevenZipArchive `
    -Url "https://downloads.sourceforge.net/project/mpv-player-windows/libmpv/$FullLibMpvArchiveName" `
    -DestPath $FullLibMpvArchivePath `
    -ArchiveName $FullLibMpvArchiveName
} elseif (-not (Test-Is7zArchive $FullLibMpvArchivePath)) {
  throw "Not a valid .7z archive: $FullLibMpvArchivePath"
}

$angleDest = Join-Path $outDir 'ANGLE.7z'
Migrate-LegacyArchive -FileName 'ANGLE.7z' -ExpectedMd5Lower 'e866f13e8d552348058afaafe869b1ed' -DestPath $angleDest
Ensure-VerifiedArchive `
  -Url 'https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z' `
  -ExpectedMd5Lower 'e866f13e8d552348058afaafe869b1ed' `
  -DestPath $angleDest

$sevenZip = Get-SevenZip
$libMpvDir = Join-Path $outDir 'libmpv'
$angleDir = Join-Path $outDir 'ANGLE'
$fullLibMpvMarker = Join-Path $libMpvDir '.media_client_full_libmpv'

if (Test-FullLibMpvReady -LibMpvDir $libMpvDir -MarkerPath $fullLibMpvMarker -ArchiveName $FullLibMpvArchiveName) {
  Write-Host "Skip full libmpv extract (already active): $libMpvDir"
} else {
  Extract-SevenZip -ArchivePath $FullLibMpvArchivePath -DestDir $libMpvDir -SevenZip $sevenZip -ForceRefresh
  Normalize-LibMpvLayout -LibMpvDir $libMpvDir
  Set-Content -LiteralPath $fullLibMpvMarker -Value $FullLibMpvArchiveName -Encoding ASCII
}
Extract-SevenZip -ArchivePath $angleDest -DestDir $angleDir -SevenZip $sevenZip

if (-not (Test-Path (Join-Path $libMpvDir 'libmpv-2.dll'))) {
  throw "libmpv extract incomplete: missing libmpv-2.dll in $libMpvDir"
}
if (-not (Test-Path (Join-Path $angleDir 'libGLESv2.dll'))) {
  throw "ANGLE extract incomplete: missing libGLESv2.dll in $angleDir"
}

Sync-LibMpvRuntimeDlls -LibMpvDir $libMpvDir

Write-Host 'All media_kit Windows archives are present. Full libmpv is active for PGS / special subtitles.'
