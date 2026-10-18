# Android 软解音频音画不同步 — 调研与修复记录

> 状态：**已修复（2026-10-19）**。
>
> **重要更正**：实测（2026-10-19 现场播放 Dolby Vision/TrueHD remux）确认，用户看到的
> 主症状**与网络卡顿无关**：只要音轨走 FFmpeg 软解，声音就**一直**比画面快
> **约 300–500 ms**（恒定）。本文的 A/B 两类嫌疑只解释「卡顿后**额外**漂移」，不是这个
> 恒定偏移的成因。恒定偏移已由**手动「音画同步」补偿**解决（见文末「恒定偏移」一节）。

## 现象

Android 客户端（手机 ExoPlayer 路径）播放 Dolby/DTS remux 时，音频与视频存在肉眼可感
的**恒定偏移**，直到下次 seek/flush 才可能重新对齐（用户现场反馈「一直在，不是卡顿
才有」）。

- **偏移方向：声音比画面快**（视频落后 / 音频领先），量级约 **300–500 ms**。
- **只在软解音轨（AC3/EAC3/DTS/TrueHD）片源上出现**；普通 AAC 等硬件解码音轨正常。
- 现场日志确认这是 FFmpeg 软解路径：`DefaultRenderersFactory: Loaded
  FfmpegAudioRenderer.`、`libffmpegJNI.so` 加载成功、`AudioTrack` 以 48 kHz
  立体声 PCM 16-bit 播放（`frame_count=24000` = 500 ms 缓冲）。

恒定偏移量级与 `DefaultAudioSink` 的 PCM 缓冲 / 音频输出延迟同量级，但方向与「音频
时钟少减了一个 latency」这类推断相反 —— 说明这是**视频管线（解码 → Surface → 显示）
比音频输出更慢**这类**设备+片源相关、播放器无法自动测量**的物理延迟，只能像
mpv `--audio-delay` / VLC 的「音轨同步」那样手动校准一次。

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

## 已实施修复（2026-10-19）

### 0. 恒定偏移：「音画同步」手动补偿（对症现场主症状）

现场实测（2026-10-19）：用户手动「声音延后 **1 s**」后对齐；且判断**只有个别片源**
偏移，正常片源不需要。因此该补偿做成 **仅当前这次播放**（不落盘、换片源自动归零），
避免把正常片源一起带偏。

- 纯逻辑：`lib/core/player/player_av_sync.dart`（`clampAudioDelayMs` /
  `formatAudioDelayMs` / `describeAudioDelay` / `mpvAudioDelaySeconds`，
  量程 ±2 s，步进 0.1 s；单测 `test/player_av_sync_test.dart`）。
- **ExoPlayer（手机 + TV 共用 bridge）**：`TvExoPlayerBridge` 用自定义
  `DefaultRenderersFactory` 包一层 `ForwardingAudioSink`，在
  `getCurrentPositionUs()` 上加 `audioDelayUs`。ExoPlayer 的视频渲染器对的就是这个
  音频时钟，因此正值 = 时钟前移 = 画面提前 = **声音延后**（mpv `--audio-delay` 语义）。
  立即生效、无需重建播放器。
- **作用域：按片源记忆**。值按 `itemId` 存在
  `StorageKeys.avDelayByItem`（JSON `{itemId: ms}`，最多 50 条，最近使用在后，超出丢
  最早的；0 表示不补偿并删除条目）。未记录过的片源一律 0，所以正常片源不会被带偏。
  手机端在 `ExoPlayerScreen.initState` 读该片源的值，`_openSource` 每次把它下发给
  native（bridge 字段跨 player 重建保留，不主动下发就会漏到下一片源）；换集走
  `context.replace`，是新屏，天然用各自的记录。
- **mpv（桌面）**：值直接写 mpv `audio-delay`（chrome 自动隐藏会重建 widget，Dart
  字段会丢），打开片源时应用该片源存的值；菜单/对话框里的调整同时写回存储。
