package com.example.media_client.tv_exo

import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Logs every data source Media3 opens, at logcat tag [TvExoPlayerBridge.TAG].
 *
 * Added while chasing a 4K remux that rebuffered every ~20 s while the transport
 * reported healthy aggregate throughput. The transport could only see *what* it
 * was asked to serve (three concurrent localhost streams on one file: one at the
 * playback position, one at `bytes=0-`, one at `bytes=7546-`); it could not see
 * whether the player was still reading the extra two, and Media3's own progress
 * logs say nothing about individual loads.
 *
 * Wrapping the factory answers both: one `ds#N open` line per load (so the load
 * count and each open position are authoritative), a `read` line every
 * [READ_LOG_EVERY_BYTES] so a stream that is never closed but keeps draining
 * shows up as ongoing reads, and a `close` line whose absence proves the load
 * outlived the player's interest in it.
 */
class LoggingDataSourceFactory(
    private val delegate: DataSource.Factory,
) : DataSource.Factory {

    private val nextId = AtomicInteger(1)

    override fun createDataSource(): DataSource =
        LoggingDataSource(delegate.createDataSource(), nextId.getAndIncrement())
}

private const val READ_LOG_EVERY_BYTES = 32L * 1024 * 1024

private class LoggingDataSource(
    private val delegate: DataSource,
    private val id: Int,
) : DataSource {

    private val label = "ds#$id"
    private var openedAtMs = 0L
    private var bytesRead = 0L
    private var nextLogBytes = READ_LOG_EVERY_BYTES
    private var lastReadAtMs = 0L

    override fun addTransferListener(transferListener: TransferListener) {
        delegate.addTransferListener(transferListener)
    }

    @Throws(IOException::class)
    override fun open(dataSpec: DataSpec): Long {
        val length = delegate.open(dataSpec)
        openedAtMs = SystemClock.elapsedRealtime()
        lastReadAtMs = openedAtMs
        Log.i(
            TvExoPlayerBridge.TAG,
            "$label open pos=${dataSpec.position} length=${dataSpec.length} " +
                "uri=${dataSpec.uri}",
        )
        return length
    }

    @Throws(IOException::class)
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val read = delegate.read(buffer, offset, length)
        val now = SystemClock.elapsedRealtime()
        if (read > 0) {
            bytesRead += read
            if (bytesRead >= nextLogBytes) {
                nextLogBytes += READ_LOG_EVERY_BYTES
                val elapsed = (now - openedAtMs).coerceAtLeast(1)
                val mbps = bytesRead * 8.0 / (elapsed * 1000.0)
                Log.i(
                    TvExoPlayerBridge.TAG,
                    "$label read ${bytesRead / 1048576}MB in ${elapsed}ms " +
                        "= ${"%.1f".format(mbps)} Mbps",
                )
            }
        } else if (read == C.RESULT_END_OF_INPUT) {
            Log.i(
                TvExoPlayerBridge.TAG,
                "$label EOF after ${bytesRead / 1048576}MB " +
                    "alive=${now - openedAtMs}ms",
            )
        }
        lastReadAtMs = now
        return read
    }

    override fun getUri(): Uri? = delegate.uri

    @Throws(IOException::class)
    override fun close() {
        val now = SystemClock.elapsedRealtime()
        Log.i(
            TvExoPlayerBridge.TAG,
            "$label close after ${bytesRead / 1048576}MB " +
                "alive=${now - openedAtMs}ms idle=${now - lastReadAtMs}ms",
        )
        delegate.close()
    }
}
