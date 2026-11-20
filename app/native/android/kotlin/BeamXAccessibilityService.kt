package io.github.rajeev0007.beamx

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Performs taps, swipes, text entry and navigation buttons for BeamX remote
 * control. It only acts on commands from an active BeamX session that the
 * phone's owner allowed, and it reads no screen content.
 */
class BeamXAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile
        var instance: BeamXAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    private fun screenSize(): Pair<Float, Float> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.maximumWindowMetrics.bounds
            Pair(b.width().toFloat(), b.height().toFloat())
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(m)
            Pair(m.widthPixels.toFloat(), m.heightPixels.toFloat())
        }
    }

    /** [points] are x,y pairs from 0 to 1 across the screen. */
    fun gesture(points: List<Double>, durationMs: Long): Boolean {
        if (points.size < 2) return false
        val (w, h) = screenSize()
        val path = Path()
        path.moveTo((points[0] * w).toFloat(), (points[1] * h).toFloat())
        var i = 2
        while (i + 1 < points.size) {
            path.lineTo((points[i] * w).toFloat(), (points[i + 1] * h).toFloat())
            i += 2
        }
        val duration = durationMs.coerceIn(1L, GestureDescription.getMaxGestureDuration())
        val stroke = GestureDescription.StrokeDescription(path, 0L, duration)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun global(action: String): Boolean = when (action) {
        "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
        "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
        "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        else -> false
    }

    private fun focusedInput(): AccessibilityNodeInfo? =
        rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)

    private fun currentText(node: AccessibilityNodeInfo): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && node.isShowingHintText) return ""
        return node.text?.toString() ?: ""
    }

    private fun setText(node: AccessibilityNodeInfo, text: String): Boolean {
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** Adds [text] to the end of the focused text field. */
    fun typeText(text: String): Boolean {
        val node = focusedInput() ?: return false
        return setText(node, currentText(node) + text)
    }

    fun key(key: String): Boolean {
        val node = focusedInput() ?: return false
        return when (key) {
            "backspace" -> {
                val t = currentText(node)
                if (t.isEmpty()) true else setText(node, t.substring(0, t.length - 1))
            }
            "enter" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
            } else {
                false
            }
            else -> false
        }
    }
}
