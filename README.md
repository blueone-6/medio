# Medio Community

[![CI](https://github.com/blueone-6/medio/actions/workflows/ci.yml/badge.svg)](https://github.com/blueone-6/medio/actions/workflows/ci.yml)
[![Release](https://github.com/blueone-6/medio/actions/workflows/release.yml/badge.svg)](https://github.com/blueone-6/medio/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/blueone-6/medio)](LICENSE)
[![Release](https://img.shields.io/github/v/release/blueone-6/medio)](https://github.com/blueone-6/medio/releases)

> 跨平台 Emby 媒体浏览客户端 —— Windows Desktop / Android Phone / Android TV 三端通用

## 功能亮点

- **Emby / Jellyfin 媒体库浏览** — 电影、剧集、综艺节目一触即达
- **沉浸式播放** — Desktop & Phone 使用 media_kit (libmpv)，Android TV 使用 ExoPlayer
- **Android TV 深度适配** — D-Pad 导航、Leanback 界面、遥控器全键位支持
- **影院级视觉体验** — 暗色主题、Amber 强调色、精致排版与流畅动效

## 平台支持

| 平台 | 播放引擎 | 状态 |
|------|----------|------|
| Windows Desktop | media_kit (libmpv) | ✅ |
| Android Phone | media_kit (libmpv) | ✅ |
| Android TV | ExoPlayer (Media3) | ✅ |

## 安装

前往 [Releases](../../releases) 下载最新版本：

- **Windows**: `medio-community-*-windows-x64.zip`（免安装，解压即用）
- **Android Phone**: `medio-community-*.apk`
- **Android TV**: `medio-community-*.apk`（安装后在 Leanback 主屏显示）

## 编译

```bash
flutter pub get

# Windows
flutter run -d windows

# Android Phone
flutter run -d android

# Android TV Emulator
flutter emulators --launch <tv_avd_name>
flutter run -d emulator-5554
```

### media_kit 原生库预下载（可选）

正常网络环境下 Flutter 构建会自动拉取 media_kit (libmpv) 原生库，无需手动干预。
仅在以下情况手动预下载：

- **Android**：Gradle 从 GitHub 拉取 libmpv JAR 超时 / 失败
- **Windows**：CMake 4.x (VS 2026+) 无法解压 `.7z` 格式

```bash
# 可选代理：若网络受限，设置 HTTPS_PROXY 环境变量后再运行
.\tool\download_media_kit_android_libs.ps1
.\tool\download_media_kit_windows_libs.ps1
```

## 技术栈

Flutter · Riverpod · go_router · media_kit · ExoPlayer (Media3) · Material 3

## Disclaimer

Medio Community is an independently developed client. It does not provide media content, servers, accounts, or third-party services. See [DISCLAIMER.md](DISCLAIMER.md).

## Third-Party Notices

Bundled third-party software and licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[GPL-3.0-or-later](LICENSE)

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
