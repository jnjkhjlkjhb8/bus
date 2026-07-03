package com.example.bus

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class LiveActivityPlugin(private val context: Context) {

    companion object {
        private const val CHANNEL_NAME = "com.jnjk.bus/live_activity"
        private const val NOTIF_ID = 1001
        private const val NOTIF_CHANNEL_ID = "live_activity"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: emptyMap()
            when (call.method) {
                "start" -> {
                    ensureChannel()
                    ensurePermission()
                    showNotification(data)
                    result.success("$NOTIF_ID")
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

    private fun ensurePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    context as Activity,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIF_ID,
                )
            }
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "即時交通",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun showNotification(data: Map<String, Any?>) {
        val routeOrTrain = data["routeOrTrain"] as? String ?: ""
        val nextStation = data["nextStation"] as? String ?: ""
        val progress = ((data["progressPercent"] as? Double ?: 0.0) * 100).toInt()

        val collapsed = RemoteViews(context.packageName, R.layout.notification_live_activity).apply {
            setTextViewText(R.id.tv_next_station, "下一站 $nextStation")
            setTextViewText(R.id.tv_route, routeOrTrain)
        }

        val expanded = RemoteViews(context.packageName, R.layout.notification_live_activity_expanded).apply {
            setTextViewText(R.id.tv_next_station_exp, "下一站 $nextStation")
            setTextViewText(R.id.tv_route_exp, routeOrTrain)
            setImageViewBitmap(R.id.iv_seg_progress, makeSegBitmap(progress))
        }

        val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()

        NotificationManagerCompat.from(context).notify(NOTIF_ID, notification)
    }

    private fun makeSegBitmap(progressPct: Int): Bitmap {
        val bw = 800
        val bh = 24
        val gap = 10
        val r = bh / 2f
        val filledW = ((progressPct.coerceIn(0, 100) / 100f) * (bw - gap)).toInt().coerceAtLeast(0)
        val remainW = (bw - gap - filledW).coerceAtLeast(0)
        val bmp = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val cv = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (filledW > 0) {
            paint.color = 0xFF4CAF50.toInt()
            cv.drawRoundRect(RectF(0f, 0f, filledW.toFloat(), bh.toFloat()), r, r, paint)
        }
        if (remainW > 0) {
            paint.color = 0xFFD0D0D0.toInt()
            cv.drawRoundRect(RectF((filledW + gap).toFloat(), 0f, bw.toFloat(), bh.toFloat()), r, r, paint)
        }
        return bmp
    }
}
