# Vendored: AndroidX Media3 FFmpeg decoder bindings

These four files (`FfmpegAudioDecoder`, `FfmpegAudioRenderer`,
`FfmpegDecoderException`, `FfmpegLibrary`) plus `package-info.java` are taken
**verbatim from AndroidX Media3 tag `1.11.1`** (Apache License 2.0, © The Android
Open Source Project):

<https://github.com/androidx/media/tree/1.11.1/libraries/decoder_ffmpeg/src/main/java/androidx/media3/decoder/ffmpeg>

They are vendored rather than depended upon because media3 does not publish the
FFmpeg extension to Google Maven — it must be built from source — and this
directory is registered as an extra Java source directory in
`android/app/build.gradle.kts`.

**Keep this in step with the media3 version.** The JNI method names and
signatures in `tool/build_ffmpeg_decoder.ps1`'s sources
(`ffmpeg_jni.cc`) are unchanged since 1.4.1, so the existing
`libffmpegJNI.so` still registers against these bindings — but media3's
`DecoderAudioRenderer`/`AudioSink` APIs it compiles against do change between
releases, and a mismatch fails at build time rather than at runtime.

**Deviations from upstream**

- `FfmpegLibrary.java` drops `org.checkerframework.checker.nullness.qual.MonotonicNonNull`
  (the import and one field annotation). It is a compile-time-only nullness
  annotation from a dependency media3 declares as `compileOnly`; dropping it
  avoids adding a dependency to this project. No behaviour change.
- `ExperimentalFfmpegVideoRenderer.java` is deliberately **not** vendored: it is
  a video renderer, and this build enables audio decoders only. Media3's
  `DefaultRenderersFactory` tolerates its absence (it catches
  `ClassNotFoundException` for that class).

**Two things to know before touching this**

1. The package name is `androidx.media3.decoder.ffmpeg`, so adding a real
   `androidx.media3:media3-decoder-ffmpeg` dependency later would produce
   duplicate classes. If media3 ever publishes that artifact, delete this
   directory and depend on it instead.
2. The native side (`android/app/src/main/jniLibs/arm64-v8a/libffmpegJNI.so`)
   resolves `FfmpegAudioDecoder.growOutputBuffer` by name from `JNI_OnLoad`, and
   `DefaultRenderersFactory` instantiates `FfmpegAudioRenderer` reflectively.
   R8 sees neither reference, so keep rules are required —
   `android/app/proguard-rules.pro`. Losing them (or minification) makes audio
   decoding fail silently rather than crash.

Rebuild the native library with `tool/build_ffmpeg_decoder.ps1`; licensing is
documented in `THIRD_PARTY_NOTICES.md` §7.
