# 预下载 media_kit Android libmpv JAR（构建时 Gradle 从 GitHub 拉取易超时）
# 用法：.\tool\download_media_kit_android_libs.ps1
# 可选代理：与 android/gradle-proxy.properties 相同，默认 127.0.0.1:7890

$ErrorActionPreference = "Stop"
$version = "1.3.8"
$tag = "v1.1.7"
$base = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\media_kit_libs_android_video-$version\android\build\$tag"
New-Item -ItemType Directory -Force -Path $base | Out-Null

$proxyHost = "127.0.0.1"
$proxyPort = 7890
$proxyFile = Join-Path (Split-Path $PSScriptRoot -Parent) "android\gradle-proxy.properties"
if (Test-Path $proxyFile) {
    foreach ($line in Get-Content $proxyFile) {
        if ($line -match 'systemProp\.https\.proxyHost=(.+)') { $proxyHost = $Matches[1].Trim() }
        if ($line -match 'systemProp\.https\.proxyPort=(.+)') { $proxyPort = $Matches[1].Trim() }
    }
}
$proxy = "http://${proxyHost}:${proxyPort}"

$files = @(
    "default-arm64-v8a.jar",
    "default-armeabi-v7a.jar",
    "default-x86_64.jar",
    "default-x86.jar"
)

foreach ($name in $files) {
    $dest = Join-Path $base $name
    if (Test-Path $dest) {
        Write-Host "skip $name"
        continue
    }
    $url = "https://github.com/media-kit/libmpv-android-video-build/releases/download/$tag/$name"
    Write-Host "download $name ..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 600 -Proxy $proxy
}

Write-Host "done -> $base"
