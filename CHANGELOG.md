# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phone double-tap zones and a paused gesture cheat-sheet.** The phone screen
  is split into thirds: double-tapping the left third rewinds 10 s, the middle
  third toggles play/pause (with a play/pause ripple), and the right third
  forwards 10 s. While playback is paused, a translucent full-screen sheet is
  split into the same three zones (two dashed dividers) and shows each gesture
  inside the zone it belongs to, so the copy never spells out
  left/middle/right; it ignores pointers, so controls and gestures keep working
  beneath it.
- **Long-press fast-forward on Android TV and phone.** On TV, holding the
  D-pad left/right ramps the seek step (10 s, then accelerated with hold time,
  with a 20 s safety cutoff) and shows an on-screen target preview, committing
  on release instead of issuing one seek per key repeat. On the phone, holding
  the right half of the screen now plays at 2x until release — the user's chosen
  speed is restored afterwards, and a paused video resumes only for the hold;
  the left half keeps the accelerated rewind.

### Fixed

- 音轨 sheet lists **every** track the device cannot decode, and no longer hides
  them when another track is playable: a file carrying both AAC and EAC3 showed
  only the playable one, which left the silent track unexplained.
- Per-session native calls (`seekTo`, `play`/`pause`, `setVolume`,
  `selectAudioTrack`/`selectTextTrack`, `setSubtitleDelayMs`) now carry the
  screen's session id, so a call still in flight from a screen that is tearing
  down can no longer act on the episode that replaced it — a stale seek used to
  jump the new episode to the old position, and a stale subtitle pick re-targeted
  the new episode's tracks.
- 音轨 sheet highlights the player's auto-selected track. It only marked a manual
  pick, so the default track looked unselected (`isSelected` from the native
  catalog was parsed but unused); the sheet now also re-reads the catalog when it
  opens, because the cached one is captured early in preparation, before media3
  has marked anything selected (verified on device: amber check on the playing
  track, `MEDIO-TRACKS … selected=[a:1:0]`).

### Changed

- The muxed-cue delay ticker only runs while a subtitle delay is actually set.
  The phone always renders muxed cues itself, so the ticker posted itself every
  100 ms for the entire session even with no delay.

## [1.2.0] - 2026-10-18

### Added

- **Dolby/DTS audio now plays on Android instead of silently**: media3 ships no
  software audio decoders and this phone's codec list has AC3/EAC3 commented
  out, so an EAC3-only remux played with no sound (the app could only explain
  why). Android builds now bundle media3's FFmpeg decoder extension — FFmpeg 6.0
  built with only the decoders the platform lacks (`ac3`, `eac3`, `dca`, `mlp`,
  `truehd`), arm64-v8a, **LGPL** (no GPL component enabled; FFmpeg is linked
  into `libffmpegJNI.so`, a separately replaceable shared object, which is the
  LGPL-2.1 §6 mechanism for this combination).
  It is consulted only for formats MediaCodec cannot handle
  (`EXTENSION_RENDERER_MODE_ON`), so hardware decoding, CPU and battery use are
  unchanged for everything else; on ABIs without the library media3 falls back
  exactly as before. Nothing is re-encoded and nothing goes through the server:
  the audio is decoded on the device. Rebuild with
  `tool/build_ffmpeg_decoder.ps1`; licensing in `THIRD_PARTY_NOTICES.md`.
  Release builds run R8, which had stripped `FfmpegAudioDecoder.growOutputBuffer`
  — the one member the JNI resolves by name, invisible to R8 as a Java
  reference — so the decoder loaded yet silently reported every AC3/EAC3 track as
  unsupported (`ffmpeg_jni: JNI_OnLoad: GetMethodID failed`). Kept now via
  `android/app/proguard-rules.pro`.

### Changed

