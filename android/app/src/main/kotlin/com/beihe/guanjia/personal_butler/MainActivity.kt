package com.beihe.guanjia.personal_butler

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method != OPEN_APP_NOTIFICATION_SETTINGS) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                result.success(openAppNotificationSettings())
            }
    }

    private fun openAppNotificationSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    },
                )
                return true
            } catch (_: RuntimeException) {
                // Some Android variants do not expose the notification page.
            }
        }

        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private companion object {
        const val CHANNEL_NAME =
            "com.beihe.guanjia.personal_butler/system_settings"
        const val OPEN_APP_NOTIFICATION_SETTINGS = "openAppNotificationSettings"
    }
}
