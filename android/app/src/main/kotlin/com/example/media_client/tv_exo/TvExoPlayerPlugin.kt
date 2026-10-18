package com.example.media_client.tv_exo

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TvExoPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var bridge: TvExoPlayerBridge? = null
    private var activity: Activity? = null

    /** Session id of the screen that owns the current event sink. */
    private var activeSinkSessionId: Int? = null

    private fun sessionIdOf(arguments: Any?): Int =
        ((arguments as? Map<*, *>)?.get("sessionId") as? Number)?.toInt() ?: 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        activeSinkSessionId = sessionIdOf(arguments)
                        bridge?.setEventSink(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        // An episode switch subscribes the *new* screen before
                        // the previous one cancels; clearing the sink blindly
                        // here used to silence "ready"/position events for the
                        // new episode (overlay stuck on 正在准备播放, subtitles
                        // frozen). Only the current owner may clear it.
                        if (activeSinkSessionId == sessionIdOf(arguments)) {
                            activeSinkSessionId = null
                            bridge?.setEventSink(null)
                        }
                    }
                },
            )
        }
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            TvExoPlayerViewFactory(ensureBridge(binding.applicationContext)),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        bridge?.dispose()
        bridge = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val b = bridge
        if (b == null) {
            result.error("no_bridge", "TvExoPlayerBridge not ready", null)
            return
        }
        when (call.method) {
            "setSource" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("bad_args", "url required", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val headers = call.argument<Map<String, String>>("headers")
                val startMs = call.argument<Number>("startPositionMs")?.toLong() ?: 0L
                val subtitleUrl = call.argument<String>("subtitleUrl")
                val subtitleMime = call.argument<String>("subtitleMime")
                val isHdrContent = call.argument<Boolean>("isHdrContent") == true
                val videoRange = call.argument<String>("videoRange")
                val positionEventIntervalMs =
                    call.argument<Number>("positionEventIntervalMs")?.toLong() ?: 1000L
                val handleAudioFocus = call.argument<Boolean>("handleAudioFocus") == true
                val customSubtitleRendering =
                    call.argument<Boolean>("customSubtitleRendering") == true
                val sessionId = call.argument<Number>("sessionId")?.toInt() ?: 0
                b.setSource(
                    url,
                    headers,
                    startMs,
                    subtitleUrl,
                    subtitleMime,
                    isHdrContent,
                    videoRange,
                    positionEventIntervalMs,
                    handleAudioFocus,
                    customSubtitleRendering,
                    sessionId,
                )
                result.success(null)
            }
            "play" -> {
                b.play(call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "pause" -> {
                b.pause(call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "seekTo" -> {
                val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                b.seekTo(ms, call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "setPlaybackSpeed" -> {
                val speed = call.argument<Double>("speed") ?: 1.0
                b.setPlaybackSpeed(speed)
                result.success(null)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                b.setVolume(volume, call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "getVolume" -> result.success(b.getVolume())
            "setMuted" -> {
                val muted = call.argument<Boolean>("muted") == true
                b.setMuted(muted)
                result.success(null)
            }
            "isMuted" -> result.success(b.isMuted())
            "setSubtitleDelayMs" -> {
                val delayMs = call.argument<Number>("delayMs")?.toLong() ?: 0L
                b.setSubtitleDelayMs(
                    delayMs,
                    call.argument<Number>("sessionId")?.toInt() ?: 0,
                )
                result.success(null)
            }
            "setSubtitleFontScale" -> {
                val scale = call.argument<Number>("scale")?.toFloat() ?: 1f
                b.setSubtitleFontScale(scale)
                result.success(null)
            }
            "setResizeMode" -> {
                val mode = call.argument<Number>("mode")?.toInt() ?: 0
                b.setResizeMode(mode)
                result.success(null)
            }
            "getResizeMode" -> result.success(b.getResizeMode())
            "getTracks" -> result.success(b.getTracks())
            "selectAudioTrack" -> {
                b.selectAudioTrack(
                    call.argument<String>("id"),
                    call.argument<Number>("sessionId")?.toInt() ?: 0,
                )
                result.success(null)
            }
            "selectTextTrack" -> {
                b.selectTextTrack(
                    call.argument<String>("id"),
                    call.argument<Number>("sessionId")?.toInt() ?: 0,
                )
                result.success(null)
            }
            "stop" -> {
                b.stop(call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "dispose" -> {
                b.dispose(call.argument<Number>("sessionId")?.toInt() ?: 0)
                result.success(null)
            }
            "getState" -> result.success(b.getState())
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        bridge?.setActivityProvider { activity }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        bridge?.setActivityProvider { null }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        bridge?.setActivityProvider { activity }
    }

    override fun onDetachedFromActivity() {
        activity = null
        bridge?.setActivityProvider { null }
    }

    private fun ensureBridge(context: android.content.Context): TvExoPlayerBridge {
        val existing = bridge
        if (existing != null) return existing
        return TvExoPlayerBridge(context) { activity }.also { bridge = it }
    }

    companion object {
        const val CHANNEL = "media_client/tv_exo_player"
        const val EVENT_CHANNEL = "media_client/tv_exo_player_events"
        const val VIEW_TYPE = "media_client/tv_exo_player_view"
    }
}
