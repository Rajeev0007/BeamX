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

    // ---------- Live touch (Android 8+) ----------
    // A finger that stays down between events: each move continues the same
    // stroke, so drags and swipes follow the remote pointer in real time
    // instead of playing back after release.

    private var stroke: GestureDescription.StrokeDescription? = null
    private var lastX = 0f
    private var lastY = 0f
    private var lastTime = 0L
    private var busy = false
    private var fallbackPoints = ArrayList<Double>()
    private var fallbackStart = 0L
    private val queue = ArrayDeque<Triple<Float, Float, Boolean>>() // x, y, isUp

    private fun toScreen(x: Double, y: Double): Pair<Float, Float> {
        val (w, h) = screenSize()
        return Pair((x * w).toFloat(), (y * h).toFloat())
    }

    private val callback = object : AccessibilityService.GestureResultCallback() {
        override fun onCompleted(gestureDescription: GestureDescription?) {
            busy = false
            drain()
        }

        override fun onCancelled(gestureDescription: GestureDescription?) {
            busy = false
            stroke = null // the chain broke; the next move starts a new touch
            drain()
        }
    }

    private fun dispatch(s: GestureDescription.StrokeDescription): Boolean {
        busy = true
        val ok = dispatchGesture(GestureDescription.Builder().addStroke(s).build(), callback, null)
        if (!ok) busy = false
        return ok
    }

    fun touchDown(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            fallbackPoints = arrayListOf(x, y)
            fallbackStart = System.currentTimeMillis()
            return true
        }
        queue.clear()
        val (sx, sy) = toScreen(x, y)
        val path = Path().apply { moveTo(sx, sy) }
        val s = GestureDescription.StrokeDescription(path, 0L, 1L, true)
        stroke = s
        lastX = sx
        lastY = sy
        lastTime = System.currentTimeMillis()
        return dispatch(s)
    }

    fun touchMove(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            if (fallbackPoints.size < 4000) fallbackPoints.addAll(listOf(x, y))
            return true
        }
        val (sx, sy) = toScreen(x, y)
        queue.addLast(Triple(sx, sy, false))
        drain()
        return true
    }

    fun touchUp(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            fallbackPoints.addAll(listOf(x, y))
            val ms = (System.currentTimeMillis() - fallbackStart).coerceIn(1L, 59000L)
            return gesture(fallbackPoints, ms)
        }
        val (sx, sy) = toScreen(x, y)
        queue.addLast(Triple(sx, sy, true))
        drain()
        return true
    }

    private fun drain() {
        if (busy || queue.isEmpty()) return
        val prev = stroke
        // Merge everything queued up to (and including) a finger lift into
        // one path, so a slow device never falls behind the pointer.
        val path = Path().apply { moveTo(lastX, lastY) }
        var up = false
        while (queue.isNotEmpty() && !up) {
            val (x, y, isUp) = queue.removeFirst()
            if (x != lastX || y != lastY) path.lineTo(x, y)
            lastX = x
            lastY = y
            up = isUp
        }
        val now = System.currentTimeMillis()
        val duration = (now - lastTime).coerceIn(1L, 250L)
        lastTime = now
        val next = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && prev != null) {
            try {
                prev.continueStroke(path, 0L, duration, !up)
            } catch (e: IllegalStateException) {
                null
            }
        } else null
        val s = next ?: GestureDescription.StrokeDescription(path, 0L, duration, !up)
        stroke = if (up) null else s
        dispatch(s)
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
