package jp.rhing.daidai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * FCMのメッセージ（`com.google.android.c2dm.intent.RECEIVE`）を、firebase_messagingの
 * レシーバーと並んで受け取り、通話の着信・取消しのデータメッセージだけを[CallNotifications]で
 * 扱う（2026-11-12）。それ以外のメッセージは何もしない（プラグイン側が従来どおり扱う）。
 */
class CallNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val data = HashMap<String, String>()
        for (key in extras.keySet()) {
            extras.getString(key)?.let { data[key] = it }
        }
        when (data["type"]) {
            "incoming_call", "incoming_group_call" -> {
                // アイコンの取得に時間がかかるため、受信処理を延長して別スレッドで行う。
                val pending = goAsync()
                Thread {
                    try {
                        CallNotifications.show(context.applicationContext, data)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            "call_cancel" -> data["callId"]?.let { CallNotifications.cancel(context, it) }
        }
    }
}
