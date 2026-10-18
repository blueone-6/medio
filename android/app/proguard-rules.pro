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

# R8 keep rules for plugins whose Java/Kotlin bridge is resolved over JNI.
#
# shared_preferences_android 2.5.x and path_provider_android 2.3.x generate
# their platform bridge with jnigen (pigeon -> `*.g.jni.dart` -> package:jni)
# instead of a MethodChannel, so the Dart side resolves the Kotlin methods at
# runtime with GetMethodID, by *name and JVM descriptor*.
#
# Two independent things go wrong under R8, both seen on a real device as a
# permanent white screen in release builds (the exception lands in the startup
# zone before runApp(); debug builds never run R8 and are unaffected):
#
# 1. Descriptors are rewritten. `@Keep` on the generated API keeps the method
#    names but not the classes named in their descriptors. Every `suspend`
#    bridge method takes a kotlin.coroutines.Continuation, R8 renames that
#    class, and the descriptor changes from
#    `(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;`
#    to one ending in the obfuscated `LX1/d;`:
#      NoSuchMethodError: no non-static method
#      "...SharedPreferencesApiRegistrar;.getAll(String, List, Continuation)Object"
#    -> includedescriptorclasses below keeps those descriptor types.
#
# 2. By-name lookups are pruned. package:jni's kotlin.dart loads a handful of
#    Kotlin runtime classes with JClass.forName()/staticMethodId() and nothing
#    references them statically, so R8 deletes them:
#      ClassNotFoundException: kotlin/coroutines/intrinsics/CoroutineSingletons
#    -> the explicit keeps below (the list mirrors jni-1.1.0/lib/src/kotlin.dart
#    plus the upstream rule in its android/consumer-rules.pro, which Flutter
#    does not apply because plugin modules are Gradle subprojects, not AARs).
-keep, includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }
-keep, includedescriptorclasses class io.flutter.plugins.pathprovider.** { *; }

-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
