# 预下载 media_kit Android libmpv JAR（构建时 Gradle 从 GitHub 拉取易超时）
# 用法：.\tool\download_media_kit_android_libs.ps1
# 可选代理：若需通过代理访问 GitHub，请提前设置 HTTPS_PROXY 环境变量，
#           例如（PowerShell）：$env:HTTPS_PROXY = "http://你的代理地址:端口"
#           未设置则直连。

$ErrorActionPreference = "Stop"
$version = "1.3.8"
$tag = "v1.1.7"
$base = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\media_kit_libs_android_video-$version\android\build\$tag"
New-Item -ItemType Directory -Force -Path $base | Out-Null

$proxy = $env:HTTPS_PROXY
$proxyArgs = @{}
if ($proxy) { $proxyArgs['Proxy'] = $proxy }

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
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 600 @proxyArgs
    } catch {
        Write-Host "retry without proxy: $_"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 600
    }
}

Write-Host "done -> $base"
