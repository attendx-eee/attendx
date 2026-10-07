package com.andhrauniversity.attendx

import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth
// for the fingerprint/biometric prompt.
class MainActivity : FlutterFragmentActivity() {

    // Device flags the attendance record is stamped with.
    //
    // Nothing here blocks anything. Developer options being on is weak
    // evidence of anything on its own — plenty of honest people leave
    // them enabled and forget — and a student who actually meant to
    // interfere would simply turn them off first. It is recorded so that
    // if a register is ever disputed there is something to look at,
    // which is the most an on-device flag can honestly offer.
    //
    // Read through Settings.Global rather than a package, so there is
    // one less dependency whose behaviour has to be trusted.
    private val channel = "attendx/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "flags" -> result.success(deviceFlags())
                    else -> result.notImplemented()
                }
            }
    }

    private fun deviceFlags(): Map<String, Boolean> {
        fun flag(name: String): Boolean = try {
            Settings.Global.getInt(contentResolver, name, 0) != 0
        } catch (e: Exception) {
            // A manufacturer that has moved or removed the setting is
            // not a tampered device. Absence reads as "not set".
            false
        }

        return mapOf(
            "developerOptions" to
                flag(Settings.Global.DEVELOPMENT_SETTINGS_ENABLED),
            "adbEnabled" to flag(Settings.Global.ADB_ENABLED),
        )
    }
}
