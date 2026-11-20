package io.github.rajeev0007.beamx

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Connects the Dart remote-control code to BeamXAccessibilityService. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beamx/input")
            .setMethodCallHandler { call, result ->
                val service = BeamXAccessibilityService.instance
                when (call.method) {
                    "isEnabled" -> result.success(service != null)
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
