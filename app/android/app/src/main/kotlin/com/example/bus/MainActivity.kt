package com.example.bus

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var navigating = false
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureFcmChannel()
        LiveActivityPlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wheres.bus/pip",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNavigating" -> {
                        navigating = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (navigating && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(2, 1))
                    .build(),
            )
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    private fun ensureFcmChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.fcm_default_channel_id),
            getString(R.string.fcm_default_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = getString(R.string.fcm_default_channel_description)
            setShowBadge(true)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }
}
