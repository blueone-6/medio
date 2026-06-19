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

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        bridge?.setEventSink(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        bridge?.setEventSink(null)
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
                b.setSource(
                    url,
                    headers,
                    startMs,
                    subtitleUrl,
                    subtitleMime,
                    isHdrContent,
                    videoRange,
                )
                result.success(null)
            }
            "play" -> {
                b.play()
                result.success(null)
            }
            "pause" -> {
                b.pause()
                result.success(null)
            }
            "seekTo" -> {
                val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                b.seekTo(ms)
                result.success(null)
            }
            "setPlaybackSpeed" -> {
                val speed = call.argument<Double>("speed") ?: 1.0
                b.setPlaybackSpeed(speed)
                result.success(null)
            }
            "stop" -> {
                b.stop()
                result.success(null)
            }
            "dispose" -> {
                b.dispose()
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
