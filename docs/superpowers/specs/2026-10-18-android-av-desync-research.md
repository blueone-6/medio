# Android 软解音频网络卡顿后音画不同步 — 调研记录

> 状态：**仅调研，未改代码**。修复方案待定（见文末「修复方向」），下次处理时从这里接续。

## 现象

Android 客户端（手机 ExoPlayer 路径）播放 Dolby/DTS remux 时，网络卡顿恢复后音频与
视频出现肉眼可感的**固定小偏移**（几十~几百 ms），直到下次 seek/flush 才重新对齐。
该偏移只在网络卡顿后出现，正常播放无偏移。

## 同步模型（现状梳理）

- **音频路径**：`FfmpegAudioRenderer`（vendored，media3 1.4.1 原样，
  `android/app/src/main/media3ffmpeg/`）→ `DefaultAudioSink` → `AudioTrack`。
  只接管 MediaCodec 不支持的 AC3/EAC3/DTS/MLP/TrueHD
  （`TvExoPlayerBridge.kt` `buildPlayer()`，`EXTENSION_RENDERER_MODE_ON`）。
- **同步模型**：ExoPlayer 是**音频主时钟** —— 视频渲染器
  （`MediaCodecVideoRenderer`）不断向音频渲染器的 `MediaClock` 对表，决定丢帧/持帧。
  音频时钟实现在 `DefaultAudioSink.getCurrentPositionUs()` →
  `AudioTrackPositionTracker`（基于 `AudioTrack.getTimestamp` /
  `getPlaybackHeadPosition` 外推）。
- **供数节奏**：手机 strm 走 `NetdiskTransport` loopback 代理（
  `lib/core/player/netdisk_transport.dart`），上游按 **4 MB 整块**拉取、
  **整块缓冲后才回吐**（`_collectBytes()`），上游无读超时。40 Mbps 片源下
  4 MB ≈ 0.8 秒画面 —— 供数天然呈「沉默→突发」锯齿。
- **卡顿表现**：媒体缓冲 30s/90s、rebuffer 后需攒 5s 缓冲才恢复播放
  （`TvExoPlayerBridge.kt` `buildLoadControl()`）。真卡顿时音频 sink 排空 →
  `AudioTrack` 欠载（underrun）→ 时钟进入「无数据外推」状态。

## 嫌疑排序（按可信度）

### A. media3 1.4.1 的音频时钟在 underrun 后会漂移（主嫌疑，官方已修）

1.4.1 的 `AudioTrackPositionTracker` 有两处弱点，都恰好在「网络卡顿 → 音频欠载 →
恢复」这个场景发作：

- underrun 靠**估算**检测（`mayHandleBuffer()` 里 `hasData` 布尔翻转）；
- 无 timestamp 模式时位置用**系统时钟 + 滑动平均偏移**外推（10 个样本平滑，
  最多 ~300 ms 滞后），欠载瞬间外推会**跑在真实声音前面**。

视频渲染器对表对的是这个偏快的时钟 → 恢复供数后真实音频落在画面后面，形成固定
偏移，直到下次 seek/flush 才重新对齐。

官方修复（可对照 media3 release notes）：

- **1.8.0**：改用 `AudioTrack#getUnderrunCount()` 检测欠载（取代 best-effort 估算）
  + "Improve audio timestamp smoothing for unexpected position drift from the audio
  output device" + 修「蓝牙设备恢复暂停后前 10 秒 A/V sync broken」。
- **1.9.1**：「Allow dynamic scheduling to slow doSomeWork interval only after audio
  starts to support smoother A/V sync at beginning of playback」。
- **1.10/1.11**：音频渲染器加 **100 ms 欠载防抖 grace period**（#3210，避免卡顿
  期反复触发 buffering）+ PCM buffer 固定 500 ms 减少设备差异。

项目锁死在 **1.4.1**（`android/app/build.gradle.kts` `val media3 = "1.4.1"`），
这些修复一个都没拿到。这也解释了「只有软解音频 + 网络卡顿才复现」：走 FFmpeg 的
恰是大码率 Dolby/DTS remux，而它们也恰是最容易卡的片源。

### B. 代理在卡顿边界可能回吐错位字节（会放大 A，可独立成灾）

`NetdiskTransport` 两个数据完整性缺口：

