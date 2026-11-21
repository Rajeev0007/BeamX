package io.github.rajeev0007.beamx

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Bundle
import android.media.AudioManager
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Connects the Dart remote-control code to BeamXAccessibilityService. */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Many phones drop incoming broadcast packets unless an app holds
        // this lock, so nearby PCs never appeared in the device list.
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("beamx-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    /** SHA-1 of the certificate this app is signed with (lowercase hex). */
    @Suppress("DEPRECATION")
    private fun signingSha1(): String? = try {
        val sigs = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            info.signingInfo?.apkContentsSigners
        } else {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
        }
        sigs?.firstOrNull()?.toByteArray()?.let { bytes ->
            java.security.MessageDigest.getInstance("SHA-1").digest(bytes)
                .joinToString("") { "%02x".format(it) }
        }
    } catch (e: Exception) {
        null
    }

    /** True in the Control edition, which declares the accessibility service. */
    private fun isControlEdition(): Boolean = try {
        packageManager.getServiceInfo(
            ComponentName(this, BeamXAccessibilityService::class.java), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beamx/input")
            .setMethodCallHandler { call, result ->
                val service = BeamXAccessibilityService.instance
                when (call.method) {
                    "isEnabled" -> result.success(service != null)
                    "isControlEdition" -> result.success(isControlEdition())
                    "signingSha1" -> result.success(signingSha1())
                    "openReleases" -> {
                        startActivity(Intent(Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://github.com/Rajeev0007/BeamX/releases/latest"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "openSettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "gesture" -> {
                        val points = call.argument<List<Double>>("points") ?: emptyList()
                        val duration = (call.argument<Int>("duration") ?: 50).toLong()
                        result.success(service?.gesture(points, duration) ?: false)
                    }
                    "touchCancel" -> result.success(service?.touchCancel() ?: false)
                    "touchDown", "touchMove", "touchUp" -> {
                        val x = call.argument<Double>("x") ?: 0.0
                        val y = call.argument<Double>("y") ?: 0.0
                        result.success(when (call.method) {
                            "touchDown" -> service?.touchDown(x, y)
                            "touchMove" -> service?.touchMove(x, y)
                            else -> service?.touchUp(x, y)
                        } ?: false)
                    }
                    "global" -> result.success(
                        service?.global(call.argument<String>("action") ?: "") ?: false)
                    "text" -> result.success(
                        service?.typeText(call.argument<String>("text") ?: "") ?: false)
                    "key" -> result.success(
                        service?.key(call.argument<String>("key") ?: "") ?: false)
                    "media" -> result.success(media(call.argument<String>("key") ?: ""))
                    else -> result.notImplemented()
                }
            }
    }

    /** Media keys and volume work without the accessibility service. */
    private fun media(key: String): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        fun press(code: Int) {
            val t = SystemClock.uptimeMillis()
            audio.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0))
            audio.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0))
        }
        fun volume(direction: Int) = audio.adjustStreamVolume(
            AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        when (key) {
            "media_play" -> press(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            "media_next" -> press(KeyEvent.KEYCODE_MEDIA_NEXT)
            "media_prev" -> press(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            "vol_up" -> volume(AudioManager.ADJUST_RAISE)
            "vol_down" -> volume(AudioManager.ADJUST_LOWER)
            "vol_mute" -> volume(AudioManager.ADJUST_TOGGLE_MUTE)
            else -> return false
        }
        return true
    }
}
