package jp.rhing.daidai

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.SpanWatcher
import android.text.Spannable
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.editing.TextInputPlugin

/**
 * 変換中の文字に、キーボード（Gboard）が付けた背景色の範囲を、Flutterへ送る（2026-11-26）。
 *
 * Gboardは、変換中の文字の中のカーソルを内部に持ち、アプリへは末尾にあると伝える。代わりに、
 * カーソルより前の範囲を濃い背景色（`BackgroundColorSpan`）で見せる。標準の入力欄はこれを描くが、
 * Flutterのエンジンは、この装飾を捨てて文字だけを`TextField`へ渡す。そのため、エンジンの内部の
 * 編集状態（`TextInputPlugin`が持つ`Editable`）から、背景色の範囲を読み取って送る。
 *
 * 背景色が変わった瞬間に送れるよう、`Editable`へ`SpanWatcher`を付けて、変化の通知で送る（遅れて
 * 表示されないように）。`Editable`は入力欄のフォーカスのたびに作り直されるので、一定間隔で
 * 取り直して、付け直す。入力欄がフォーカスされている間だけ動かす（[start]・[stop]）。
 */
class ImeSpanBridge(private val activity: Activity, private val channel: MethodChannel) {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var last: String? = null

    private var attached: Editable? = null
    private var scheduled = false

    /** 背景色の変化を、同じ操作の中でまとめて1回だけ、すぐ後に送る。 */
    private val sendNow = Runnable {
        scheduled = false
        if (!running) return@Runnable
        try {
            tick()
        } catch (_: Throwable) {
            // 内部の構造が変わった等。何も送らず、通常の表示のままにする。
        }
    }

    private fun schedule() {
        if (scheduled) return
        scheduled = true
        handler.postAtFrontOfQueue(sendNow)
    }

    private val watcher = object : SpanWatcher {
        override fun onSpanAdded(text: Spannable, what: Any, start: Int, end: Int) = schedule()
        override fun onSpanRemoved(text: Spannable, what: Any, start: Int, end: Int) = schedule()
        override fun onSpanChanged(
            text: Spannable,
            what: Any,
            ostart: Int,
            oend: Int,
            nstart: Int,
            nend: Int,
        ) = schedule()
    }

    private val poll = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                attachIfNeeded()
                schedule()
            } catch (_: Throwable) {
            }
            handler.postDelayed(this, 100)
        }
    }

    private fun currentEditable(): Editable? {
        val flutterView = findFlutterView(activity.window.decorView)
        val plugin = flutterView?.let { fieldOfType(it, TextInputPlugin::class.java) }
        return plugin?.let { fieldOfType(it, Editable::class.java) } as? Editable
    }

    /** 入力欄が替わった（`Editable`が作り直された）、または付けた監視が外れた時に、付け直す。 */
    private fun attachIfNeeded() {
        val editable = currentEditable()
        if (editable !== attached) {
            attached?.let { runCatching { it.removeSpan(watcher) } }
            attached = editable
        }
        val target = attached ?: return
        if (target.getSpanStart(watcher) < 0) {
            target.setSpan(watcher, 0, target.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
        }
    }

    fun start() {
        if (running) return
        running = true
        last = null
        handler.post(poll)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(poll)
        handler.removeCallbacks(sendNow)
        scheduled = false
        attached?.let { runCatching { it.removeSpan(watcher) } }
        attached = null
        last = null
    }

    private fun findFlutterView(v: View): FlutterView? {
        if (v is FlutterView) return v
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) findFlutterView(v.getChildAt(i))?.let { return it }
        }
        return null
    }

    /** 型で探す（R8で名前が変わっても読めるように）。 */
    private fun fieldOfType(obj: Any, type: Class<*>): Any? {
        var c: Class<*>? = obj.javaClass
        while (c != null) {
            for (f in c.declaredFields) {
                if (type.isAssignableFrom(f.type)) {
                    f.isAccessible = true
                    return f.get(obj)
                }
            }
            c = c.superclass
        }
        return null
    }

    private fun tick() {
        val editable = attached ?: currentEditable()
        val spans = ArrayList<List<Int>>()
        if (editable != null) {
            for (span in editable.getSpans(0, editable.length, BackgroundColorSpan::class.java)) {
                // キーボードが変換中の文字に付けたものだけ（`SPAN_COMPOSING`）。
                if (editable.getSpanFlags(span) and Spanned.SPAN_COMPOSING == 0) continue
                spans.add(listOf(editable.getSpanStart(span), editable.getSpanEnd(span), span.backgroundColor))
            }
        }
        val signature = spans.joinToString("|") { it.joinToString(",") }
        if (signature == last) return
        last = signature
        channel.invokeMethod("spans", spans)
    }
}