- **UI**：手机「音轨」面板底部「音画同步 · 仅本次播放」（声音延后/提前 0.1 s、0.5 s、
  重置同步）；桌面「更多 → 音画同步」（0.1 s 微调 / 重置 / 精确滑杆）。
- **1 s 这个量级**更像是**片源自带的音频延迟**（坏 remux / 音轨本就被后置），而不是
  设备管线延迟。为此 `TvExoPlayerBridge` 的 `onAudioInputFormatChanged` 会打印
  `mime/rate/ch/encoderDelay/encoderPadding`：若 `encoderDelay` 接近 1 s，说明延迟来自
  容器声明，可以做成「按片源自动应用」，不必手动调。

### 1. media3 1.4.1 → 1.11.1（对症 A，卡顿后额外漂移）

- `android/app/build.gradle.kts`：`val media3 = "1.11.1"`。
- vendored FFmpeg 绑定
  （`android/app/src/main/media3ffmpeg/`）按同一 tag 重新同步（5 个文件；唯一
  偏离仍是去掉 `MonotonicNonNull` 注解），README 已更新。
- 拿到的官方修复：`AudioTrack#getUnderrunCount()` 欠载检测、音频 timestamp 漂移
  平滑、蓝牙恢复后 10 秒 A/V sync、动态调度（1.9.1）、100 ms 欠载防抖 grace +
  固定 500 ms PCM buffer（1.10/1.11）、`MediaCodecVideoRenderer` 对「预测将迟到」
  的解码输入直接丢弃（1.11）。
- 原生 `.so` 无需重建：1.4.1 与 1.11.1 的 `ffmpeg_jni.cc` JNI 方法名/签名一致
  （已核对 `JNI_OnLoad` 的 `RegisterNatives` 表）。
- 回归验证：`flutter build apk --release` 通过，R8 mapping 中
  `FfmpegAudioRenderer` 及其反射构造器、`FfmpegAudioDecoder.growOutputBuffer`
  仍然保留；`install -r` 覆盖安装后启动无异常。

### 2. 代理字节完整性（对症 B，独立可先行的两个缺口的收口）

- **短块校验**：206 响应以 **上游自己的 `Content-Range`** 为准校验
  （`parseContentRangeHeader`）：起始偏移不符（`RANGE MISMATCH`）或长度不足
  （`TRUNCATED`）都不再当整块使用，而是有限重试
  （`maxShortBlockRetries`），失败则让播放器侧自己重试；不会再被
  `data.length < chunkSize` 提前 break 掉整个 relay。
- **缓存短块**：从磁盘读出的块用 `expectedBlockLength` 校验，不符则删除并重新拉取
  （`NetdiskBlockCache.delete`），堵住「短块写进缓存后被永久复用」。
- **200 忽略 Range**：`_relayWholeFile` 现在按客户端请求的 `start` 切片：已知实体
  长度时回 **206 + Content-Range** 并自行 skip，open-ended 请求不再从字节 0 整文件
  转发、seek 不再变成「从头下载」；只有 chunked（无长度）才退化为 200。

### 3. 卡顿结束后的一次重同步（兜底，防止仍出现固定偏移）

`TvExoPlayerBridge` 现在跟踪 READY→BUFFERING→READY 的**真卡顿**（排除 seek 引发的
buffering、初始 prepare 与切轨）：

- 卡顿期间收到 `AnalyticsListener.onAudioUnderrun`，或卡顿时长 ≥
  `RESYNC_MIN_STALL_MS`（1.5 s），且当前选中音轨属于 FFmpeg 软解集合
  （AC3/EAC3/DTS/DTS-HD/TrueHD…），READY 后 `RESYNC_SETTLE_MS`（0.5 s）执行一次
  位置保持的 flush —— 即用户手动 seek 的那一步。