- **Android phone playback engine switched from `media_kit` (libmpv) to Media3 ExoPlayer**
  (`ExoPlayerScreen`, `lib/screens/exo_player_screen.dart`). Desktop keeps media_kit.
  - Native bridge extended additively (`tv_exo` channels): track listing + audio/text
    selection, volume/mute, subtitle delay, configurable position-event cadence, audio
    focus handling. TV behavior unchanged.
  - External Emby text subtitles are fetched + parsed in Dart
    (`lib/core/player/exo/subtitle_text_parse.dart`) and rendered as a Flutter overlay —
    full both-direction subtitle delay, letterbox-aware positioning, and mid-session
    switching without re-prepare.
  - Muxed text/PGS tracks render natively via media3 (PGS decode, SSA text), with
    positive-direction subtitle delay via a CueGroup history.
  - Preserved capabilities: resume, 10 s progress reporting, auto-next countdown,
    codec fallback, network reopen/re-bootstrap recovery, netdisk transport + disk
    cache, HDR passthrough, gestures (seek/volume/brightness), keyboard shortcuts,
    volume memory, playback speed with pitch correction (Sonic), episode panel,
    portrait/landscape toggle, per-item subtitle preference.
  - libmpv is no longer initialized on Android at startup (saves ~100 MB RAM),
    and `media_kit_libs_android_video` is dropped from the dependency graph
    entirely (APK shrinks accordingly); the vendored
    `third_party/media_kit_libs_android_video` override was removed with it.
  - Phone player gained a **画面** button (适应 / 裁剪铺满 / 拉伸填满),
    remembered per device. Only 拉伸 distorts; the other two keep the aspect
    ratio. 裁剪铺满 is `RESIZE_MODE_ZOOM` — mapping crop to `RESIZE_MODE_FILL`
    stretched the picture, which was a bug. media3's `FIXED_WIDTH`/`FIXED_HEIGHT`
    are deliberately not offered: on a fixed full-screen surface they collapse
    onto 裁剪铺满 / 适应 and looked broken, so only the three distinguishable
    behaviours are listed.
  - Buffering raised for both **TV and phone** (they play the same netdisk/strm
    4K remuxes): media3 caps the buffer by bytes first
    (`DEFAULT_VIDEO_BUFFER_SIZE` = 131 MB ≈ 25 s of a 40 Mbps remux), so the old
    15 s/45 s configuration never reached its own duration target — the byte cap
    bound it. Now 30–90 s with a 320 MB target and
    `prioritizeTimeOverSizeThresholds`; the pool only grows as the buffer fills,
    so memory is unaffected on sources that never reach it.
  - NetdiskTransport logs relay throughput (per 32 MB plus a summary on close)
    and warns on upstream blocks slower than 1.5 s, so "why does it buffer"
    is answerable from the app log / diagnostics screen.
  - Subtitle offset is now adjusted only from the 字幕偏移 menu (inline ± buttons
    removed from both the phone and desktop control bars), and the menu rows
    refresh in place after each tap — previously the sheet was built once, so a
    tap changed the offset with no visible feedback and looked broken. For
    bitmap/muxed tracks (which media3 can only *delay*, since only the active
    cues are exposed) the 提前 row now says so instead of silently clamping.
  - Leaving the phone player restores portrait explicitly (previously restoring
    "all orientations" left the app stuck in landscape with auto-rotate off).
  - **Episode switch race fixed ("audio plays, picture is black")**: on a switch
    Flutter attaches the new platform view *before* the previous screen's
    `dispose()` reaches native code, and that stale teardown used to null the new
    `playerView` and release the *new* player — leaving it with no output
    surface. Player screens now carry a session id (stale `stop`/`dispose` are
    ignored) and `dispose` no longer clears `playerView`, which the view clears
    itself via `detachPlayerView`.
  - **Event channel no longer dies on an episode switch** (which left the
    "正在准备播放" overlay up until its timeout and froze subtitles): cancelling
    an `EventChannel` subscription removes the channel's *shared* Dart message
    handler, and the plugin's `onCancel` cleared the sink the next screen had
    just installed. The Dart side now keeps one app-lifetime pump per player
    path, and the sink is session-correlated on the native side.
  - **Playback keeps the screen awake** (`keepScreenOn` while playing or
    buffering, cleared on pause/stop/dispose) — the phone used to dim and sleep
    mid-playback when the system screen timeout elapsed.
  - **Embedded subtitles are no longer fetched from Emby's subtitle API**: a
    stream with `IsExternal: false` (the common "默认 SUBRIP" track inside a
    remux) returns nothing from
    `/Videos/{id}/{source}/Subtitles/{index}/Stream.srt`, so the default
    subtitle rendered blank while an external SRT worked. Auto-selection now
    prefers an external file, then renders the default/forced embedded track
    natively from the container, and only falls back to the API for an embedded
    stream the container does not expose. The 字幕 sheet offers only fetchable
    streams under 外挂 (`externalSubtitleChoices`); embedded tracks stay under
    内嵌, so a tap can no longer land on a stream the API cannot serve.
  - **Native track picking never worked**: ids were built as `t2:0` while the
    native resolver split on `:` expecting `prefix:group:track`, so every
    内嵌/音轨 selection was a silent no-op (an embedded pick left no subtitle
    on screen). The id now carries the prefix as its own segment and the
    resolver also accepts the legacy form rather than failing quietly.
  - Language matching for embedded tracks normalises Emby's Matroska
    bibliographic codes against media3's (`chi` vs `zho`, `eng` vs `en`, …),
    which is why an embedded stream was not recognised as covered by 内嵌.
  - Native (muxed) subtitle text honours 字幕字号 and is sized/positioned from
    the displayed video frame (5.5 % of its height, just above its bottom
    edge) — media3's default fraction is relative to the whole full-height
    PlayerView, which on a portrait phone produced oversized subtitles pinned
    to the screen bottom instead of the video. The native view also no longer
    inherits the *system* caption style (white text on a black box on this
    device): it now uses the app's look — white text with a drop shadow and no
    background — matching the external-subtitle overlay. The letterbox bars are
    applied as *view padding*, which is what media3 lays cues out against: that
    keeps bitmap (PGS) cues — which carry the positions authored for the video
    frame — inside the video instead of at the bottom of the screen.
  - **Track selections are re-applied if the `ready` event is missed**: the
    shared event channel and a `ready` payload that carries no source id meant
    an early/stale event could consume the one-shot flag and leave the session
    with no subtitle (or audio) selection until a manual pick. The flag is now
    cleared only after the catalog was read and the selection applied, and the
    playback state stream drives the same path as a fallback.
  - **A failed external-subtitle fetch is retried once** instead of leaving the
    session without subtitles for good (the empty cue list also hid the
    overlay), and the result is logged with byte/cue counts.
  - **Unsupported audio is now explained instead of silently absent**: media3
    drops tracks the device cannot decode, so a remux whose only track is EAC3
    (no Dolby decoder in this phone's codec list) produced an empty 音轨 list and
    silent playback with no hint. The bridge reports those tracks
    (`unsupportedAudio`) and the sheet shows e.g.
    `EAC3 音轨 · 此设备无法解码 / 无声播放`.
  - **Seek stalls when the signed CDN URL expires**: the netdisk transport pins
    one pre-resolved 115 CDN URL per session, but those URLs expire within
    minutes (a URL that served bytes earlier returns 403 later) and the Emby
    server caches its own redirect for minutes — so `refresh()` could keep
    handing back the same dead URL, exhausting its retries and leaving the player
    to re-open the source. Measured on device: 20.4 s between `seekTo` and
    `onRenderedFirstFrame` for a forward jump, versus 1.3 s for the same kind of
    jump while the URL was still valid, while the CDN answers that jump in
    ~0.25 s. On an expiry status the transport now falls back to the Emby stream
    URL — which mints a fresh signed URL per request — and retries that block
    immediately, with a one-shot background re-pin of a direct CDN URL after.
  - NetdiskTransport block fetches and player buffering transitions are logged
    to logcat (`MEDIO-TRANSPORT …`, `TvExoPlayer: state=…`) so a slow seek can be
    attributed to the transport or to the player on a release install, where the
    app's own log file is not reachable.
  - **A stalled player now says so instead of freezing the frame**: buffering
    mid-playback used to be invisible — the picture simply stopped with no
    explanation, which reads as a hung app on a slow network. Both ExoPlayer
    screens (phone and TV) now show a pill over the frame once a wait passes
    700 ms — long enough that the routine sub-second rebuffer of a seek stays
    quiet — escalating after 8 s to `网络缓慢，正在缓冲…` with the buffered range
    (`已缓冲至 …`), which is what separates a slow network from a dead source.
    The bridge reports the buffered position for this, the video is never
    blacked out, and the escalation rule is a pure tested function
    (`lib/widgets/player/buffering_indicator.dart`).

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

## [1.0.0] - 2026-06-19

### Added

- Initial community release.
- Cross-platform Emby/Jellyfin media library browsing: Windows Desktop, Android Phone, and Android TV.
- Immersive playback engine split: `media_kit` (libmpv) on Windows Desktop & Android Phone; ExoPlayer (Media3) on Android TV.
- Android TV deep adaptation: D-Pad navigation, Leanback-style UI, full remote control support.
- Cinema-grade visual experience: dark theme with amber accent, Be Vietnam Pro + Noto Sans SC typography, refined motion.
- Server connection management with multi-server support.
- Movie, TV, and collection browsing with metadata and backdrop imagery.

[1.2.0]: https://github.com/blueone-6/medio/releases/tag/v1.2.0
[1.1.0]: https://github.com/blueone-6/medio/releases/tag/v1.1.0
[1.0.0]: https://github.com/blueone-6/medio/releases/tag/v1.0.0
