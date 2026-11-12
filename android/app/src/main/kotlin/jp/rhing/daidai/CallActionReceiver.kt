package jp.rhing.daidai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/**
 * 着信通知の「拒否」（2026-11-12）。アプリを開かずに、通知を消し、一対の通話なら通話
 * ドキュメントを`declined`にして発信側へ伝える。広場の通話は、拒否しても書き込むものは無く
 * 通知を消すだけ。
 */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(CallNotifications.EXTRA_CALL_ID) ?: return
        val kind = intent.getStringExtra(CallNotifications.EXTRA_KIND)
        CallNotifications.cancel(context, callId)
        if (kind != CallNotifications.KIND_DM) return
        val pending = goAsync()
        FirebaseFirestore.getInstance()
            .collection("calls")
            .document(callId)
            .update(mapOf("status" to "declined", "endedAt" to FieldValue.serverTimestamp()))
            .addOnCompleteListener { pending.finish() }
    }
}
