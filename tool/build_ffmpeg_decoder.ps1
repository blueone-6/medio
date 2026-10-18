# Rebuilds the Android FFmpeg audio decoder that Medio bundles.
#
# Why this exists
# ---------------
# media3 ships no software audio decoders and the phone's platform codec list
# has AC3/EAC3 commented out, so Dolby/DTS remuxes play silently. Media3's
# official FFmpeg decoder extension supplies those decoders, but it is not
# published to Google Maven — it has to be built from FFmpeg sources with the
# NDK. The result is committed as
#   android/app/src/main/jniLibs/arm64-v8a/libffmpegJNI.so      (native side)
# and its Java bindings are vendored (Apache-2.0, one compile-time annotation
# dropped) under
#   android/app/src/main/media3ffmpeg/androidx/media3/decoder/ffmpeg/
# so a normal `flutter build apk` needs none of this. Re-run this script only
# when changing the decoder set or the FFmpeg version. See
# THIRD_PARTY_NOTICES.md §7 for the license situation (FFmpeg is LGPL here).
#
# Requirements: WSL2 with an Ubuntu distro (the build is a Linux-hosted NDK
# build; the script installs make/cmake/unzip via `sudo -n apt-get` and
# downloads the NDK and FFmpeg). The media3 JNI sources it compiles are vendored
# in tool/media3_ffmpeg/, so the build is pinned and needs no GitHub access.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tool\build_ffmpeg_decoder.ps1

param(
    [string]$Distro   = "Ubuntu-22.04",
    [string]$NdkTag   = "r26b",
    [string]$FfmpegTag = "6.0",
    [string[]]$Decoders = @("ac3", "eac3", "dca", "mlp", "truehd")
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$repoWsl  = "/mnt/" + $repoRoot.Substring(0, 1).ToLower() + $repoRoot.Substring(2).Replace('\', '/')
$decoderFlags = ($Decoders | ForEach-Object { " --enable-decoder=$_" }) -join ""
$ffmpegSha256 = "57be87c22d9b49c112b6d24bc67d42508660e6b718b3db89c44e47e289137082"

$bash = @"
set -euo pipefail
HOME_DIR="`$HOME"
WORK="`$HOME_DIR/medio-ffmpeg"
NDK_DIR="`$HOME_DIR/android-ndk-$NdkTag"
TOOLCHAIN_COMMON="toolchains/llvm/prebuilt/linux-x86_64/bin"
API=21
ABI=arm64-v8a
MODULE="`$WORK/module/src/main/jni"
DEST="$repoWsl/android/app/src/main/jniLibs/`$ABI"
JNI_SRC="$repoWsl/tool/media3_ffmpeg"

echo '=== 0/5 toolchain ==='
# unzip is needed for the NDK archive independently of make/cmake.
if ! command -v make >/dev/null || ! command -v cmake >/dev/null || ! command -v unzip >/dev/null; then
  echo 'installing make/cmake/unzip via sudo -n apt-get (needs passwordless sudo)'
  sudo -n apt-get update -qq
  sudo -n apt-get install -y -qq make cmake unzip
fi

echo '=== 1/5 NDK ==='
if [ ! -d "`$NDK_DIR" ]; then
  cd "`$HOME_DIR"
  curl -fL --retry 3 -o "android-ndk-$NdkTag-linux.zip" \
    "https://dl.google.com/android/repository/android-ndk-$NdkTag-linux.zip"
  unzip -q "android-ndk-$NdkTag-linux.zip"
  rm -f "android-ndk-$NdkTag-linux.zip"
fi
TOOLCHAIN="`$NDK_DIR/`$TOOLCHAIN_COMMON"

echo '=== 2/5 sources ==='
mkdir -p "`$MODULE"
cd "`$WORK"
if [ ! -f "ffmpeg-$FfmpegTag.tar.xz" ]; then
  curl -fL --retry 3 -o "ffmpeg-$FfmpegTag.tar.xz" \
    "https://ffmpeg.org/releases/ffmpeg-$FfmpegTag.tar.xz"
fi
echo "$ffmpegSha256  ffmpeg-$FfmpegTag.tar.xz" | sha256sum -c -
if [ ! -d "ffmpeg-$FfmpegTag" ]; then
  tar xf "ffmpeg-$FfmpegTag.tar.xz"
fi
# JNI sources are vendored in this repo (see tool/media3_ffmpeg/README.md) so
# the build is pinned and offline-capable.
cp -f "`$JNI_SRC/CMakeLists.txt" "`$JNI_SRC/ffmpeg_jni.cc" "`$MODULE/"
rm -rf "`$MODULE/ffmpeg"
cp -r "ffmpeg-$FfmpegTag" "`$MODULE/ffmpeg"

echo '=== 3/5 configure (audio decoders only, no GPL components) ==='
cd "`$MODULE/ffmpeg"
./configure \
  --prefix="`$MODULE/ffmpeg/prefix" \
  --libdir=android-libs/`$ABI \
  --arch=aarch64 --cpu=armv8-a --target-os=android \
  --enable-static --disable-shared --disable-doc --disable-programs \
  --disable-everything --disable-avdevice --disable-avformat --disable-swscale \
  --disable-postproc --disable-avfilter --disable-symver --enable-swresample \
  --extra-ldexeflags=-pie --disable-v4l2-m2m --disable-vulkan \
  --cross-prefix="`$TOOLCHAIN/aarch64-linux-android`$API-" \
  --nm="`$TOOLCHAIN/llvm-nm" --ar="`$TOOLCHAIN/llvm-ar" \
  --ranlib="`$TOOLCHAIN/llvm-ranlib" --strip="`$TOOLCHAIN/llvm-strip" \
  $decoderFlags

echo '=== 4/5 build ==='
make -j"`$(nproc)"
make install-libs

echo '=== 5/5 libffmpegJNI.so ==='
cd "`$MODULE"
cmake -S . -B "build/`$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="`$NDK_DIR/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=`$ABI -DANDROID_PLATFORM=android-`$API -DCMAKE_BUILD_TYPE=Release
cmake --build "build/`$ABI" -j"`$(nproc)"
mkdir -p "`$DEST"
cp -f "build/`$ABI/libffmpegJNI.so" "`$DEST/"
"`$TOOLCHAIN/llvm-strip" --strip-unneeded "`$DEST/libffmpegJNI.so"
echo "--- installed ---"
"`$TOOLCHAIN/llvm-nm" -D --defined-only "`$DEST/libffmpegJNI.so" | grep -c Java_ || true
ls -la "`$DEST/libffmpegJNI.so"
"@

$scriptPath = Join-Path $env:TEMP "medio_build_ffmpeg_decoder.sh"
# Write without a BOM and with LF line endings so bash can run it directly.
$text = $bash -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($scriptPath, $text, (New-Object System.Text.UTF8Encoding($false)))

$wslPath = "/mnt/c/" + $scriptPath.Substring(0, 1).ToLower() + $scriptPath.Substring(2).Replace('\', '/')
Write-Host "Building FFmpeg decoders ($($Decoders -join ', ')) for Android arm64-v8a via WSL ($Distro)..."
wsl -d $Distro -- bash $wslPath
if ($LASTEXITCODE -ne 0) { throw "FFmpeg decoder build failed (exit $LASTEXITCODE)" }
Write-Host "Done. Check in android/app/src/main/jniLibs/arm64-v8a/libffmpegJNI.so"
