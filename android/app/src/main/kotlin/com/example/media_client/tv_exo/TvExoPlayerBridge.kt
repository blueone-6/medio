package com.example.media_client.tv_exo

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.EventChannel

/**
 * Single ExoPlayer instance for Android TV playback (PlayerView / SurfaceView).
 *
 * Hybrid-composited into Flutter so HDR metadata can reach the display pipeline.
 */
@OptIn(UnstableApi::class)
class TvExoPlayerBridge(
    private val context: Context,
    private var activityProvider: () -> Activity?,
) {
    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var positionUpdatesActive = false
    /// Defer [playWhenReady] until [Player.STATE_READY] so resume seeks do not
    /// briefly decode from 0 before jumping to the bookmark.
    private var pendingAutoPlay = false
    private var hdrOutputActive = false

    private fun tvTrackSelectorParameters(hdrContent: Boolean): DefaultTrackSelector.Parameters {
        return trackSelector.buildUponParameters()
            .setMaxVideoSize(1920, 1080)
            // Tunneling can strip HDR metadata on some MTK SoCs — disable for HDR.
            .setTunnelingEnabled(!hdrContent)
            .setIgnoredTextSelectionFlags(
                C.SELECTION_FLAG_DEFAULT or
                    C.SELECTION_FLAG_FORCED or
                    C.SELECTION_FLAG_AUTOSELECT,
            )
            .build()
    }

    private val trackSelector = DefaultTrackSelector(context)

    private val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            15_000,
            45_000,
            1_500,
            2_500,
        )
        .build()

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            when (state) {
                Player.STATE_READY -> {
                    val p = player
                    if (p != null && pendingAutoPlay) {
                        pendingAutoPlay = false
                        p.playWhenReady = true
                    }
                    emit(
                        mapOf(
                            "event" to "ready",
                            "positionMs" to (p?.currentPosition?.coerceAtLeast(0) ?: 0L),
                        ),
                    )
                }
                Player.STATE_ENDED -> emit(mapOf("event" to "completed"))
            }
            emitPosition()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emitPosition()
        }

        override fun onPlayerError(error: PlaybackException) {
            emit(
                mapOf(
                    "event" to "error",
                    "message" to (error.message ?: error.errorCodeName),
                    "code" to error.errorCode,
                ),
            )
        }
    }

    private val positionRunnable = object : Runnable {
        override fun run() {
            emitPosition()
            if (positionUpdatesActive) {
                mainHandler.postDelayed(this, 1000)
            }
        }
    }

    fun setActivityProvider(provider: () -> Activity?) {
        activityProvider = provider
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun attachPlayerView(view: PlayerView) {
        playerView = view
        player?.let { view.player = it }
    }

    fun detachPlayerView(view: PlayerView) {
        if (playerView === view) {
            view.player = null
            playerView = null
        }
    }

    private fun buildPlayer(httpFactory: DefaultHttpDataSource.Factory): ExoPlayer {
        val mediaSourceFactory = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(httpFactory)
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
            .also { exo ->
                exo.addListener(playerListener)
                exo.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
                playerView?.player = exo
            }
    }

    private fun applyHdrOutput(isHdrContent: Boolean, videoRange: String?): TvHdrDisplay.SetHdrResult? {
        val activity = activityProvider() ?: return null
        val result = TvHdrDisplay.setHdrOutputEnabled(activity, isHdrContent)
        hdrOutputActive = result.applied
        val logMap = TvHdrDisplay.toLogMap(result, isHdrContent, videoRange)
        Log.i(TAG, "hdr_output $logMap")
        emit(mapOf("event" to "hdr_output" ) + logMap)
        return result
    }

    private fun restoreHdrOutput() {
        if (!hdrOutputActive) return
        val activity = activityProvider() ?: return
        TvHdrDisplay.setHdrOutputEnabled(activity, false)
        hdrOutputActive = false
        Log.i(TAG, "hdr_output restored colorMode=default")
    }

    fun setSource(
        url: String,
        headers: Map<String, String>?,
        startPositionMs: Long,
        subtitleUrl: String?,
        subtitleMime: String?,
        isHdrContent: Boolean,
        videoRange: String?,
    ) {
        stopPositionUpdates()
        restoreHdrOutput()
        playerView?.player = null
        player?.removeListener(playerListener)
        player?.release()
        player = null

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
        if (!headers.isNullOrEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        trackSelector.parameters = tvTrackSelectorParameters(isHdrContent)
        applyHdrOutput(isHdrContent, videoRange)

        val p = buildPlayer(httpFactory)
        player = p

        val builder = MediaItem.Builder().setUri(Uri.parse(url))
        if (!subtitleUrl.isNullOrBlank()) {
            val mime = subtitleMime?.takeIf { it.isNotBlank() } ?: "application/x-subrip"
            val sub = MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUrl))
                .setMimeType(mime)
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()
            builder.setSubtitleConfigurations(listOf(sub))
        }

        val startMs = startPositionMs.coerceAtLeast(0)
        val mediaItem = builder.build()
        if (startMs > 0) {
            pendingAutoPlay = true
            p.playWhenReady = false
            p.setMediaItem(mediaItem, startMs)
        } else {
            pendingAutoPlay = false
            p.setMediaItem(mediaItem)
            p.playWhenReady = true
        }
        p.prepare()
        startPositionUpdates()
    }

    fun play() {
        player?.play() ?: return
    }

    fun pause() {
        player?.pause()
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs.coerceAtLeast(0))
    }

    fun setPlaybackSpeed(speed: Double) {
        player?.setPlaybackSpeed(speed.toFloat().coerceIn(0.25f, 2.0f))
    }

    fun stop() {
        stopPositionUpdates()
        player?.stop()
        player?.clearMediaItems()
        restoreHdrOutput()
    }

    fun dispose() {
        stopPositionUpdates()
        restoreHdrOutput()
        playerView?.player = null
        player?.removeListener(playerListener)
        player?.release()
        player = null
        playerView = null
    }

    fun getState(): Map<String, Any?> {
        val p = player ?: return mapOf(
            "positionMs" to 0,
            "durationMs" to 0,
            "isPlaying" to false,
            "isBuffering" to false,
        )
        return mapOf(
            "positionMs" to p.currentPosition.coerceAtLeast(0),
            "durationMs" to if (p.duration > 0) p.duration else 0,
            "isPlaying" to p.isPlaying,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
        )
    }

    private fun startPositionUpdates() {
        if (positionUpdatesActive) return
        positionUpdatesActive = true
        mainHandler.post(positionRunnable)
    }

    private fun stopPositionUpdates() {
        positionUpdatesActive = false
        mainHandler.removeCallbacks(positionRunnable)
    }

    private fun emitPosition() {
        val p = player ?: return
        emit(
            mapOf(
                "event" to "position",
                "positionMs" to p.currentPosition.coerceAtLeast(0),
                "durationMs" to if (p.duration > 0) p.duration else 0,
                "isPlaying" to p.isPlaying,
                "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            ),
        )
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: IllegalStateException) {
                // Channel closed.
            }
        }
    }

    companion object {
        private const val TAG = "TvExoPlayer"
    }
}
