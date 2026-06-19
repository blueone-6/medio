param(
    [string]$Target = "apk",
    [string]$Version = ""
)

switch ($Target) {
    "apk"        { flutter build apk }
    "appbundle"  { flutter build appbundle }
    "windows"    { flutter build windows }
    "apk-rename" {
        $src = "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "ERROR: $src not found. Run 'build.ps1 apk' first." -ForegroundColor Red
            exit 1
        }
        if (-not $Version) {
            $Version = (Select-String -Path pubspec.yaml -Pattern "^version:\s*(\S+)").Matches.Groups[1].Value
            if ($Version -match "\+") { $Version = $Version.Split("+")[0] }
        }
        $distDir = "dist"
        if (-not (Test-Path -LiteralPath $distDir)) {
            New-Item -ItemType Directory -Path $distDir | Out-Null
        }
        $dest = Join-Path $distDir "medio-community-$Version-android.apk"
        Copy-Item -LiteralPath $src -Destination $dest -Force
        $sizeMB = [Math]::Round((Get-Item -LiteralPath $dest).Length / 1MB, 2)
        Write-Host "Copied -> $dest ($sizeMB MB)" -ForegroundColor Green
    }
    default      { Write-Host "Unknown target: $Target. Use apk, appbundle, windows, or apk-rename."; exit 1 }
}
