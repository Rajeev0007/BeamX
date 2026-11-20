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
    // stroke, so drags and swipes follow the remote pointer in real time.
    // All events go through one ordered queue, and only one gesture is in
    // flight at a time, because dispatching a new gesture cancels the
    // previous one.

    private enum class Kind { DOWN, MOVE, UP, CANCEL }

    private data class TouchEvent(val kind: Kind, val x: Float, val y: Float, val time: Long)

    private val queue = ArrayDeque<TouchEvent>()
    private var stroke: GestureDescription.StrokeDescription? = null
    private var inFlight: GestureDescription? = null
    private var lastX = 0f
    private var lastY = 0f
    private var lastEventTime = 0L
    private var fallbackPoints = ArrayList<Double>()
    private var fallbackStart = 0L

    private fun toScreen(x: Double, y: Double): Pair<Float, Float> {
        val (w, h) = screenSize()
        return Pair((x * w).toFloat(), (y * h).toFloat())
    }

    private val callback = object : AccessibilityService.GestureResultCallback() {
        override fun onCompleted(gestureDescription: GestureDescription?) {
            if (gestureDescription !== inFlight) return // a stale gesture
            inFlight = null
            drain()
        }

        override fun onCancelled(gestureDescription: GestureDescription?) {
            if (gestureDescription !== inFlight) return
            inFlight = null
            stroke = null // the chain broke; the next move starts a new touch
            drain()
        }
    }

    private fun dispatch(s: GestureDescription.StrokeDescription) {
        val g = GestureDescription.Builder().addStroke(s).build()
        inFlight = g
        if (!dispatchGesture(g, callback, null)) {
            inFlight = null
            stroke = null
        }
    }

    private fun enqueue(kind: Kind, x: Double, y: Double): Boolean {
        val (sx, sy) = toScreen(x, y)
        queue.addLast(TouchEvent(kind, sx, sy, System.currentTimeMillis()))
        drain()
        return true
    }

    fun touchDown(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            fallbackPoints = arrayListOf(x, y)
            fallbackStart = System.currentTimeMillis()
            return true
        }
        return enqueue(Kind.DOWN, x, y)
    }

    fun touchMove(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            if (fallbackPoints.size < 4000) fallbackPoints.addAll(listOf(x, y))
            return true
        }
        return enqueue(Kind.MOVE, x, y)
    }

    fun touchUp(x: Double, y: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            if (fallbackPoints.isEmpty()) return false
            fallbackPoints.addAll(listOf(x, y))
            val ms = (System.currentTimeMillis() - fallbackStart).coerceIn(1L, 59000L)
            val points = fallbackPoints
            fallbackPoints = ArrayList()
            return gesture(points, ms)
        }
        return enqueue(Kind.UP, x, y)
    }

    /** Lifts the finger where it is (control turned off, session ended). */
    fun touchCancel(): Boolean {
        fallbackPoints = ArrayList()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        queue.clear()
        queue.addLast(TouchEvent(Kind.CANCEL, lastX, lastY, System.currentTimeMillis()))
        drain()
        return true
    }

    private fun lift() {
        val prev = stroke ?: return
        stroke = null
        val path = Path().apply { moveTo(lastX, lastY) }
        try {
            dispatch(prev.continueStroke(path, 0L, 1L, false))
        } catch (e: IllegalStateException) {
            // Nothing to lift.
        }
    }

    private fun drain() {
        if (inFlight != null || queue.isEmpty()) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val first = queue.first()
        when (first.kind) {
            Kind.CANCEL -> {
                queue.removeFirst()
                lift()
                if (inFlight == null) drain()
            }
            Kind.DOWN -> {
                if (stroke != null) {
                    // A new finger while the old one is still down: lift it
                    // first, then this DOWN runs after that completes.
                    lift()
                    if (inFlight == null) drain()
                    return
                }
                queue.removeFirst()
                lastX = first.x
                lastY = first.y
                lastEventTime = first.time
                val path = Path().apply { moveTo(first.x, first.y) }
                val s = GestureDescription.StrokeDescription(path, 0L, 1L, true)
                stroke = s
                dispatch(s)
            }
            Kind.MOVE, Kind.UP -> {
                // Merge queued moves (and a following lift) into one path, but
                // never across a new DOWN, so a slow device can't fall behind.
                val path = Path().apply { moveTo(lastX, lastY) }
                var up = false
                var endTime = lastEventTime
                while (queue.isNotEmpty() && !up) {
                    val e = queue.first()
                    if (e.kind != Kind.MOVE && e.kind != Kind.UP) break
                    queue.removeFirst()
                    if (e.x != lastX || e.y != lastY) path.lineTo(e.x, e.y)
                    lastX = e.x
                    lastY = e.y
                    endTime = e.time
                    up = e.kind == Kind.UP
                }
                val duration = (endTime - lastEventTime).coerceIn(8L, 50L)
                lastEventTime = endTime
                val prev = stroke
                if (prev == null) {
                    // The chain broke (e.g. the system cancelled it): restart
                    // the touch from here so the drag continues.
                    if (up) {
                        drain()
                        return
                    }
                    val s = GestureDescription.StrokeDescription(path, 0L, duration, true)
                    stroke = s
                    dispatch(s)
                    return
                }
                val next = try {
                    prev.continueStroke(path, 0L, duration, !up)
                } catch (e: IllegalStateException) {
                    null
                }
                if (next == null) {
                    stroke = null
                    drain()
                    return
                }
                stroke = if (up) null else next
                dispatch(next)
            }
        }
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
