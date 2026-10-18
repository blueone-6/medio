# R8 keep rules for the bundled FFmpeg audio decoder.
#
# `libffmpegJNI.so` (android/app/src/main/jniLibs/arm64-v8a) is media3's FFmpeg
# decoder extension; its Java side is vendored under
# android/app/src/main/media3ffmpeg/. The native side resolves
# `FfmpegAudioDecoder.growOutputBuffer` by name in `JNI_OnLoad` via
# `GetMethodID`, and that member has no Java-side caller, so R8 cannot see the
# reference and strips it — observed as `ffmpeg_jni: JNI_OnLoad: GetMethodID
# failed`, after which every AC3/EAC3 track is reported unsupported and playback
# is silent, even though the renderer itself loaded fine.
#
# This mirrors the rule upstream ships with the extension
# (`libraries/decoder_ffmpeg/proguard-rules.txt`). Only this member is needed:
# media3's own consumer rules already keep the reflectively-instantiated
# `FfmpegAudioRenderer` constructor. `includedescriptorclasses` is deliberately
# kept — the `GetMethodID` signature string names
# `androidx/media3/decoder/SimpleDecoderOutputBuffer`, so that class must not be
# renamed either.
-keep, includedescriptorclasses class androidx.media3.decoder.ffmpeg.FfmpegAudioDecoder {
    private java.nio.ByteBuffer growOutputBuffer(androidx.media3.decoder.SimpleDecoderOutputBuffer, int);
}
