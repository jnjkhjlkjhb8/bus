package com.example.bus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/**
 * The alight-tracking Live Update: one card for bus, TRA, THSR and metro.
 *
 * Everything is built through [NotificationCompat], so a single code path
 * serves Android 16's promoted ongoing notification (status-bar chip +
 * segmented [NotificationCompat.ProgressStyle] bar) and degrades on its own to
 * a plain progress notification on older releases. The four bespoke renderers
 * this replaced had drifted into five different card vocabularies for what is
 * one intent: counting down to the stop the rider gets off at.
 *
 * The card is deliberately template-only — promoted notifications forbid
 * `setCustomContentView` and `setColorized(true)`, and that is the point: the
 * system draws it, so it stays legible on the lock screen, always-on display
 * and status bar, at the user's own theme and text size.
 */
class LiveActivityPlugin(
    private val context: Context,
    private val notificationPermission: NotificationPermissionCoordinator,
) {

    companion object {
        private const val CHANNEL_NAME = "com.wheres.bus/live_activity"
        private const val NOTIF_ID = 1001
        private const val NOTIF_CHANNEL_ID = "live_activity"
        // Broadcast fired by the card's 取消追蹤 action; the plugin catches it
        // and forwards CancelTrack to Dart, which routes it to whichever bloc
        // owns the live session.
        private const val CANCEL_ACTION = "com.wheres.bus.action.CANCEL_TRACK"

        // Stops remaining at or below which the ride reads as "act now",
        // regardless of the rider's own lead. One stop out is the last moment
        // standing up still helps.
        private const val ARRIVING_STOPS = 1
    }

    private var channel: MethodChannel? = null

    // The 取消追蹤 action lives in the notification while the app process is
    // alive (background push updates are a later phase), so a plain
    // context-registered receiver that pings Dart over the channel suffices.
    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            channel?.invokeMethod("onCancelTrack", null)
        }
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        // A card on screen at registration time cannot belong to this engine —
        // no Dart code has run yet — so it is a leftover from a process the
        // system killed mid-session. Nothing can ever update it again and
        // setOngoing(live) makes it un-swipeable, with a 取消追蹤 action whose
        // broadcast reaches a dead receiver. Clear it before Dart starts.
        NotificationManagerCompat.from(context).cancel(NOTIF_ID)
        ContextCompat.registerReceiver(
            context,
            cancelReceiver,
            IntentFilter(CANCEL_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        channel!!.setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: emptyMap()
            when (call.method) {
                "start" -> {
                    ensureChannel()
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
                        showNotification(data)
                        result.success("$NOTIF_ID")
                    }
                }
                "update" -> {
                    showNotification(data)
                    result.success(null)
                }
                "stop" -> {
                    NotificationManagerCompat.from(context).cancel(NOTIF_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @androidx.annotation.VisibleForTesting
    internal fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // A promoted ongoing notification may not sit on an IMPORTANCE_MIN
        // channel. Re-creating an existing channel with the same id only ever
        // raises importance for installs that still hold the old LOW channel;
        // the platform treats it as a no-op otherwise.
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID,
            "下車提醒",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { setShowBadge(false) }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun showNotification(data: Map<String, Any?>) {
        NotificationManagerCompat.from(context).notify(NOTIF_ID, buildTrack(data))
    }

    /**
     * The one and only card. Bus, TRA, THSR and metro differ in the strings
     * they put in it — never in its shape.
     */
    @androidx.annotation.VisibleForTesting
    internal fun buildTrack(data: Map<String, Any?>): Notification {
        val mode = data["mode"] as? String ?: "bus"
        val phase = data["phase"] as? String ?: "riding"
        val vehicleLabel = data["vehicleLabel"] as? String ?: ""
        val vehicleId = (data["vehicleId"] as? String)?.takeIf { it.isNotEmpty() }
        val board = data["boardStation"] as? String ?: ""
        val target = data["targetStation"] as? String ?: ""
        val next = data["nextStation"] as? String ?: ""
        val hopCount = max(1, (data["hopCount"] as? Number)?.toInt() ?: 1)
        val remaining = max(0, (data["remainingStops"] as? Number)?.toInt() ?: 0)
        val lead = max(1, (data["leadStops"] as? Number)?.toInt() ?: 1)
        val etaMinutes = (data["etaMinutes"] as? Number)?.toInt()
        val departureMs = (data["scheduledDepartureMs"] as? Number)?.toLong()
        val delayMinutes = (data["delayMinutes"] as? Number)?.toInt() ?: 0

        // A terminal reading lingers briefly before Dart dismisses the lease:
        // 已到站 completes the bar, 追蹤失效 must be seen. Neither may vanish
        // silently — a card that just disappears reads as "still tracking".
        val ended = phase == "arrived" || phase == "lost"
        val live = !ended
        val waiting = phase == "waiting"
        val riding = live && !waiting

        val progress = when {
            phase == "arrived" -> hopCount
            else -> (data["currentIndex"] as? Number)?.toInt() ?: 0
        }.coerceIn(0, hopCount)

        val vehicle = if (vehicleId == null) vehicleLabel else "$vehicleLabel $vehicleId"

        val title = when (phase) {
            "lost" -> "追蹤失效"
            "arrived" -> "已到 $target"
            else -> "往 $target"
        }
        val text = when {
            phase == "lost" -> "請重新綁定"
            phase == "arrived" -> "追蹤結束"
            waiting -> boardingLine(vehicle, board, departureMs, delayMinutes)
            remaining <= ARRIVING_STOPS -> "準備下車 · 下一站 $next"
            else -> "$vehicle · 下一站 $next"
        }
        // Under 7 characters, so the status-bar chip renders it in full rather
        // than collapsing to the icon alone.
        val chip = when {
            phase == "lost" -> "失效"
            phase == "arrived" -> "已到站"
            waiting -> etaChip(etaMinutes)
            remaining <= ARRIVING_STOPS -> "下一站"
            else -> "剩${remaining}站"
        }

        val ink = ContextCompat.getColor(context, R.color.track_ink)
        val approach = ContextCompat.getColor(context, R.color.track_approach)
        val arriving = ContextCompat.getColor(context, R.color.track_arriving)

        // Distance to the alight stop, as colour. The amber threshold is the
        // rider's own 提前站數 — the same number that decides when the
        // reminder buzzes — so the warm bar is the visual residue of that
        // buzz rather than a second rule to learn. A finished ride goes back
        // to Ink: red would demand an action that no longer exists.
        val warmColor = if (remaining <= ARRIVING_STOPS) arriving else approach
        // The station the warm run starts after — the rider's own 提前站數.
        // Pushed past the end while there is nothing to warn about, so a
        // waiting or finished card has no warm run at all.
        val warmFrom = if (riding) hopCount - lead else hopCount
        // Tints the notification header. Measured on a Pixel 8 / Android 17:
        // this does NOT reach the status-bar chip (system neutral surface) nor
        // the action text (device accent) — promoted cards forbid custom views
        // and setColorized, so those two colours are the platform's to choose,
        // not ours. Distance therefore lives in the progress bar, which
        // Segment.setColor does honour, and in the chip's wording.
        val accent = if (riding && remaining <= ARRIVING_STOPS) arriving else ink

        val builder = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            // The small icon is what the status-bar chip shows next to its
            // 剩N站, at about 16dp. It is the only place the card names the
            // network, so it carries the transit mode rather than a generic
            // mark: a rider glancing at the chip should know which reminder is
            // running before reading a character.
            .setSmallIcon(chipIcon(mode))
            .setColor(accent)
            .setOngoing(live)
            // Live Updates refresh on every station hop; only alert on the
            // first post.
            .setOnlyAlertOnce(true)
            .setContentTitle(title)
            .setContentText(text)
            .setShortCriticalText(chip)
            .setContentIntent(launchIntent())
            .setStyle(progressStyle(hopCount, progress, warmFrom, ink, warmColor))
            // Restores the app-name row. Without an explicit `when` the header
            // collapses to a bare icon, and a card that never says who posted
            // it is a card the rider cannot place.
            .setShowWhen(true)
            // Requests the status-bar chip. Only asked for while the session
            // is live, so a terminal card settles into an ordinary
            // notification for its last few seconds instead of holding the
            // chip on something that has stopped moving.
            .setRequestPromotedOngoing(live)

        // The time slot in that row is the last-updated stamp, not a countdown
        // to arrival: every station hop re-posts the card, so `now` is exactly
        // "as of when". A chronometer counting down to the ETA would compete
        // with the chip for the same job and keep running even after the feed
        // behind it went quiet.
        builder.setWhen(System.currentTimeMillis())

        // Retirement window: how long a silence this card may sit through
        // before the platform takes it down. Updates are local-only, so a
        // process the system killed mid-ride leaves an un-swipeable ongoing
        // card whose numbers never move again, and the as-of stamp above is
        // the only hint — one the rider has to notice and do arithmetic on.
        //
        // This is the Android half of iOS's per-mode `staleDate`
        // (LiveActivityPlugin.swift), with one difference that sets the
        // numbers: ActivityKit *marks* a stale card, the platform here
        // *cancels* it. Cancelling a card the rider is still riding behind is
        // the worse error of the two, so the windows are double the iOS ones —
        // long enough that no live session can be cut off (every mode re-posts
        // at least once a minute while the app runs), short enough that a dead
        // process is cleaned up in minutes rather than sitting there until the
        // next launch. A terminal card gets no timeout: Dart dismisses it
        // after its own linger.
        if (live) builder.setTimeoutAfter(staleWindowMs(mode))

        // Below Android 16 there is no chip, so the reading has to live in the
        // notification itself. On 16+ this would only duplicate the chip.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) {
            builder.setSubText(chip)
        }

        if (live) {
            builder.addAction(
                NotificationCompat.Action.Builder(
                    IconCompat.createWithResource(context, R.drawable.ic_track_cancel),
                    "取消追蹤",
                    cancelIntent(),
                ).build(),
            )
        }

        return builder.build()
    }

    /**
     * The progress bar: one continuous run from the board stop to the alight
     * stop, a square at every station along it, a hollow ring where the rider
     * got on, a flag on the stop they want, and the map's own user puck as the
     * tracker.
     *
     * Stations are **points**, not segments. A segment renders as a rounded
     * bar and a point as a square tick, and a station is a discrete event on a
     * continuous ride — so the ride is the segments and each station is a mark
     * on them. The station the reminder fires at is the one square in the warm
     * colour, which makes the bar answer three questions at a glance: where am
     * I, where will I be warned, where do I get off.
     *
     * Colour rides on what is **left**, not on what is done: the travelled
     * stretch greys out behind the tracker and the run still to come carries
     * the distance colour. Stops already passed cannot be acted on.
     *
     * Both halves are coloured explicitly rather than through
     * `setStyledByProgress(true)`. Measured on a Pixel 8 / Android 17, that
     * flag fades everything past the tracker to a bare grey rule: upcoming
     * stations lose their squares and the reminder marker vanishes — which is
     * precisely the one it exists to show *before* the rider reaches it.
     */
    private fun progressStyle(
        hopCount: Int,
        progress: Int,
        warmFrom: Int,
        calmColor: Int,
        warmColor: Int,
    ): NotificationCompat.ProgressStyle {
        val passed = ContextCompat.getColor(context, R.color.track_passed)
        val notch = ContextCompat.getColor(context, R.color.track_notch)

        return NotificationCompat.ProgressStyle()
            .setProgress(progress)
            // One segment per hop, so every station divides the bar on both
            // halves of the ride. Not two long runs split at the tracker: the
            // platform stops drawing points past the current progress, so with
            // one long segment ahead the whole run to come collapses into an
            // unbroken rule (verified on a Pixel 8 / Android 17).
            //
            // The reminder's station is marked by where the colour turns
            // rather than by a marker on it — for the same reason. Everything
            // past it is warm, so the bar reads as "black while there is
            // nothing to do, warm from the stop you asked to be warned at".
            // As the ride goes on the warm run is all that is left, which is
            // exactly the state it describes.
            .setProgressSegments(
                (1..hopCount).map { at ->
                    NotificationCompat.ProgressStyle.Segment(1).setColor(
                        when {
                            at <= progress -> passed
                            at > warmFrom -> warmColor
                            else -> calmColor
                        },
                    )
                },
            )
            // Squares on the stations already behind the tracker. Nothing is
            // emitted ahead of it: the platform drops those, and a crowd of
            // never-drawn ticks buys nothing.
            .setProgressPoints(
                (1..progress.coerceAtMost(hopCount - 1)).map { at ->
                    NotificationCompat.ProgressStyle.Point(at).setColor(notch)
                },
            )
            .setProgressStartIcon(
                IconCompat.createWithResource(context, R.drawable.ic_track_board),
            )
            .setProgressEndIcon(
                IconCompat.createWithResource(context, R.drawable.ic_track_alight),
            )
            .setProgressTrackerIcon(
                IconCompat.createWithResource(context, R.drawable.ic_track_puck),
            )
            .setStyledByProgress(false)
    }

    /**
     * TRA and THSR share the rail glyph: at chip size the useful distinction
     * is rail-versus-bus-versus-metro, and the card's text already says which
     * train.
     */
    private fun chipIcon(mode: String): Int = when (mode) {
        "metro" -> R.drawable.ic_track_metro
        "tra", "thsr" -> R.drawable.ic_track_rail
        else -> R.drawable.ic_track_bus
    }

    /**
     * How long this mode's card may go without an update before the platform
     * retires it — twice the matching iOS `staleDate` window, because these
     * windows delete rather than annotate. The feeds are not one cadence: bus
     * ETA lands every 30 s, a metro card moves once per station hop, and a
     * train can sit between two rural stations for a long time with nothing
     * wrong.
     */
    private fun staleWindowMs(mode: String): Long = when (mode) {
        "metro" -> 12 * 60 * 1000L
        "tra", "thsr" -> 40 * 60 * 1000L
        else -> 6 * 60 * 1000L
    }

    /**
     * The line shown while the rider is still on the platform.
     *
     * A train they have not caught is described by its timetable — the printed
     * departure and, named separately, the slip against it — because that is
     * what they are comparing the app to on the station board. Folding the
     * delay into the time silently would make the card disagree with the board
     * for no visible reason. Everything else (metro, and any train with no
     * timetable to hand) falls back to naming the stop they board at, with the
     * chip carrying the minutes.
     */
    private fun boardingLine(
        vehicle: String,
        board: String,
        departureMs: Long?,
        delayMinutes: Int,
    ): String {
        if (departureMs == null) return "$vehicle · 於 $board 上車"
        val clock = timeFormat.format(java.util.Date(departureMs))
        val late = if (delayMinutes > 0) " · 誤點 ${delayMinutes} 分" else ""
        return "$vehicle · $clock 開$late"
    }

    private val timeFormat = java.text.SimpleDateFormat(
        "HH:mm",
        java.util.Locale.getDefault(),
    )

    private fun etaChip(etaMinutes: Int?): String = when {
        etaMinutes == null -> "進站中"
        etaMinutes <= 0 -> "進站中"
        else -> "${etaMinutes}分"
    }

    // Broadcast PendingIntent the 取消追蹤 action fires; cancelReceiver catches
    // it and forwards to Dart.
    private fun cancelIntent(): PendingIntent {
        val intent = Intent(CANCEL_ACTION).setPackage(context.packageName)
        return PendingIntent.getBroadcast(
            context,
            1,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun launchIntent(): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
