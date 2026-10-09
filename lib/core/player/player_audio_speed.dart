import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// Native mpv backend only; not part of the public media_kit API.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

/// Pitch-corrected audio across every offered playback rate (absorbed from
/// Kazumi's `af=scaletempo2=max-speed=8`).
///
/// mpv's auto-inserted scaletempo tops out at 2.0x — the exact ceiling of
/// medio's rate menu, where the correction boundary sits. An explicit
/// `scaletempo2` filter with a raised max-speed keeps 0.5–2.0 pitch-correct
/// and future-proofs higher rates. Setting `af` explicitly also disables the
/// auto-insert, which this replaces.
const String pitchCorrectedAudioFilter = 'scaletempo2=max-speed=8';

extension PlayerAudioSpeed on Player {
  Future<void> applyPitchCorrectedAudioFilter() async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    await platform.setProperty('af', pitchCorrectedAudioFilter);
  }
}
