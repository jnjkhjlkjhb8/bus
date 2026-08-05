package com.example.bus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.RemoteMessage

/**
 * Redraws the tracking card from a server push (ADR-0018).
 *
 * The card used to be exactly as live as the Dart isolate: both native sides
 * only ever redraw when Dart hands them something, and a backgrounded app's
 * process is cached for a while and then is not. A rider mid-ride would lose
 * the reading they opened the card for, which is precisely when they need it.
 *
 * This is a receiver on the raw FCM broadcast rather than a
 * [com.google.firebase.messaging.FirebaseMessagingService], because
 * firebase_messaging already declares that service and only one may win —
 * taking it would break the Dart-side background handler that the 下車提醒
 * vibration (ADR-0020) rides on. Receivers do not compete: the plugin's own
 * receiver and this one both see every message, and a broadcast starts the
 * process when it has already been killed, which a MethodChannel could never do.
 *
 * Only `type = alight_track` is ours. Everything else — including the vibration
 * push, which has to reach Dart to buzz — is left alone.
 */
class TrackPushReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackPush"
        private const val PUSH_TYPE = "alight_track"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val app = context?.applicationContext ?: return
        val extras = intent?.extras ?: return
        val data = RemoteMessage(extras).data
        if (data["type"] != PUSH_TYPE) return
        // The card's own writer decides whether this reading is worth drawing:
        // a push that lost its race to a local update describes a ride less far
        // along than the one already on screen.
        val drawn = TrackNotification(app).post(data)
        if (!drawn) {
            Log.i(TAG, "dropped a card refresh older than the reading on screen")
        }
    }
}
