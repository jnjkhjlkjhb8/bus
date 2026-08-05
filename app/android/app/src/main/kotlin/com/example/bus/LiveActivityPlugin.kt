package com.example.bus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart's `AlightTrackChannel` to the tracking card.
 *
 * The card itself is [TrackNotification]'s, which needs only a [Context] so the
 * same builder serves this Activity-bound path and the server-pushed refresh a
 * dead process receives (ADR-0018). What is left here is the part that genuinely
 * needs an engine: the notification-permission prompt and the 取消追蹤 round trip
 * back to whichever bloc owns the session.
 */
class LiveActivityPlugin(
    private val context: Context,
    private val notificationPermission: NotificationPermissionCoordinator,
) {

    companion object {
        private const val CHANNEL_NAME = "com.wheres.bus/live_activity"

        /**
         * Whether an engine is listening for 取消追蹤 right now.
         *
         * Both receivers answer that broadcast, and when Dart is alive its
         * CancelTrack is the authoritative path — install-bound, and it tears
         * the session down in the app too. TrackCancelReceiver's HTTP fallback
         * would only duplicate it, so it reads this first. False on a fresh
         * process, which is exactly the state the fallback exists for.
         */
        @Volatile
        var dartIsListening: Boolean = false
            private set
    }

    private val card = TrackNotification(context)

    private var channel: MethodChannel? = null

    private var receiverRegistered = false

    // The 取消追蹤 action reaches Dart only while the process is alive. A dead
    // one is covered by TrackCancelReceiver, which is in the manifest and takes
    // the card down without needing an isolate to talk to.
    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            channel?.invokeMethod("onCancelTrack", null)
        }
    }

    @androidx.annotation.VisibleForTesting
    internal val cancelReceiverForTest: BroadcastReceiver
        get() = cancelReceiver

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        // A card on screen at registration time cannot belong to this engine —
        // no Dart code has run yet — so it is a leftover from a process the
        // system killed mid-session. On metro it may still be refreshed by
        // push, but no other mode can be, and its 取消追蹤 broadcast would reach
        // a dead dynamic receiver. Clear it before Dart starts: the session the
        // app restores will post its own.
        NotificationManagerCompat.from(context).cancel(TrackNotification.NOTIF_ID)
        ContextCompat.registerReceiver(
            context,
            cancelReceiver,
            IntentFilter(TrackNotification.CANCEL_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
        dartIsListening = true
        channel!!.setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: emptyMap()
            when (call.method) {
                "start" -> {
                    card.beginSession()
                    // Android 13+ POST_NOTIFICATIONS is a runtime permission
                    // whose grant/deny decision only reaches the app
                    // asynchronously, through onRequestPermissionsResult (see
                    // MainActivity), so `start` must not report completion to
                    // Dart until that callback has fired (whether it resolves
                    // immediately — already granted, or pre-13 — or after the
                    // user responds to the system prompt).
                    notificationPermission.request { _ ->
                        // Post regardless of the outcome: a denial makes
                        // NotificationManagerCompat.notify a silent no-op on
                        // the platform side, and tracking must never block on
                        // the user's notification choice.
                        card.post(data)
                        result.success("${TrackNotification.NOTIF_ID}")
                    }
                }
                "update" -> {
                    card.post(data)
                    result.success(null)
                }
                "stop" -> {
                    card.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Undoes [register]. The receiver holds the Activity context and the
     * channel handler holds this plugin, so both outlive the engine that
     * created them unless they are released with it — one process serving two
     * engines in sequence would otherwise stack a receiver per engine, each
     * pushing onCancelTrack at a dead Dart isolate.
     */
    fun dispose() {
        dartIsListening = false
        if (receiverRegistered) {
            context.unregisterReceiver(cancelReceiver)
            receiverRegistered = false
        }
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
