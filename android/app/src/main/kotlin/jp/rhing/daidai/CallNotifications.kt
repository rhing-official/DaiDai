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
    /**
     * 着信音ごとの通常・緊急のチャンネルIDの接頭辞（2026-11-25）。チャンネルの音は作った後で変えられない
     * ため、DaiDaiの着信音（設定で選ぶ`ringtoneSound`）ごとに別のチャンネルを作る。以前は端末の標準の
     * 着信音を鳴らす`incoming_call`・`incoming_call_urgent`だった（[LEGACY_CHANNEL_IDS]、削除する）。
     */
    const val CHANNEL_ID = "incoming_call"
    private val LEGACY_CHANNEL_IDS = listOf("incoming_call", "incoming_call_urgent") +
        listOf("phonebooth_ring", "marimba_ring", "european_ringback", "futuristic_dial")
            .flatMap { listOf("incoming_call_$it", "incoming_call_urgent_$it") }

    /** `res/raw`に同梱した着信音。idはファイル名と`SoundPreset.id`に一致する。 */
    private val RING_SOUND_IDS = listOf("phonebooth_ring", "marimba_ring", "european_ringback", "futuristic_dial")
    private const val DEFAULT_RING_SOUND_ID = "marimba_ring"

    /** 音・振動なしの着信チャンネル（設定で着信音をオフにした端末用、2026-11-18）。 */
    const val SILENT_CHANNEL_ID = "incoming_call_silent"

    /**
     * 緊急の着信のチャンネル（おやすみモードを貫通する、2026-11-25）。チャンネルは作った後で設定を
     * 変えられないため、通常のチャンネルとは別に作る。端末の「おやすみモードの許可」が有る時だけ作る。
     */
    const val URGENT_CHANNEL_ID = "incoming_call_urgent"
    const val URGENT_SILENT_CHANNEL_ID = "incoming_call_urgent_silent"
    const val EXTRA_CALLER_NAME = "daidai_call_caller_name"
    const val EXTRA_ICON_URL = "daidai_call_icon_url"
    const val EXTRA_IS_VIDEO = "daidai_call_is_video"
    const val EXTRA_ACTION = "daidai_call_action"
    const val EXTRA_KIND = "daidai_call_kind"
    const val EXTRA_CALL_ID = "daidai_call_id"
    const val EXTRA_GROUP_ID = "daidai_call_group_id"

    /** 着信の宛先のアカウントのid。使っていないアカウント宛てか判断する（2026-11-24）。 */
    const val EXTRA_RECIPIENT_ID = "daidai_call_recipient_id"
    const val EXTRA_RING = "daidai_call_ring"
    const val ACTION_ANSWER = "answer"
    const val ACTION_DECLINE = "decline"

    /** 通話中の通知（前面サービス）のタップ。今の画面に重ねて通話画面を開く（2026-11-18）。 */
    const val ACTION_OPEN_CALL = "open_call"
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

    /**
     * 設定>着信音・呼出音の「着信音を鳴らす」（端末ごと、既定オン）。DartのSharedPreferences
     * （`flutter.`が付く同じファイル）から読む。
     */
    /**
     * 設定で選んだ着信音のid。未設定・不明・アップロード音源（通知のチャンネルでは鳴らせない）は
     * 既定の音（`SoundCategory.ringtone.defaultPreset`と同じ）。
     */
    fun ringSoundId(context: Context): String {
        val saved = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.ringtoneSound", null)
        return if (saved != null && saved in RING_SOUND_IDS) saved else DEFAULT_RING_SOUND_ID
    }

    /** 音の指定が壊れていたチャンネル（1205・1206）を作り直すため、IDに版（v2）を付ける。 */
    private fun ringChannelId(soundId: String, urgent: Boolean) =
        if (urgent) "incoming_call_urgent_v2_$soundId" else "incoming_call_v2_$soundId"

    private fun ringSoundUri(context: Context, soundId: String): android.net.Uri {
        val resId = context.resources.getIdentifier(soundId, "raw", context.packageName)
        if (resId != 0) return android.net.Uri.parse("android.resource://${context.packageName}/$resId")
        // 音が見つからない（リソースの縮小で消えた等）。無音のまま気付かないよう、標準の通知音に落とす。
        android.util.Log.w("DaiDaiCall", "ring sound missing: $soundId")
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    private fun ringAudioAttributes() = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    fun ringtoneEnabled(context: Context): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.callRingtoneEnabled", true)

    /**
     * 着信の宛先[recipientId]が、今アプリでサインインしているアカウントと違うか（2026-11-24）。
     * 今のアカウントのidは、Dart側が端末の設定（`currentAccountId`、アカウントの切り替えで入れ替え
     * ない）に書いたもの。宛先が無い（古いサーバー）時は、従来どおり今のアカウント宛てとみなす。
     */
    fun isForOtherAccount(context: Context, recipientId: String?): Boolean {
        if (recipientId.isNullOrEmpty()) return false
        val current = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.currentAccountId", null)
        return current != recipientId
    }

    /**
     * 端末のおやすみモード（通知の制限）が、今オンか（2026-11-25）。許可は要らない。通常の発信の
     * 着信は、オンの間は音も全画面も出さない（`CATEGORY_CALL`の通知は、おやすみモードの「通話を
     * 許可」「繰り返しの発信者」の設定で鳴ってしまうため、アプリ側で止める）。
     */
    fun isDndActive(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val filter = context.getSystemService(NotificationManager::class.java).currentInterruptionFilter
        return filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
    }

    /** 端末の「おやすみモードの許可」を、このアプリが持っているか（Android 6以降）。 */
    fun hasPolicyAccess(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted
    }

    /**
     * 緊急の着信のチャンネルを用意する。許可が無い時は作らない（許可が無いと、貫通の指定が効かない
     * チャンネルが残ってしまうため）。既に有っても貫通の設定が外れていれば、作り直す。
     */
    private fun ensureUrgentChannels(context: Context, soundId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !hasPolicyAccess(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        for ((id, name, ring) in listOf(
            Triple(ringChannelId(soundId, true), "通話の着信（緊急）", true),
            Triple(URGENT_SILENT_CHANNEL_ID, "通話の着信（緊急・音なし）", false),
        )) {
            val existing = manager.getNotificationChannel(id)
            if (existing != null && existing.canBypassDnd()) continue
            if (existing != null) manager.deleteNotificationChannel(id)
            val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "相手が緊急で発信した通話の着信を、おやすみモード中も知らせます"
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                if (ring) {
                    setSound(ringSoundUri(context, soundId), ringAudioAttributes())
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 800, 600, 800, 600)
                } else {
                    setSound(null, null)
                    enableVibration(false)
                }
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun ensureChannel(context: Context, soundId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        // 端末の標準の着信音を鳴らしていた旧チャンネルを消す。
        for (legacy in LEGACY_CHANNEL_IDS) {
            if (manager.getNotificationChannel(legacy) != null) manager.deleteNotificationChannel(legacy)
        }
        if (manager.getNotificationChannel(SILENT_CHANNEL_ID) == null) {
            val silent = NotificationChannel(
                SILENT_CHANNEL_ID,
                "通話の着信（音なし）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "着信音をオフにしている時の、通話の着信の表示です"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(silent)
        }
        val id = ringChannelId(soundId, false)
        if (manager.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(id, "通話の着信", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "通話の着信を、設定で選んだ着信音で知らせます"
            setSound(ringSoundUri(context, soundId), ringAudioAttributes())
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

    private fun intentExtras(
        intent: Intent,
        kind: String,
        callId: String,
        groupId: String?,
        recipientId: String?,
    ): Intent =
        intent.putExtra(EXTRA_KIND, kind)
            .putExtra(EXTRA_CALL_ID, callId)
            .putExtra(EXTRA_GROUP_ID, groupId)
            .putExtra(EXTRA_RECIPIENT_ID, recipientId)

    fun show(context: Context, data: Map<String, String>) {
        // アプリを開いている間は、アプリ内のバナーが知らせる。ただし、アプリ内のバナーは今の
        // アカウント宛ての着信しか見ないので、使っていないアカウント宛てはここで知らせる（2026-11-24）。
        val recipientId = data["recipientId"]
        if (isAppInForeground(context) && !isForOtherAccount(context, recipientId)) return
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        val callId = data["callId"] ?: return
        val kind = if (data["type"] == "incoming_group_call") KIND_GROUP else KIND_DM
        val groupId = data["groupId"]
        val callerName = data["callerName"].orEmpty()
        val isVideo = data["isVideo"] == "true"
        // 緊急の発信で、受け手が「おやすみモードの許可」を与えている時だけ、貫通するチャンネルで出す。
        val urgent = data["urgent"] == "true" && hasPolicyAccess(context)
        // 診断用（2026-11-25）。緊急の判定と、おやすみモードの状態を、実機のログで確かめる。
        android.util.Log.d(
            "DaiDaiCall",
            "incoming urgentFlag=${data["urgent"]} policyAccess=${hasPolicyAccess(context)} dnd=${isDndActive(context)}",
        )
        val soundId = ringSoundId(context)
        ensureChannel(context, soundId)
        if (urgent) ensureUrgentChannels(context, soundId)

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
                recipientId,
            ),
            flags,
        )
        val declineIntent = PendingIntent.getBroadcast(
            context,
            id,
            intentExtras(Intent(context, CallActionReceiver::class.java), kind, callId, groupId, recipientId),
            flags,
        )
        // ロック画面では、全画面でアプリを開く（応答・拒否はアプリ内のバナーで行う）。
        val fullScreenIntent = PendingIntent.getActivity(
            context,
            id + 1,
            intentExtras(
                Intent(context, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(EXTRA_RING, true)
                    putExtra(EXTRA_CALLER_NAME, if (kind == KIND_GROUP) data["title"].orEmpty() else callerName)
                    putExtra(EXTRA_ICON_URL, data["iconUrl"])
                    putExtra(EXTRA_IS_VIDEO, isVideo)
                },
                kind,
                callId,
                groupId,
                recipientId,
            ),
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
        val ringEnabled = ringtoneEnabled(context)
        // おやすみモード中の通常の発信は、鳴らさず、全画面も出さず、静かな通知だけにする。
        // 緊急の発信（かつ許可あり）だけが貫通する。
        if (isDndActive(context) && !urgent) {
            showQuiet(
                context,
                id,
                title,
                text,
                person,
                declineIntent,
                answerIntent,
                fullScreenIntent,
            )
            return
        }
        val channelId = when {
            urgent && ringEnabled -> ringChannelId(soundId, true)
            urgent -> URGENT_SILENT_CHANNEL_ID
            ringEnabled -> ringChannelId(soundId, false)
            else -> SILENT_CHANNEL_ID
        }
        val builder = NotificationCompat.Builder(context, channelId)
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
        // 着信音をオフにしている端末は、音も振動も出さない（Android 8未満はここで止める）。
        if (!ringEnabled) builder.setSilent(true)
        val notification = builder.build()
        // 呼び出し音を、応答・拒否・取消しまで繰り返す。
        if (ringEnabled) {
            notification.flags = notification.flags or android.app.Notification.FLAG_INSISTENT
        }
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            // 通知の許可が無い。
        }
    }

    /**
     * おやすみモード中の通常の発信の着信。音・振動・全画面・`CATEGORY_CALL`なし（通話として扱われて
     * 貫通しないよう）の、静かな通知。タップで着信の画面を開き、応答・拒否のボタンは付ける。
     */
    private fun showQuiet(
        context: Context,
        id: Int,
        title: String,
        text: String,
        person: Person,
        declineIntent: PendingIntent,
        answerIntent: PendingIntent,
        openIntent: PendingIntent,
    ) {
        val builder = NotificationCompat.Builder(context, SILENT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setSilent(true)
            .setOngoing(true)
            .setTimeoutAfter(RING_TIMEOUT_MS)
            .setContentIntent(openIntent)
            .addAction(0, "拒否", declineIntent)
            .addAction(0, "応答", answerIntent)
            .addPerson(person)
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (e: SecurityException) {
            // 通知の許可が無い。
        }
    }

    fun cancel(context: Context, callId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }
}