- 因为 `ExoPlayerImplInternal` 会把「seek 到当前位置」当作 no-op，这里 seek 到
  `currentPosition + 1 ms` 以强制触发 renderer flush。
- 日志：`av_resync scheduled ...` / `av_resync seek pos=...`，logcat tag
  `TvExoPlayer`。

### 测试与验证

- 新增/更新单测：`test/player_av_sync_test.dart`（补偿值 clamp/格式化）、
  `test/netdisk_range_plan_test.dart`（`expectedBlockLength`、
  `parseContentRangeHeader`）、`test/netdisk_transport_test.dart`（截断块重试、
  磁盘短块丢弃、200 忽略 Range 的固定/开放式切片）。`flutter analyze`、完整
  `flutter test` 通过（`player_subtitle_activation_order_test.dart` 的 2 例因本机缺少
  `build/libmpv/libmpv-2.dll` 失败，与本次改动无关）。
- 真机：`flutter build apk --release` 通过；`adb install -r` 覆盖安装后启动无异常。

### 仍需人工确认的场景

1. **恒定偏移校准**：播放那个偏移的片源 → 播放器菜单「音轨」→ 底部「音画同步 ·
   按片源记忆」，点「声音延后 0.5s」（或 0.1s 微调）到口型对齐。**只记在这个片源
   上**，其它片源一律不受影响；下次播放同一片源自动生效。
2. **卡顿后额外漂移**：限速到码率以下的复现实验应确认恢复后不再有偏移；若日志出现
   `av_resync seek` 而画面仍偏，需要抓 `onAudioUnderrun` / 视频 PTS 进一步定位。
3. **实测数据（2026-10-19 01:10）**：该片源音轨是 `audio/eac3` 48 kHz 立体声、
   `encoderDelay=0`（容器没声明延迟），软解路径成立；也就是说这 ~1 s 不来自容器，
   而是 FFmpeg EAC3 解码/供数或 sink 起始锚点一侧，暂未继续深挖。

## 后续可选项

- 已实现「音画同步」补偿：ExoPlayer 走音频时钟前移，mpv 走 `audio-delay`。
- 若希望完全不依赖卡顿兜底 seek：可把 `RESYNC_MIN_STALL_MS` 调高或加设置开关。
- 想彻底自动对齐，需要在设备上量测「视频呈现时刻 vs 音频输出时刻」（如录制/光电
  对拍）；media3 没有公开的 A/V offset API，无法仅凭时钟自估。

## 原始修复方向（保留，供追溯）

1. **升级 media3 1.4.1 → 1.11.x**：对症 A —— 已做（1.11.1）。
2. **代理补短块校验 + 200-忽略-Range 时按客户端 Range 切片**：堵住 B —— 已做。
3. **手动「音频延迟」补偿** —— 已做（本文「恒定偏移」一节），也确认它是现场主症状
   的正解。

## 关键文件索引

| 文件 | 关注点 |
|------|--------|
| `android/app/src/main/kotlin/.../tv_exo/TvExoPlayerBridge.kt` | renderersFactory、LoadControl、音画同步补偿 sink、卡顿兜底重同步 |
| `android/app/src/main/media3ffmpeg/androidx/media3/decoder/ffmpeg/` | vendored FFmpeg 音频解码 |
| `android/app/build.gradle.kts` | media3 版本锁定处（现 1.11.1） |
| `lib/core/player/player_av_sync.dart` | 音画同步取值范围/格式化（纯函数） |
| `lib/core/player/netdisk_transport.dart` | loopback 代理、4 MB 块、重试、短块/200 切片 |
| `lib/core/player/netdisk_range_plan.dart` | `expectedBlockLength` / `parseContentRangeHeader`（纯函数） |
| `lib/core/player/netdisk_block_cache.dart` | 磁盘块缓存（`delete` 丢弃坏块） |
| `lib/screens/exo_player_screen.dart` | 手机侧重开/退避逻辑、音画同步应用 |