- 上游 206 返回**短块**时不校验长度（`_collectBytes()` 全收全出），响应头却按
  完整区间声明（`_writeResponseHeaders()`）→ 播放器读到的字节流缺段，且短块会
  **写进磁盘缓存被复用**（`NetdiskBlockCache.read()` 也不校验长度）。
- 上游忽略 Range 返回 200 时**整文件转发、从字节 0 开始**（`_relayWholeFile()`，
  `_stream()` 中 200 分支），不按客户端请求的 start 切片。logcat 特征：
  `MEDIO-TRANSPORT block #N WHOLE-FILE 200 (range ignored)`。

错位/缺段的 AC3 数据进 FFmpeg 解码器产出 invalid
（`FfmpegAudioDecoder.decode()` 标记 `shouldBeSkipped`），而 sink 收到 skip 后会
**重置位置基准**（`DefaultAudioSink.handleBuffer()` 的 `startMediaTimeUsNeedsSync`
路径，`onPositionDiscontinuity` 可观测）—— 音频时钟跳一下、视频不动，正好是
「卡顿后音画错开一点」。

### C. rebuffer 期间音视频排空时间差（背景因素）

卡顿进入 BUFFERING 时 AudioTrack 继续把 sink 内缓冲（约百 ms 级）播完才静音，
视频帧也在继续释放；正常情况恢复后由音频时钟重新对齐，但叠加 A 的估计误差时这个
差值就固化成偏移。LoadControl 的 rebuffer 门槛（恢复需 5s 缓冲）拉长了欠载窗口，
使 A 更容易发作。

### 已排除

- `bogus_position_guard` / stall detector 的纠正性 seek **只在桌面 mpv 路径**
  （`player_screen.dart`），Android（`ExoPlayerScreen` / `TvPlayerScreen`）不接入。
- Dart 侧重开（`_handleRecoverableNetworkError`）用 250 ms 陈旧位置重开，只造成
  整体位置跳变，不造成音画互差。

## 验证路径（下次处理时可先做）

1. **复现实验**：同一片源分别在「本地 NAS/无损网络」和「限速到码率以下」播放同一
   段落，确认偏移只在卡顿后出现且为固定小偏移。
2. **埋点对照**：临时挂 `EventLogger`/`AnalyticsListener` 抓
   `onAudioUnderrun`、`onPositionDiscontinuity`（sink 的
   `UnexpectedDiscontinuityException`）、`onAudioPositionAdvancing`，与视频
   `onDroppedFrames` 对照时间线 —— 能直接区分成因 A（欠载后时钟漂移）和 B
   （字节错位触发位置重置）。
3. **日志排查**：logcat 搜 `WHOLE-FILE 200 (range ignored)` 与
   `MEDIO-TRANSPORT` 吞吐告警，确认卡顿时是否伴随 B 类事件。

## 修复方向（按性价比，待拍板）

1. **升级 media3 1.4.1 → 1.11.x**：直接拿到官方 underrun 检测与时钟平滑修复，
   是对症 A 的根治。工作量集中在 vendored FFmpeg 绑定按新 tag 重新同步
   （见 `android/app/src/main/media3ffmpeg/README.md` 的上游对齐说明；
   `DefaultAudioSink.Builder.setAudioProcessors` 已废弃需换
   `setAudioProcessorChain`；回归验证 R8 keep 规则
   `android/app/proguard-rules.pro`）。
2. **代理补短块校验 + 200-忽略-Range 时按客户端 Range 切片**：堵住 B，与 1 独立、
   可先行。
3. **调参缓解**（非根治）：缩短 `bufferForPlaybackAfterRebufferMs` 减少欠载时长；
   或加「音频延迟」手动补偿设置（目前无该旋钮）。

## 关键文件索引

| 文件 | 关注点 |
|------|--------|
| `android/app/src/main/kotlin/.../tv_exo/TvExoPlayerBridge.kt` | renderersFactory、LoadControl |
| `android/app/src/main/media3ffmpeg/androidx/media3/decoder/ffmpeg/` | vendored FFmpeg 音频解码 |
| `android/app/build.gradle.kts` | media3 版本锁定处 |
| `lib/core/player/netdisk_transport.dart` | loopback 代理、4 MB 块、重试 |
| `lib/core/player/netdisk_block_cache.dart` | 磁盘块缓存（无长度校验） |
| `lib/screens/exo_player_screen.dart` | 手机侧重开/退避逻辑 |
