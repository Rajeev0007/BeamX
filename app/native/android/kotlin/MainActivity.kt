package io.github.rajeev0007.beamx

import android.content.Intent
import android.provider.Settings
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
                    else -> result.notImplemented()
                }
            }
    }
}
