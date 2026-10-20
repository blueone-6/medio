/// Windows 杜比（Dolby Vision / Atmos）播放策略的纯函数。
///
/// 放在 `core/player/` 而不是屏幕里，方便单测（见
/// `test/dolby_playback_test.dart`）。只负责“算出要设哪些 mpv 属性”，
/// 不碰 Player / UI。
library;

/// Windows 上启用音频直通时要设置的 mpv 属性。
///
/// * `ao=wasapi` + `audio-exclusive=yes`：绕过 Windows 音频引擎，独占设备。
/// * `audio-spdif`：TrueHD/EAC3/DTS 等压缩音频源码直通给 AVR/回音壁。
/// * `audio-channels=auto`：不强制声道数，避免把对象音频下混成 PCM。
///
/// 非 Windows 或未启用时返回空 Map（调用方按空集合跳过）。
Map<String, String> dolbyAudioPassthroughProperties({
  required bool windows,
  required bool enabled,
}) {
  if (!windows || !enabled) return const <String, String>{};
  // `ao` 放最后：先设直通/独占选项，再让 WASAPI 输出按这些选项初始化，
  // 避免先选驱动再改选项导致一次多余的 audio output reload。
  return const <String, String>{
    'audio-exclusive': 'yes',
    'audio-spdif': 'ac3,eac3,dts,dts-hd,truehd',
    'audio-channels': 'auto',
    'ao': 'wasapi',
  };
}

/// FFmpeg `libplacebo` 滤镜图：应用 DV RPU，并把 HDR/P5 转成 BT.709 SDR。
///
/// 这是当前 media_kit Windows（legacy gpu 纹理路径）上修复 P5 的关键：
/// 先由 libplacebo 处理 IPTPQc2/RPU 并 tone-map，mpv 只负责显示 SDR 帧。
const String dolbyVisionLibplaceboGraph =
    'libplacebo=apply_dolbyvision=1:format=yuv420p:colorspace=bt709:'
    'color_primaries=bt709:color_trc=bt709:range=tv:tonemapping=bt.2446a';

/// Windows 上 Dolby Vision 的视频滤镜值。
///
/// * [useLibplacebo] = true：走 FFmpeg `libplacebo`，能处理 P5 的 IPTPQc2/RPU，
///   并直接 tone-map 到 BT.709；4K 下比旧路径多一次 GPU/CPU 往返。
/// * false：只剥离 DV 元数据（`format:dolbyvision=no`），P8/P7 可正常走
///   HDR10 基础层，但 **P5 仍会偏色**，仅作为 libplacebo 不可用时的退路。
///
/// 非 Windows 或非 DV 返回 null。
String? dolbyVisionVideoFilter({
  required bool windows,
  required bool isDolbyVision,
  required bool useLibplacebo,
}) {
  if (!windows || !isDolbyVision) return null;
  if (!useLibplacebo) return 'format:dolbyvision=no';
  // 用 mpv 的固定长度转义（%n%...）包住滤镜图，避免 `:` / `"` 被
  // vf 列表解析器误拆。图是纯 ASCII，长度可直接用 Dart length。
  return 'lavfi=graph=%${dolbyVisionLibplaceboGraph.length}%'
      '$dolbyVisionLibplaceboGraph';
}
