package com.example.media_client.tv_exo

import android.content.Context
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

@UnstableApi
class TvExoPlayerView(
    context: Context,
    private val bridge: TvExoPlayerBridge,
) : PlatformView {
    // PlayerView defaults to SurfaceView (required for HDR passthrough; not TextureView).
    private val playerView = PlayerView(context).apply {
        useController = false
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    init {
        bridge.attachPlayerView(playerView)
    }

    override fun getView(): PlayerView = playerView

    override fun dispose() {
        bridge.detachPlayerView(playerView)
    }
}

class TvExoPlayerViewFactory(
    private val bridge: TvExoPlayerBridge,
) : io.flutter.plugin.platform.PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return TvExoPlayerView(context, bridge)
    }
}
