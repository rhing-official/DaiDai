package jp.rhing.daidai

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import java.net.HttpURLConnection
import java.net.URL

/**
 * 通話の着信通知（Android 12のCallStyle、2026-11-12）。アプリを閉じている間、一対・広場の
 * 通話の着信を、右が緑の「応答」・左が赤の「拒否」ボタン付きで知らせる。FCMのdata
 * メッセージ（`type`が`incoming_call`・`incoming_group_call`・`call_cancel`）から
 * [CallNotificationReceiver]が呼ぶ。応答はアプリを開いて通話へ進み（[MainActivity]）、
 * 拒否は[CallActionReceiver]がアプリを開かずに処理する。
 */
object CallNotifications {
    const val CHANNEL_ID = "incoming_call"
    const val EXTRA_ACTION = "daidai_call_action"
    const val EXTRA_KIND = "daidai_call_kind"
    const val EXTRA_CALL_ID = "daidai_call_id"
    const val EXTRA_GROUP_ID = "daidai_call_group_id"
    const val EXTRA_RING = "daidai_call_ring"
    const val ACTION_ANSWER = "answer"
    const val ACTION_DECLINE = "decline"
    const val KIND_DM = "dm"
    const val KIND_GROUP = "group"

    /** 呼び出しの長さ（アプリ側の`kCallRingTimeout`と同じ30秒）。 */
    private const val RING_TIMEOUT_MS = 30_000L

    fun notificationId(callId: String): Int = callId.hashCode()

    private fun isAppInForeground(context: Context): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processes = manager.runningAppProcesses ?: return false
        return processes.any {
            it.processName == context.packageName &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "通話の着信", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "通話の着信を知らせます"
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 600, 800, 600)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun circleBitmap(source: Bitmap): Bitmap {
        val size = minOf(source.width, source.height)
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(source, (size - source.width) / 2f, (size - source.height) / 2f, paint)
        return output
    }

    /** アイコンを取得する（失敗したらnull）。受信から10秒ほどで処理を終える必要があるため短い待ち時間にする。 */
    private fun loadIcon(url: String?): Bitmap? {
        if (url.isNullOrEmpty()) return null
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.inputStream.use { BitmapFactory.decodeStream(it) }?.let { circleBitmap(it) }
        } catch (e: Exception) {
            null
        }
    }

    private fun intentExtras(intent: Intent, kind: String, callId: String, groupId: String?): Intent =
        intent.putExtra(EXTRA_KIND, kind)
            .putExtra(EXTRA_CALL_ID, callId)
            .putExtra(EXTRA_GROUP_ID, groupId)

    fun show(context: Context, data: Map<String, String>) {
        // アプリを開いている間は、アプリ内のバナーが知らせる。
        if (isAppInForeground(context)) return
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        val callId = data["callId"] ?: return
        val kind = if (data["type"] == "incoming_group_call") KIND_GROUP else KIND_DM
        val groupId = data["groupId"]
        val callerName = data["callerName"].orEmpty()
        val isVideo = data["isVideo"] == "true"
        ensureChannel(context)

        val id = notificationId(callId)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val answerIntent = PendingIntent.getActivity(
            context,
            id,
            intentExtras(
                Intent(context, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(EXTRA_ACTION, ACTION_ANSWER)
                },
                kind,
                callId,
                groupId,
            ),
            flags,
        )
        val declineIntent = PendingIntent.getBroadcast(
            context,
            id,
            intentExtras(Intent(context, CallActionReceiver::class.java), kind, callId, groupId),
            flags,
        )
        // ロック画面では、全画面でアプリを開く（応答・拒否はアプリ内のバナーで行う）。
        val fullScreenIntent = PendingIntent.getActivity(
            context,
            id + 1,
            Intent(context, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_RING, true)
            },
            flags,
        )

        val personBuilder = Person.Builder().setName(callerName.ifEmpty { "DaiDai" }).setImportant(true)
        loadIcon(data["iconUrl"])?.let { personBuilder.setIcon(IconCompat.createWithBitmap(it)) }
        val person = personBuilder.build()

        val text = if (kind == KIND_GROUP) {
            if (isVideo) "ビデオ通話が始まりました" else "通話が始まりました"
        } else {
            if (isVideo) "ビデオ通話の着信" else "音声通話の着信"
        }
        val title = if (kind == KIND_GROUP) data["title"].orEmpty() else callerName
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setOnlyAlertOnce(false)
            .setTimeoutAfter(RING_TIMEOUT_MS)
            .setFullScreenIntent(fullScreenIntent, true)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, declineIntent, answerIntent))
            .addPerson(person)
            .build()
        // 呼び出し音を、応答・拒否・取消しまで繰り返す。
        notification.flags = notification.flags or android.app.Notification.FLAG_INSISTENT
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            // 通知の許可が無い。
        }
    }

    fun cancel(context: Context, callId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }
}
