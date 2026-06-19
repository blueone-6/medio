package com.example.media_client.tv_exo

import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.util.Log
import android.view.Display

/**
 * Queries display HDR capabilities and toggles Activity window color mode for
 * HDR10 passthrough (projector / HDMI handles tone mapping).
 */
object TvHdrDisplay {
    private const val TAG = "TvHdrDisplay"

    data class Capabilities(
        val displayHdr10: Boolean,
        val supportedHdrTypeNames: List<String>,
        val maxLuminance: Float,
    )

    data class SetHdrResult(
        val requested: Boolean,
        val applied: Boolean,
        val colorMode: String,
        val capabilities: Capabilities,
        val reason: String? = null,
    )

    fun queryCapabilities(activity: Activity): Capabilities {
        val display = activity.window?.decorView?.display
            ?: activity.windowManager.defaultDisplay
        val caps = display.hdrCapabilities
        val types = caps?.supportedHdrTypes?.map { hdrTypeName(it) } ?: emptyList()
        val hdr10 = supportsHdr10(caps)
        return Capabilities(
            displayHdr10 = hdr10,
            supportedHdrTypeNames = types,
            maxLuminance = caps?.desiredMaxLuminance ?: 0f,
        )
    }

    fun supportsHdr10(caps: Display.HdrCapabilities?): Boolean {
        if (caps == null) return false
        return caps.supportedHdrTypes.any {
            it == Display.HdrCapabilities.HDR_TYPE_HDR10 ||
                it == Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS
        }
    }

    fun setHdrOutputEnabled(activity: Activity, enabled: Boolean): SetHdrResult {
        val caps = queryCapabilities(activity)
        if (!enabled) {
            activity.window.colorMode = ActivityInfo.COLOR_MODE_DEFAULT
            return SetHdrResult(
                requested = false,
                applied = true,
                colorMode = "default",
                capabilities = caps,
            )
        }
        if (!caps.displayHdr10) {
            Log.w(
                TAG,
                "HDR content but display reports no HDR10 support types=${caps.supportedHdrTypeNames}",
            )
            activity.window.colorMode = ActivityInfo.COLOR_MODE_DEFAULT
            return SetHdrResult(
                requested = true,
                applied = false,
                colorMode = "default",
                capabilities = caps,
                reason = "display_no_hdr10",
            )
        }
        activity.window.colorMode = ActivityInfo.COLOR_MODE_HDR
        val applied = activity.window.colorMode == ActivityInfo.COLOR_MODE_HDR
        if (!applied) {
            Log.w(TAG, "COLOR_MODE_HDR not applied windowMode=${activity.window.colorMode}")
        } else {
            Log.i(
                TAG,
                "HDR output enabled types=${caps.supportedHdrTypeNames} " +
                    "maxLum=${caps.maxLuminance}",
            )
        }
        return SetHdrResult(
            requested = true,
            applied = applied,
            colorMode = if (applied) "hdr" else "default",
            capabilities = caps,
            reason = if (applied) null else "color_mode_not_applied",
        )
    }

    fun toLogMap(result: SetHdrResult, isHdrContent: Boolean, videoRange: String?): Map<String, Any?> {
        return mapOf(
            "isHdrContent" to isHdrContent,
            "videoRange" to videoRange,
            "displayHdr10" to result.capabilities.displayHdr10,
            "hdrTypes" to result.capabilities.supportedHdrTypeNames,
            "maxLuminance" to result.capabilities.maxLuminance,
            "hdrRequested" to result.requested,
            "hdrApplied" to result.applied,
            "colorMode" to result.colorMode,
            "reason" to result.reason,
            "apiLevel" to Build.VERSION.SDK_INT,
        )
    }

    private fun hdrTypeName(type: Int): String = when (type) {
        Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "dolby_vision"
        Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
        Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
        Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "hdr10_plus"
        else -> "unknown_$type"
    }
}
