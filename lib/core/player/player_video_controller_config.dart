import 'package:media_kit_video/media_kit_video.dart';

import '../layout/platform_layout.dart';

/// [VideoController] options per platform (Android phone uses GPU texture path).
VideoControllerConfiguration videoControllerConfiguration({
  required bool hardwareDecoding,
  bool onEmulator = false,
}) {
  if (isAndroidMobileUi) {
    final useHw = hardwareDecoding && !onEmulator;
    // Emulator: mediacodec_embed — OMX/MediaCodec → Surface.
    // Phone: vo=gpu for Flutter texture compositing latency.
    final useMediacodecVo = onEmulator;
    final vo = useMediacodecVo ? 'mediacodec_embed' : 'gpu';
    final hwdec = !useHw
        ? 'no'
        : useMediacodecVo
            ? 'mediacodec'
            : 'auto-safe';
    return VideoControllerConfiguration(
      vo: vo,
      hwdec: hwdec,
      enableHardwareAcceleration: useHw,
      // Attach Surface when [Video] mounts so --wid is available before [Player.open].
      androidAttachSurfaceAfterVideoParameters: false,
    );
  }
  return VideoControllerConfiguration(
    hwdec: hardwareDecoding ? 'auto' : 'no',
    enableHardwareAcceleration: hardwareDecoding,
  );
}
