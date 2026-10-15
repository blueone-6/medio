# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-15

### Added

- Unified netdisk (Quark) and strm playback behind a resilient transport layer,
  with bounded-range proxying for direct netdisk streaming.
- Silent CDN stall recovery: the player now detects stalled streams and
  re-opens the source instead of misreading the stall as a pause.
- Persistent stall detector that survives progress reports.

### Fixed

- Reject transient EOF positions after seeks and hide them from the controls.
- Supersede stale seek verification on keyboard and gesture seeks; stop
  re-opening after every successful slider seek and recover rejected seeks at
  the target position.
- Space out CDN recovery re-opens while keeping the resume point when the
  reported position collapses.
- Fully turn off text subtitles.
- Moved the episode selector to the left of the portrait control bar to avoid
  crowding the fast-forward key.

[1.1.0]: https://github.com/blueone-6/medio/releases/tag/v1.1.0

## [1.0.0] - 2026-06-19

### Added

- Initial community release.
- Cross-platform Emby/Jellyfin media library browsing: Windows Desktop, Android Phone, and Android TV.
- Immersive playback engine split: `media_kit` (libmpv) on Windows Desktop & Android Phone; ExoPlayer (Media3) on Android TV.
- Android TV deep adaptation: D-Pad navigation, Leanback-style UI, full remote control support.
- Cinema-grade visual experience: dark theme with amber accent, Be Vietnam Pro + Noto Sans SC typography, refined motion.
- Server connection management with multi-server support.
- Movie, TV, and collection browsing with metadata and backdrop imagery.

[1.0.0]: https://github.com/blueone-6/medio/releases/tag/v1.0.0
