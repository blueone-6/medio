# Vendored: media3 1.4.1 decoder_ffmpeg JNI sources

`CMakeLists.txt` and `ffmpeg_jni.cc` are taken verbatim from AndroidX Media3 tag
`1.4.1` (Apache License 2.0, © The Android Open Source Project):

<https://github.com/androidx/media/tree/1.4.1/libraries/decoder_ffmpeg/src/main/jni>

`tool/build_ffmpeg_decoder.ps1` compiles them against the FFmpeg 6.0 static
libraries to produce `libffmpegJNI.so`. They are vendored so that rebuilding the
binary is offline-capable and pinned to exact bytes rather than fetching
whatever `raw.githubusercontent.com` serves for a ref that may later move.

The Java side of the same module lives in
`android/app/src/main/media3ffmpeg/`; see its README for the R8 keep rules that
this native code depends on.
