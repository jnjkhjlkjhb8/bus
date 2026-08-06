package com.example.bus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Ends the session behind the card when 取消追蹤 is pressed.
 *
 * Declared in the manifest, so it answers even after the system has killed the
 * process — which is now reachable state, because a pushed refresh (ADR-0018)
 * can put a card in front of a rider whose app is not running. The plugin's own
 * dynamic receiver still forwards the press to Dart while an engine is alive,
 * and Dart's CancelTrack is the authoritative path; this one exists for when
 * there is no Dart to forward to.
 *
 * It cannot make that gRPC call: the install id lives in a Hive box and the
 * install secret in EncryptedSharedPreferences, neither reachable from a bare
 * receiver, and there is no gRPC stack here either. It posts the session's id to
 * a small HTTP endpoint instead, where the id itself is the credential — a
 * server-minted UUIDv4 that only ever travelled to this device (FDPL-65).
 *
 * Without it, cancelling in that state hid the card and left the session
 * running, so the rider kept being buzzed by a reminder they had just
 * cancelled.
 */
class TrackCancelReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackCancel"
        private const val CANCEL_PATH = "/api/track/cancel"
        private const val TIMEOUT_MS = 10_000
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val app = context?.applicationContext ?: return
        val trackId = intent?.getStringExtra(TrackNotification.EXTRA_TRACK_ID).orEmpty()
        // Taking the card down comes first and never depends on the network:
        // the button must always at least do the thing it says. Naming the
        // session also refuses a refresh already in flight, so the card cannot
        // repost itself a second after the rider dismissed it.
        TrackNotification(app).cancel(trackId)

        // Dart's CancelTrack is the authoritative path whenever there is a Dart:
        // it is install-bound and it tears the session down in the app too. This
        // fallback only runs when nobody is listening for the same broadcast.
        if (LiveActivityPlugin.dartIsListening) return

        if (trackId.isEmpty()) return
        val baseUrl = app.getString(R.string.api_base_url)
        if (baseUrl.isEmpty()) return

        // goAsync keeps the process alive past onReceive for the request. The
        // window it buys is bounded by the system (~10s), which is why the
        // connection timeouts are set to fit inside it rather than trusting a
        // slow network to finish.
        val pending = goAsync()
        thread {
            try {
                postCancel(baseUrl, trackId)
            } catch (e: Exception) {
                // A failed cancel is not worth surfacing: the card is already
                // gone from the rider's screen, and the session ends on its own
                // when the ride does. Retrying would mean scheduling work for a
                // ride that is probably already over.
                Log.i(TAG, "cancel could not reach the server: ${e.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }

    private fun postCancel(baseUrl: String, trackId: String) {
        val connection = URL(baseUrl.trimEnd('/') + CANCEL_PATH).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("content-type", "application/json")
            // The id is server-minted and matched against a fixed UUID shape at
            // the other end, so it cannot carry anything into the JSON.
            connection.outputStream.use { it.write("""{"track_id":"$trackId"}""".toByteArray()) }
            Log.i(TAG, "cancel posted, status ${connection.responseCode}")
        } finally {
            connection.disconnect()
        }
    }
}
