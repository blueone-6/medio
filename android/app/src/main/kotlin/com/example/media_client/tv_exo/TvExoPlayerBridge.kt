package com.example.media_client.tv_exo

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.EventChannel

/**
 * Single ExoPlayer instance (Media3 + SurfaceView), shared by TV and phone.
 *
 * Hybrid-composited into Flutter so HDR metadata can reach the display pipeline.
 *
 * Phone additions over the TV baseline (all gated behind [customSubtitleRendering]
 * / explicit methods so the TV path stays byte-identical):
 * - track listing + audio/text selection
 * - player volume / mute
 * - muxed-subtitle delay via a CueGroup history re-rendered into a custom
 *   [SubtitleView] (positive offsets only; external sidecar subs are rendered
 *   by the Flutter overlay which supports both directions)
 * - configurable position event interval + audio focus handling
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

    // ── Phone-extended state ──
    /** Position event cadence, ms. TV keeps 1000; phone uses 250. */
    private var positionEventIntervalMs = 1000L

    /** Phone path: text tracks render through [delaySubtitleView] with delay support. */
    private var customSubtitleRendering = false

    /** Audio focus (pause on call / headphone unplug). Off for TV (legacy behavior). */
    private var handleAudioFocus = false

    /** Last user-requested volume, 0..1. Re-applied after player rebuilds. */
    private var desiredVolume = 1.0

    private var muted = false

    /** Muxed subtitle delay, ms ≥ 0 (positive = subtitles appear later). */
    private var subtitleDelayMs = 0L

    /**
     * Video resize mode (`AspectRatioFrameLayout.RESIZE_MODE_*`).
     * Defaults to FIT so the TV path is unchanged; the phone sets CROP.
     * Stored on the bridge so it survives a PlayerView re-attach.
     */
    private var resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT

    /** Rolling (positionMs → active cues) history for delayed muxed rendering. */
    private val cueHistory = ArrayDeque<Pair<Long, List<Cue>>>()

    /** Custom subtitle surface for the delayed muxed path; PlayerView's own is hidden. */
    private var delaySubtitleView: SubtitleView? = null

    /** Native (muxed) subtitle scale: user 字幕字号 / 42. */
    private var subtitleFontScale = 1f

    private fun tvTrackSelectorParameters(
        hdrContent: Boolean,
        disableText: Boolean,
    ): DefaultTrackSelector.Parameters {
        return trackSelector.buildUponParameters()
            // No max-video-size cap: 4K direct play is the design intent
            // (hardware decode via ExoPlayer); a 1080p cap silently degraded
            // every 4K source on TV.
            // Tunneling can strip HDR metadata on some MTK SoCs — disable for HDR.
            .setTunnelingEnabled(!hdrContent)
            .setIgnoredTextSelectionFlags(
                C.SELECTION_FLAG_DEFAULT or
                    C.SELECTION_FLAG_FORCED or
                    C.SELECTION_FLAG_AUTOSELECT,
            )
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, disableText)
            .build()
    }

    private val trackSelector = DefaultTrackSelector(context)

    /**
     * Buffering for high-bitrate remuxes, shared by TV and phone.
     *
     * media3 caps the buffer by *bytes* before the time target
     * (`DEFAULT_VIDEO_BUFFER_SIZE` = 131 MB, prioritise-time-over-size off), so
     * the previous 15 s / 45 s configuration only ever held ~25 s of a 40 Mbps
     * 4K remux — well under its own 45 s target. Anything the link delivers
     * below the bitrate for a few seconds then drains the buffer and rebuffers:
     * both the phone and the TV play the same netdisk/strm 4K remuxes, so both
     * are exposed (the TV even has the netdisk block cache off by default).
     *
     * The pool is only grown as the buffer actually fills, so a device that
     * never reaches these numbers does not pay for them.
     */
    private fun buildLoadControl(): DefaultLoadControl =
        DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                30_000,
                90_000,
                2_500,
                5_000,
            )
            .setTargetBufferBytes(320 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            updateKeepScreenOn()
            // Visible in logcat (the Dart-side logs only reach the app log file):
            // BUFFERING→READY transitions are what "seek stalls" look like from
            // the player's side, and they delimit where the wait happens.
            Log.i(
                TAG,
                "state=$state pos=${player?.currentPosition ?: -1} " +
                    "buf=${player?.bufferedPosition ?: -1}",
            )
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
                            "videoWidth" to (p?.videoSize?.width ?: 0),
                            "videoHeight" to (p?.videoSize?.height ?: 0),
                        ),
                    )
                }
                Player.STATE_ENDED -> emit(mapOf("event" to "completed"))
            }
            emitPosition()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateKeepScreenOn()
            emitPosition()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            updateKeepScreenOn()
        }

        override fun onRenderedFirstFrame() {
            Log.i(TAG, "onRenderedFirstFrame")
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            applySubtitleLayout()
        }

        override fun onPlayerError(error: PlaybackException) {
            Log.w(TAG, "player error code=${error.errorCode} ${error.message}", error)
            emit(
                mapOf(
                    "event" to "error",
                    "message" to (error.message ?: error.errorCodeName),
                    "code" to error.errorCode,
                ),
            )
        }

        override fun onCues(cueGroup: CueGroup) {
            if (!customSubtitleRendering) return
            val p = player ?: return
            val posMs = cueGroup.presentationTimeUs / 1000
            val last = cueHistory.lastOrNull()
            if (last != null && last.first == posMs && last.second == cueGroup.cues) return
            // Keep the buffer position-ordered: a backward seek appends entries
            // older than existing ones — rebuild ordering by dropping stale future.
            while (cueHistory.isNotEmpty() && cueHistory.last().first > posMs) {
                cueHistory.removeLast()
            }
            if (cueHistory.isNotEmpty() && cueHistory.last().first == posMs) {
                cueHistory.removeLast()
            }
            cueHistory.addLast(posMs to cueGroup.cues.toList())
            trimCueHistory(p)
            renderDelayedCues(p)
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            if (!customSubtitleRendering) return
            val p = player ?: return
            // Seeks (and timeline refreshes) invalidate buffered future cues.
            while (cueHistory.isNotEmpty() && cueHistory.last().first > p.currentPosition) {
                cueHistory.removeLast()
            }
            renderDelayedCues(p)
        }
    }

    private val positionRunnable = object : Runnable {
        override fun run() {
            emitPosition()
            if (positionUpdatesActive) {
                mainHandler.postDelayed(this, positionEventIntervalMs)
            }
        }
    }

    /**
     * Re-renders delayed muxed cues while a delay is active.
     *
     * Only runs while [subtitleDelayMs] is non-zero ([syncDelayTicker]): the
     * phone always renders muxed cues itself, so an unconditional 100 ms tick
     * woke the CPU ~10×/s for the whole session even with no delay set.
     */
    private val delayTicker = object : Runnable {
        override fun run() {
            delayTickerScheduled = false
            val p = player
            if (p == null || !customSubtitleRendering || subtitleDelayMs == 0L) return
            renderDelayedCues(p)
            scheduleDelayTicker()
        }
    }

    private var delayTickerScheduled = false

    private fun scheduleDelayTicker() {
        if (delayTickerScheduled) return
        delayTickerScheduled = true
        mainHandler.postDelayed(delayTicker, DELAY_TICK_MS)
    }

    private fun stopDelayTicker() {
        delayTickerScheduled = false
        mainHandler.removeCallbacks(delayTicker)
    }

    /** Starts the cue re-render ticker only while a delay is actually set. */
    private fun syncDelayTicker() {
        if (customSubtitleRendering && subtitleDelayMs != 0L) {
            scheduleDelayTicker()
        } else {
            stopDelayTicker()
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
        view.resizeMode = resizeMode
        watchSurface(view)
        updateKeepScreenOn()
        Log.i(
            TAG,
            "view attached playerView=${view.hashCode()} player=${player?.hashCode()} " +
                "resizeMode=$resizeMode size=${view.width}x${view.height}",
        )
        // The platform view can attach before/after the player exists; make sure
        // the player ends up with a live surface either way.
        mainHandler.post { rebindSurface("attach") }
        if (customSubtitleRendering) {
            ensureDelaySubtitleView(view)
        }
    }

    /**
     * Re-asserts the player <-> view binding so PlayerView hands its
     * SurfaceHolder to the player again. media3 only pushes the surface when
     * `PlayerView.setPlayer` is called or the holder (re)appears, so anything
     * that recreates the surface (resize-mode change, platform-view re-attach
     * after an episode switch) could otherwise leave the player decoding video
     * with no output surface — i.e. "audio plays, picture is black".
     */
    private fun rebindSurface(reason: String) {
        val view = playerView ?: return
        val p = player ?: return
        try {
            view.player = null
            view.player = p
            val surfaceView = view.videoSurfaceView as? android.view.SurfaceView
            Log.i(
                TAG,
                "surface rebind ($reason) valid=${surfaceView?.holder?.surface?.isValid}",
            )
        } catch (e: Exception) {
            Log.w(TAG, "surface rebind failed: $e")
        }
    }

    /** Logs the SurfaceView lifecycle so a lost video surface is visible. */
    private fun watchSurface(view: PlayerView) {
        val surfaceView = view.videoSurfaceView as? android.view.SurfaceView ?: return
        val holder = surfaceView.holder ?: return
        holder.addCallback(object : android.view.SurfaceHolder.Callback {
            override fun surfaceCreated(h: android.view.SurfaceHolder) {
                Log.i(TAG, "surfaceCreated valid=${h.surface.isValid}")
            }

            override fun surfaceChanged(
                h: android.view.SurfaceHolder,
                format: Int,
                width: Int,
                height: Int,
            ) {
                Log.i(TAG, "surfaceChanged ${width}x$height")
            }

            override fun surfaceDestroyed(h: android.view.SurfaceHolder) {
                Log.i(TAG, "surfaceDestroyed")
            }
        })
    }

    fun detachPlayerView(view: PlayerView) {
        if (playerView === view) {
            delaySubtitleView?.let { custom ->
                view.removeView(custom)
            }
            delaySubtitleView = null
            view.keepScreenOn = false
            view.player = null
            playerView = null
            Log.i(TAG, "view detached playerView=${view.hashCode()}")
        }
    }

    private fun ensureDelaySubtitleView(view: PlayerView) {
        if (delaySubtitleView != null) {
            Log.i(
                TAG,
                "delaySubtitleView already attached parent=${delaySubtitleView?.parent?.hashCode()} " +
                    "view=${view.hashCode()}",
            )
            applySubtitleLayout()
            return
        }
        val custom = SubtitleView(view.context)
        // Match the Flutter overlay (white text + drop shadow, no background).
        // Left unset, media3 paints text cues with the *system* caption style,
        // which on this device is white-on-black — an unexpected black box.
        custom.setStyle(
            CaptionStyleCompat(
                android.graphics.Color.WHITE,
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW,
                android.graphics.Color.BLACK,
                null,
            ),
        )
        // The style above is authoritative; embedded ASS/SSA looks are not part
        // of the app's caption design and only widen the gap to the overlay.
        custom.setApplyEmbeddedStyles(false)
        // The user's 字幕字号 setting must win over a track's embedded sizes.
        custom.setApplyEmbeddedFontSizes(false)
        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        )
        view.addView(custom, lp)
        // PlayerView's own subtitle surface keeps rendering live cues — hide it
        // so the delayed layer is the single visible subtitle source.
        view.subtitleView?.visibility = android.view.View.GONE
        delaySubtitleView = custom
        Log.i(
            TAG,
            "delaySubtitleView added parent=${view.hashCode()} children=${view.childCount}",
        )
        applySubtitleLayout()
        player?.let { renderDelayedCues(it) }
    }

    /**
     * Sizes/positions the delayed cues like the Flutter overlay does.
     *
     * media3 lays cues out relative to the subtitle view minus its padding, so
     * the letterbox bars are applied as view padding. That keeps text cues at
     * the video's bottom edge and — more importantly — keeps PGS/bitmap cues
     * (which carry the positions authored for the video frame) inside the video
     * area instead of the bottom of the screen. The remaining height is then
     * the displayed video height, which is also what the text size fraction is
     * relative to (the same 5.5 % the Flutter overlay uses).
     */
    private fun applySubtitleLayout() {
        val view = playerView ?: return
        val sub = delaySubtitleView ?: return
        val viewH = view.height.toFloat()
        val viewW = view.width.toFloat()
        if (viewH <= 0f || viewW <= 0f) return
        val videoSize = player?.videoSize
        val aspect = if (videoSize != null && videoSize.width > 0 && videoSize.height > 0) {
            videoSize.width.toFloat() / videoSize.height.toFloat()
        } else {
            viewW / viewH
        }
        val displayedH = if (resizeMode == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
            minOf(viewH, viewW / aspect)
        } else {
            viewH
        }
        val bar = ((viewH - displayedH) / 2f).coerceAtLeast(0f).toInt()
        sub.setPadding(0, bar, 0, bar)
        sub.setFractionalTextSize(
            (SUBTITLE_HEIGHT_FRACTION * subtitleFontScale).coerceIn(0.008f, 0.12f),
        )
        val marginPx = SUBTITLE_BOTTOM_MARGIN_DP * view.resources.displayMetrics.density
        sub.setBottomPaddingFraction(
            (marginPx / displayedH.coerceAtLeast(1f)).coerceIn(0f, 0.2f),
        )
    }

    /** Scales native (muxed) subtitle text: the user's 字幕字号 / 42. */
    fun setSubtitleFontScale(scale: Float) {
        subtitleFontScale = scale.coerceIn(0.3f, 3f)
        applySubtitleLayout()
    }

    private fun trimCueHistory(p: Player) {
        val windowMs = CUE_HISTORY_WINDOW_MS
        val minPos = p.currentPosition - windowMs
        while (cueHistory.size > 1 && cueHistory.first().first < minPos) {
            cueHistory.removeFirst()
        }
        while (cueHistory.size > CUE_HISTORY_MAX_ENTRIES) {
            cueHistory.removeFirst()
        }
    }

    private fun renderDelayedCues(p: Player) {
        val target = p.currentPosition - subtitleDelayMs
        var active: List<Cue> = emptyList()
        for (entry in cueHistory) {
            if (entry.first <= target) {
                active = entry.second
            } else {
                break
            }
        }
        delaySubtitleView?.setCues(active)
    }

    /**
     * Keeps the display awake while the player is playing or buffering.
     *
     * ExoPlayer/PlayerView never manage this themselves: the phone dimmed and
     * slept mid-playback once the system screen timeout elapsed. Pausing clears
     * the flag, so a paused player no longer pins the screen on.
     */
    private fun updateKeepScreenOn() {
        val p = player
        val keep = p != null &&
            p.playbackState != Player.STATE_IDLE &&
            p.playbackState != Player.STATE_ENDED &&
            (p.playWhenReady || p.playbackState == Player.STATE_BUFFERING)
        playerView?.keepScreenOn = keep
    }

    private fun buildPlayer(httpFactory: DefaultHttpDataSource.Factory): ExoPlayer {
        val mediaSourceFactory = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(httpFactory)
        // media3 ships no software audio decoders, and this device's platform
        // codec list has AC3/EAC3 commented out, so Dolby remuxes would play
        // silently. `libffmpegJNI.so` (see THIRD_PARTY_NOTICES.md) supplies
        // AC3/EAC3/DTS/MLP/TrueHD. ON means "only where MediaCodec cannot", so
        // hardware decoding — and battery use — is untouched for everything
        // else; when the library is missing (other ABIs) media3 logs and falls
        // back exactly as before.
        val renderersFactory = DefaultRenderersFactory(context)
            .setExtensionRendererMode(
                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON,
            )
        val builder = ExoPlayer.Builder(context, renderersFactory)
            .setMediaSourceFactory(mediaSourceFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(buildLoadControl())
        if (handleAudioFocus) {
            builder.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                /* handleAudioFocus = */ true,
            )
        }
        return builder.build().also { exo ->
            exo.addListener(playerListener)
            exo.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
            exo.volume = if (muted) 0f else desiredVolume.toFloat()
            Log.i(
                TAG,
                "player built playerView=${playerView?.hashCode()} " +
                    "size=${playerView?.width}x${playerView?.height}",
            )
            playerView?.let { view ->
                view.player = exo
                if (customSubtitleRendering) ensureDelaySubtitleView(view)
            }
            updateKeepScreenOn()
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
        positionEventIntervalMs: Long = 1000L,
        handleAudioFocus: Boolean = false,
        customSubtitleRendering: Boolean = false,
        sessionId: Int = 0,
    ) {
        activeSessionId = sessionId
        stopPositionUpdates()
        restoreHdrOutput()
        detachPhoneExtras()
        playerView?.player = null
        player?.removeListener(playerListener)
        player?.release()
        player = null
        cueHistory.clear()
        delaySubtitleView?.setCues(emptyList())

        this.positionEventIntervalMs = positionEventIntervalMs.coerceIn(100L, 5000L)
        this.handleAudioFocus = handleAudioFocus
        this.customSubtitleRendering = customSubtitleRendering

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
        if (!headers.isNullOrEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        // Phone starts with text tracks off; Dart re-enables + overrides once
        // the preference (external overlay vs muxed track) is applied.
        trackSelector.parameters = tvTrackSelectorParameters(
            isHdrContent,
            disableText = customSubtitleRendering,
        )
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
        syncDelayTicker()
    }

    fun play(sessionId: Int = 0) {
        if (!ownsSession(sessionId)) return stale("play", sessionId)
        player?.play() ?: return
    }

    fun pause(sessionId: Int = 0) {
        if (!ownsSession(sessionId)) return stale("pause", sessionId)
        player?.pause()
    }

    fun seekTo(positionMs: Long, sessionId: Int = 0) {
        // A stale seek from a screen that is tearing down would otherwise jump
        // the *next* episode to the old position.
        if (!ownsSession(sessionId)) return stale("seekTo", sessionId)
        Log.i(TAG, "seekTo $positionMs (from ${player?.currentPosition ?: -1})")
        player?.seekTo(positionMs.coerceAtLeast(0))
    }

    fun setPlaybackSpeed(speed: Double) {
        player?.setPlaybackSpeed(speed.toFloat().coerceIn(0.25f, 2.0f))
    }

    /**
     * `AspectRatioFrameLayout.RESIZE_MODE_FIT` (0), `RESIZE_MODE_FILL` (3) or
     * `RESIZE_MODE_ZOOM` (4). FIT/ZOOM keep the aspect ratio; FILL stretches.
     */
    fun setResizeMode(mode: Int) {
        resizeMode = when (mode) {
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView?.resizeMode = resizeMode
        Log.i(TAG, "setResizeMode=$resizeMode")
        applySubtitleLayout()
        // A resize re-measures (and can recreate) the SurfaceView; re-assert the
        // binding on the next frame so the player keeps a video output surface.
        mainHandler.post { rebindSurface("resizeMode") }
    }

    fun getResizeMode(): Int = resizeMode

    fun setVolume(volume: Double, sessionId: Int = 0) {
        if (!ownsSession(sessionId)) return stale("setVolume", sessionId)
        desiredVolume = volume.coerceIn(0.0, 1.0)
        player?.volume = if (muted) 0f else desiredVolume.toFloat()
    }

    fun getVolume(): Double = desiredVolume

    fun setMuted(value: Boolean) {
        muted = value
        player?.volume = if (muted) 0f else desiredVolume.toFloat()
    }

    fun isMuted(): Boolean = muted

    /** Muxed subtitle delay, ms. Negative offsets are clamped to 0 (ExoPlayer
     * exposes only the currently-active cues, so future cues cannot be shown
     * early; external sidecar subs are delayed in both directions by the
     * Flutter overlay instead). */
    fun setSubtitleDelayMs(delayMs: Long, sessionId: Int = 0) {
        if (!ownsSession(sessionId)) return stale("setSubtitleDelayMs", sessionId)
        val clamped = delayMs.coerceIn(0L, 30_000L)
        if (clamped != subtitleDelayMs) {
            subtitleDelayMs = clamped
            player?.let { renderDelayedCues(it) }
        }
        syncDelayTicker()
    }

    /**
     * Parses a track id. Current format is `prefix:group:track`; the legacy
     * `t2:0` form (prefix glued to the group index) is still accepted so a
     * mismatched id can never silently turn a pick into a no-op again.
     */
    private fun findTrack(id: String?): Pair<Tracks.Group, Int>? {
        if (id == null) return null
        val parts = id.split(":")
        val groupPart: String
        val trackPart: String
        when (parts.size) {
            3 -> {
                groupPart = parts[1]
                trackPart = parts[2]
            }
            2 -> {
                groupPart = parts[0].drop(1)
                trackPart = parts[1]
            }
            else -> return null
        }
        val groupIndex = groupPart.toIntOrNull() ?: return null
        val trackIndex = trackPart.toIntOrNull() ?: return null
        val p = player ?: return null
        val groups = p.currentTracks.groups
        if (groupIndex < 0 || groupIndex >= groups.size) return null
        val group = groups[groupIndex]
        if (trackIndex < 0 || trackIndex >= group.length) return null
        return group to trackIndex
    }

    private fun trackEntry(
        prefix: String,
        groupIndex: Int,
        trackIndex: Int,
        group: Tracks.Group,
    ): Map<String, Any?> {
        val format = group.getTrackFormat(trackIndex)
        val label = when {
            !format.label.isNullOrBlank() -> format.label
            !format.language.isNullOrEmpty() -> format.language
            else -> "轨道 ${trackIndex + 1}"
        }
        return mapOf(
            // `prefix:group:track` — findTrack() splits on ':' and expects the
            // prefix to be its own segment ("t2:0" silently failed to resolve,
            // which made every native text/audio pick a no-op).
            "id" to "$prefix:$groupIndex:$trackIndex",
            "language" to format.language,
            "label" to label,
            "isSelected" to group.isTrackSelected(trackIndex),
        )
    }

    /** Human-readable codec name for a track the device cannot decode. */
    private fun audioCodecLabel(format: Format): String =
        format.label ?: when (format.sampleMimeType) {
            MimeTypes.AUDIO_AC3 -> "AC3"
            MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC -> "EAC3"
            MimeTypes.AUDIO_DTS -> "DTS"
            MimeTypes.AUDIO_DTS_HD -> "DTS-HD"
            MimeTypes.AUDIO_TRUEHD -> "TrueHD"
            else -> format.sampleMimeType?.substringAfter('/')?.uppercase() ?: "未知音轨"
        }

    fun getTracks(): Map<String, Any?> {
        val p = player
        if (p == null) {
            return mapOf("audio" to emptyList<Any>(), "text" to emptyList<Any>())
        }
        val audio = mutableListOf<Map<String, Any?>>()
        val text = mutableListOf<Map<String, Any?>>()
        val unsupportedAudio = mutableListOf<Map<String, Any?>>()
        p.currentTracks.groups.forEachIndexed { groupIndex, group ->
            val prefix = when (group.type) {
                C.TRACK_TYPE_AUDIO -> "a"
                C.TRACK_TYPE_TEXT -> "t"
                else -> return@forEachIndexed
            }
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) {
                    // Unsupported tracks are dropped from the catalog. Keep the
                    // unsupported *audio* ones so the app can say why there is no
                    // sound (e.g. an EAC3 track on a phone with no Dolby decoder)
                    // instead of showing an empty 音轨 list.
                    val format = group.getTrackFormat(trackIndex)
                    Log.w(
                        TAG,
                        "track unsupported type=${group.type} id=$prefix:$groupIndex:$trackIndex " +
                            "mime=${format.sampleMimeType} label=${format.label}",
                    )
                    if (group.type == C.TRACK_TYPE_AUDIO) {
                        unsupportedAudio.add(
                            mapOf(
                                "id" to "$prefix:$groupIndex:$trackIndex",
                                "language" to format.language,
                                "label" to audioCodecLabel(format),
                                "mime" to format.sampleMimeType,
                            ),
                        )
                    }
                    continue
                }
                val entry = trackEntry(prefix, groupIndex, trackIndex, group)
                if (group.type == C.TRACK_TYPE_AUDIO) audio.add(entry) else text.add(entry)
            }
        }
        Log.i(
            TAG,
            "getTracks audio=${audio.size} text=${text.size} " +
                "unsupportedAudio=${unsupportedAudio.size}",
        )
        return mapOf(
            "audio" to audio,
            "text" to text,
            "unsupportedAudio" to unsupportedAudio,
        )
    }

    fun selectAudioTrack(id: String?, sessionId: Int = 0) {
        if (!ownsSession(sessionId)) return stale("selectAudioTrack", sessionId)
        val p = player ?: return
        if (id == null) {
            trackSelector.parameters = trackSelector.buildUponParameters()
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .build()
            return
        }
        val found = findTrack(id) ?: return
        trackSelector.parameters = trackSelector.buildUponParameters()
            .setOverrideForType(TrackSelectionOverride(found.first.mediaTrackGroup, found.second))
            .build()
    }

    fun selectTextTrack(id: String?, sessionId: Int = 0) {
        // A stale pick from the previous episode must not re-target this one.
        if (!ownsSession(sessionId)) return stale("selectTextTrack", sessionId)
        val p = player ?: run {
            Log.i(TAG, "selectTextTrack($id) ignored: no player")
            return
        }
        if (id == null) {
            trackSelector.parameters = trackSelector.buildUponParameters()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            Log.i(TAG, "selectTextTrack -> off")
            return
        }
        val found = findTrack(id)
        if (found == null) {
            Log.w(TAG, "selectTextTrack id=$id not found in ${p.currentTracks.groups.size} groups")
            return
        }
        trackSelector.parameters = trackSelector.buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(TrackSelectionOverride(found.first.mediaTrackGroup, found.second))
            .build()
        Log.i(
            TAG,
            "selectTextTrack id=$id -> group=${found.second} " +
                "delayView=${delaySubtitleView != null} view=${playerView?.hashCode()}",
        )
    }

    /**
     * Session that currently owns this (single, shared) bridge.
     *
     * On an episode switch Flutter creates the new platform view *before* the
     * previous screen's `dispose()` reaches native code, so a stale `dispose()`
     * used to null the **new** playerView and release the **new** player —
     * leaving it without a video surface (audio only, black picture). Each
     * screen now sends its own session id and only the owner may stop/dispose.
     * Legacy callers (TV) send no id; 0 always owns the bridge.
     */
    private var activeSessionId = 0

    private fun ownsSession(sessionId: Int): Boolean =
        sessionId == 0 || activeSessionId == 0 || sessionId == activeSessionId

    /** Logs a call dropped because its screen no longer owns the bridge. */
    private fun stale(method: String, sessionId: Int) {
        Log.i(TAG, "ignoring stale $method (session=$sessionId active=$activeSessionId)")
    }

    fun stop(sessionId: Int = 0) {
        if (!ownsSession(sessionId)) {
            Log.i(TAG, "ignoring stale stop (session=$sessionId active=$activeSessionId)")
            return
        }
        stopPositionUpdates()
        player?.stop()
        player?.clearMediaItems()
        cueHistory.clear()
        delaySubtitleView?.setCues(emptyList())
        restoreHdrOutput()
        playerView?.keepScreenOn = false
    }

    fun dispose(sessionId: Int = 0) {
        if (!ownsSession(sessionId)) {
            Log.i(
                TAG,
                "ignoring stale dispose (session=$sessionId active=$activeSessionId) " +
                    "playerView=${playerView?.hashCode()}",
            )
            return
        }
        stopPositionUpdates()
        restoreHdrOutput()
        detachPhoneExtras()
        playerView?.keepScreenOn = false
        playerView?.player = null
        player?.removeListener(playerListener)
        player?.release()
        player = null
        // Deliberately keep `playerView`: on an episode switch the *new*
        // platform view is already attached by the time this stale teardown
        // lands, and its own session builds a fresh player right after. The
        // view clears the reference itself through detachPlayerView().
        activeSessionId = 0
        cueHistory.clear()
    }

    private fun detachPhoneExtras() {
        stopDelayTicker()
        val view = delaySubtitleView
        val parentView = playerView
        if (view != null && parentView != null) {
            parentView.removeView(view)
            parentView.subtitleView?.visibility = android.view.View.VISIBLE
        }
        delaySubtitleView = null
    }

    fun getState(): Map<String, Any?> {
        val p = player ?: return mapOf(
            "positionMs" to 0,
            "durationMs" to 0,
            "bufferedPositionMs" to 0,
            "isPlaying" to false,
            "isBuffering" to false,
            "videoWidth" to 0,
            "videoHeight" to 0,
            "speed" to 1.0,
        )
        return mapOf(
            "positionMs" to p.currentPosition.coerceAtLeast(0),
            "durationMs" to if (p.duration > 0) p.duration else 0,
            "bufferedPositionMs" to p.bufferedPosition.coerceAtLeast(0),
            "isPlaying" to p.isPlaying,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            "videoWidth" to p.videoSize.width,
            "videoHeight" to p.videoSize.height,
            "speed" to p.playbackParameters.speed.toDouble(),
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
                "bufferedPositionMs" to p.bufferedPosition.coerceAtLeast(0),
                "isPlaying" to p.isPlaying,
                "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
                "videoWidth" to p.videoSize.width,
                "videoHeight" to p.videoSize.height,
                "speed" to p.playbackParameters.speed.toDouble(),
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
        private const val DELAY_TICK_MS = 100L
        private const val CUE_HISTORY_WINDOW_MS = 180_000L
        private const val CUE_HISTORY_MAX_ENTRIES = 2048

        /** Subtitle line height as a fraction of the displayed video height. */
        private const val SUBTITLE_HEIGHT_FRACTION = 0.055f

        /** Gap between the video's bottom edge and the cues, in dp. */
        private const val SUBTITLE_BOTTOM_MARGIN_DP = 24f
    }
}
