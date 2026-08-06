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
 * vibration (ADR-0020) rides on. A broadcast also starts a process the system
 * has already killed, which a MethodChannel could never do.
 *
 * Receivers on this action do not compete, and that is observed rather than
 * assumed: firebase-messaging's own `FirebaseInstanceIdReceiver` and
 * firebase_messaging's `FlutterFirebaseMessagingReceiver` are both declared for
 * it with the same permission and no priority, and the plugin's is where every
 * message this app already handles actually arrives — its
 * `FlutterFirebaseMessagingService.onMessageReceived` is empty for exactly that
 * reason. Two coexist today; this is the third under the same terms.
 *
 * What that argument does *not* cover is our own build dropping the
 * declaration — a manifest merge or a shrinker can, and the symptom would be a
 * card that silently stops moving, which is the bug this was written to fix.
 * `TrackPushReceiverRegistrationTest` resolves the receiver through the package
 * manager so that failure is caught here rather than on a rider's lock screen.
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
        if (data["type"] != PUSH_TYPE) {
            // Logged so `adb logcat -s TrackPush` can tell "this receiver never
            // fires" apart from "it fires and the payload is not what we think".
            // Without it, both look identical from outside: a card that does not
            // move.
            Log.i(TAG, "broadcast reached us, not a card refresh (type=${data["type"]})")
            return
        }
        // The card's own writer decides whether this reading is worth drawing:
        // a push that lost its race to a local update describes a ride less far
        // along than the one already on screen, and a cancelled session is not
        // redrawn at all.
        val drawn = TrackNotification(app).post(data)
        Log.i(TAG, if (drawn) "card refreshed" else "card refresh dropped as stale or cancelled")
    }
}
