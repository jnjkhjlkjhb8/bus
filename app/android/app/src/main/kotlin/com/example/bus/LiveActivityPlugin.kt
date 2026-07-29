package com.example.bus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.ceil
import kotlin.math.max

class LiveActivityPlugin(
    private val context: Context,
    private val notificationPermission: NotificationPermissionCoordinator,
) {

    companion object {
        private const val CHANNEL_NAME = "com.wheres.bus/live_activity"
        private const val NOTIF_ID = 1001
        private const val NOTIF_CHANNEL_ID = "live_activity"
        // Broadcast fired by the metro Live Update's 取消追蹤 action; the plugin
        // catches it and forwards CancelTrack to Dart (ADR-0015). No existing
        // notification actions in this app, so this is the routing seam.
        private const val CANCEL_ACTION = "com.wheres.bus.action.CANCEL_TRACK"
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
                        // NotificationManagerCompat.notify a silent no-op on the
                        // platform side, and the Live Activity card must never
                        // block navigation on the user's notification choice.
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

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Live Updates require at least DEFAULT importance to be promoted to the
            // status-bar chip. Re-creating an existing channel with the same id only
            // ever raises importance for installs that still have the old LOW channel;
            // the platform treats it as a no-op otherwise.
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "即時交通",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { setShowBadge(false) }
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun showNotification(data: Map<String, Any?>) {
        val notification = buildNotification(data)
        NotificationManagerCompat.from(context).notify(NOTIF_ID, notification)
    }

    private fun buildNotification(data: Map<String, Any?>): Notification {
        val mode = data["mode"] as? String ?: "waiting"
        if (mode == "board") {
            return buildBoard(data)
        }
        if (mode == "mrt_track") {
            return buildMrtTrack(data)
        }
        val routeOrTrain = data["routeOrTrain"] as? String ?: ""
        val fromStation = data["fromStation"] as? String ?: ""
        val nextStation = data["nextStation"] as? String ?: ""
        val alightStation = data["alightStation"] as? String
        val remainingStops = (data["remainingStops"] as? Number)?.toInt()
        val progressPct = ((data["progressPercent"] as? Number)?.toDouble() ?: 0.0)
            .coerceIn(0.0, 1.0)
        val etaMs = (data["etaMs"] as? Number)?.toLong()
            ?: (data["arrivalTimeMs"] as? Number)?.toLong()
        val walkMinutes = (data["walkMinutes"] as? Number)?.toInt() ?: 0
        val plate = data["plate"] as? String
        val routeNumber = data["routeNumber"] as? String

        val riding = mode == "riding"
        val pinned = !plate.isNullOrEmpty()

        val chip: String
        val title: String
        val text: String
        if (pinned) {
            // Pinned-vehicle 追蹤 card: distinct from the generic waiting/riding
            // copy above, shows the tracked plate instead of route progress text.
            chip = remainingStops?.let { "${it}站" } ?: etaChip(etaMs)
            title = "${routeNumber ?: routeOrTrain}  $plate"
            text = "往 ${alightStation ?: nextStation}" +
                (remainingStops?.let { "  還剩 $it 站" } ?: "")
        } else if (riding) {
            chip = if (remainingStops != null) "${remainingStops}站" else "行駛中"
            title = "$routeOrTrain  下一站 $nextStation"
            text = if (alightStation != null) {
                "$alightStation 下車" +
                    (if (remainingStops != null) "  剩 $remainingStops 站" else "")
            } else {
                "下一站 $nextStation"
            }
        } else {
            chip = etaChip(etaMs)
            title = "下一班 $routeOrTrain"
            text = "於 $fromStation 上車" +
                (if (walkMinutes > 0) "  步行 $walkMinutes 分" else "")
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            // Pinned tracking shows the same progress bar as riding on the
            // promoted (Android 16+) surface.
            buildPromoted(riding || pinned, title, text, chip, progressPct)
        } else {
            // Legacy surface has no room for both a progress bar and the
            // plate/route title, so the pinned card falls back to setSubText
            // (same branch as the non-riding waiting card).
            buildLegacy(riding, title, text, chip, (progressPct * 100).toInt())
        }
    }

    // 站點 ETA board: a stop and its routes, not a single tracked journey.
    // No progress bar — the board has no single destination to progress
    // toward, so both surfaces render a plain multi-line route list.
    private fun buildBoard(data: Map<String, Any?>): Notification {
        val stopName = data["stopName"] as? String ?: ""
        @Suppress("UNCHECKED_CAST")
        val routes = (data["routes"] as? List<Map<String, Any?>>) ?: emptyList()
        val lines = routes.map { r -> "${r["route"]}  ${r["destination"]}  ${r["eta"]}" }
        val firstRoute = routes.firstOrNull()
        val chip = (firstRoute?.get("eta") as? String)
            ?: (firstRoute?.get("route") as? String)
            ?: ""
        val text = lines.firstOrNull() ?: stopName

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            Notification.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_transit)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentTitle(stopName)
                .setContentText(text)
                .setShortCriticalText(chip)
                .setContentIntent(launchIntent())
                .setFlag(Notification.FLAG_PROMOTED_ONGOING, true)
                .setStyle(
                    Notification.InboxStyle().also { style ->
                        lines.forEach { style.addLine(it) }
                    },
                )
                .build()
        } else {
            NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_transit)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentTitle(stopName)
                .setContentText(text)
                .setSubText(chip)
                .setContentIntent(launchIntent())
                .setStyle(
                    NotificationCompat.InboxStyle().also { style ->
                        lines.forEach { style.addLine(it) }
                    },
                )
                .build()
        }
    }

    private fun etaChip(etaMs: Long?): String {
        if (etaMs == null) return "進站中"
        val remainMs = etaMs - System.currentTimeMillis()
        if (remainMs <= 0) return "進站中"
        val minutes = max(1L, ceil(remainMs / 60000.0).toLong())
        return "${minutes}分"
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.BAKLAVA)
    private fun buildPromoted(
        riding: Boolean,
        title: String,
        text: String,
        chip: String,
        progressPct: Double,
    ): Notification {
        val builder = Notification.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_transit)
            .setOngoing(true)
            // Live Updates refresh frequently; only alert on the first post.
            .setOnlyAlertOnce(true)
            .setContentTitle(title)
            .setContentText(text)
            .setShortCriticalText(chip)
            .setContentIntent(launchIntent())
            // Request promotion to the status-bar chip (POST_PROMOTED_NOTIFICATIONS).
            .setFlag(Notification.FLAG_PROMOTED_ONGOING, true)

        if (riding) {
            builder.setStyle(
                Notification.ProgressStyle()
                    .setProgress((progressPct * 100).toInt())
                    .setProgressSegments(
                        listOf(Notification.ProgressStyle.Segment(100)),
                    )
                    .setProgressTrackerIcon(
                        Icon.createWithResource(context, R.drawable.ic_stat_transit),
                    ),
            )
        }

        return builder.build()
    }

    private fun buildLegacy(
        riding: Boolean,
        title: String,
        text: String,
        chip: String,
        progressPct: Int,
    ): Notification {
        val builder = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_transit)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(launchIntent())

        if (riding) {
            builder.setProgress(100, progressPct, false)
        } else {
            builder.setSubText(chip)
        }

        return builder.build()
    }

    // Metro 下車提醒 Live Update (ADR-0015): a per-station ProgressStyle with one
    // segment per hop and a point at the alight stop, 往 {target} / 下一站 {next},
    // the 剩N站 count only in the status-bar chip (setShortCriticalText, never in
    // the body), and a single 取消追蹤 action. Below Android 16 it degrades to a
    // plain progress bar like buildLegacy.
    private fun buildMrtTrack(data: Map<String, Any?>): Notification {
        val target = data["alightStation"] as? String ?: ""
        val next = data["nextStation"] as? String ?: ""
        val remaining = (data["remainingStops"] as? Number)?.toInt() ?: 0
        val currentIndex = (data["currentIndex"] as? Number)?.toInt() ?: 0
        val targetIndex = max(1, (data["targetIndex"] as? Number)?.toInt() ?: 1)
        // A terminal reading lingers briefly before Dart dismisses the lease:
        // 已到站 completes the bar; 追蹤失效 must be seen, never a silent vanish.
        val ended = data["endedStatus"] as? String
        val progress =
            (if (ended == "arrived") targetIndex else currentIndex).coerceIn(0, targetIndex)
        val chip = when (ended) {
            "arrived" -> "已到站"
            "lost" -> "失效"
            else -> "剩${remaining}站"
        }
        val title = when (ended) {
            "arrived" -> "已到 $target"
            "lost" -> "追蹤失效"
            else -> "往 $target"
        }
        val text = when (ended) {
            "arrived" -> "追蹤結束"
            "lost" -> "請重新綁定列車"
            else -> "下一站 $next"
        }
        val live = ended == null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            Notification.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_transit)
                .setOngoing(live)
                .setOnlyAlertOnce(true)
                .setContentTitle(title)
                .setContentText(text)
                .setShortCriticalText(chip)
                .setContentIntent(launchIntent())
                .setFlag(Notification.FLAG_PROMOTED_ONGOING, live)
                .setStyle(
                    Notification.ProgressStyle()
                        .setProgress(progress)
                        // One segment per hop board→target; the filled portion
                        // is the stations already passed (current_index).
                        .setProgressSegments(
                            List(targetIndex) {
                                Notification.ProgressStyle.Segment(1)
                            },
                        )
                        // A point marks the alight stop at the path's end.
                        .setProgressPoints(
                            listOf(Notification.ProgressStyle.Point(targetIndex)),
                        )
                        .setProgressTrackerIcon(
                            Icon.createWithResource(context, R.drawable.ic_stat_transit),
                        ),
                )
                .also { b ->
                    if (live) {
                        b.addAction(
                            Notification.Action.Builder(
                                Icon.createWithResource(context, R.drawable.ic_stat_transit),
                                "取消追蹤",
                                cancelIntent(),
                            ).build(),
                        )
                    }
                }
                .build()
        } else {
            NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_transit)
                .setOngoing(live)
                .setOnlyAlertOnce(true)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(launchIntent())
                .setProgress(targetIndex, progress, false)
                .also { b -> if (live) b.addAction(0, "取消追蹤", cancelIntent()) }
                .build()
        }
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
