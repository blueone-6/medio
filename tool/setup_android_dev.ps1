# 配置 Android / Flutter 官方源与本机 Gradle 代理（可重复执行）
# 用法：在项目根目录执行  .\tool\setup_android_dev.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
# 直接写 HKCU 环境注册表，避免 Environment.SetEnvironmentVariable 的窗口广播被挂起。
function Set-UserEnvironmentVariable([string]$Name, [string]$Value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if ($null -eq $key) { throw "Cannot open HKCU\Environment" }
    try { $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}

function Remove-UserEnvironmentVariable([string]$Name) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if ($null -eq $key) { throw "Cannot open HKCU\Environment" }
    try { if ($null -ne $key.GetValue($Name)) { $key.DeleteValue($Name) } }
    finally { $key.Dispose() }
}

# ---------- Flutter 官方源（当前 PowerShell 会话）----------
$env:PUB_HOSTED_URL = "https://pub.dev"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.googleapis.com"
Write-Host "[flutter] PUB_HOSTED_URL=$env:PUB_HOSTED_URL"
Write-Host "[flutter] FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"

# 持久化到用户环境变量；保持显式官方源，避免残留国内镜像配置
Set-UserEnvironmentVariable "PUB_HOSTED_URL" $env:PUB_HOSTED_URL
Set-UserEnvironmentVariable "FLUTTER_STORAGE_BASE_URL" $env:FLUTTER_STORAGE_BASE_URL
Write-Host "[flutter] 已写入用户环境变量（需重新打开终端后全局生效）"

# ---------- Gradle / Flutter / Git 可选代理（共用 gradle-proxy.properties）----------
$example = Join-Path $Root "android\gradle-proxy.properties.example"
$proxyFile = Join-Path $Root "android\gradle-proxy.properties"
if (-not (Test-Path $proxyFile)) {
    Copy-Item $example $proxyFile
    Write-Host "[gradle] 已创建 android\gradle-proxy.properties（默认 127.0.0.1:7890）"
} else {
    Write-Host "[gradle] 已存在 android\gradle-proxy.properties，未覆盖"
}

function Read-GradleProxySettings {
    param([string]$Path)
    $enabled = $true
    $proxyHost = "127.0.0.1"
    $proxyPort = "7890"
    if (-not (Test-Path $Path)) { return @{ Enabled = $false } }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*enabled\s*=\s*false') { $enabled = $false }
        if ($line -match 'systemProp\.https\.proxyHost=(.+)') { $proxyHost = $Matches[1].Trim() }
        if ($line -match 'systemProp\.https\.proxyPort=(.+)') { $proxyPort = $Matches[1].Trim() }
    }
    return @{ Enabled = $enabled; Host = $proxyHost; Port = $proxyPort }
}

$proxy = Read-GradleProxySettings $proxyFile
if ($proxy.Enabled) {
    $proxyUrl = "http://$($proxy.Host):$($proxy.Port)"
    $noProxy = "localhost,127.0.0.1,::1"
    foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy")) {
        Set-Item -Path "Env:$name" -Value $proxyUrl
        Set-UserEnvironmentVariable $name $proxyUrl
    }
    foreach ($name in @("NO_PROXY", "no_proxy")) {
        Set-Item -Path "Env:$name" -Value $noProxy
        Set-UserEnvironmentVariable $name $noProxy
    }
    git config --global http.proxy $proxyUrl 2>$null
    git config --global https.proxy $proxyUrl 2>$null
    Write-Host "[flutter/git] HTTP_PROXY/HTTPS_PROXY=$proxyUrl（已写入用户环境变量）"
    Write-Host "[flutter/git] NO_PROXY=$noProxy"
    Write-Host "[flutter/git] git config --global http(s).proxy=$proxyUrl"
} else {
    foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy")) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        Remove-UserEnvironmentVariable $name
    }
    git config --global --unset http.proxy 2>$null
    git config --global --unset https.proxy 2>$null
    Write-Host "[flutter/git] gradle-proxy 已 disabled，已清除 HTTP(S)_PROXY 与 git 全局代理"
}

Write-Host ""
Write-Host "下一步："
Write-Host "  1. 确认本机代理已监听（默认 7890；端口见 gradle-proxy.properties）"
Write-Host "  2. 重新打开终端后执行: flutter doctor"
Write-Host "  3. 不需要代理：删除 android\gradle-proxy.properties，或设 enabled=false 后重跑本脚本"
Write-Host "  4. flutter pub get && flutter run -d android"
