package jp.rhing.daidai

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 通話中、アプリを離れる・画面を消す・他のアプリの通知を見る間も、OSにマイク・カメラ・通信を
 * 止められないようにする前面サービス（2026-11-13）。常駐の「通話中」の通知を出すだけで、
 * 通話の処理自体はこれまでどおりDart側（WebRTC）が行う。開始・停止は
 * [MainActivity]の`setCallActive`から。
 */
class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    // 画面共有（MediaProjection）の間だけ、前面サービスの型に`mediaProjection`を足す。
    private var projection = false
    private var notification: android.app.Notification? = null

    /** 現在の型で`startForeground`を呼び直して、型を切り替える（サービスが動いている間だけ）。 */
    private fun applyForegroundType() {
        val n = notification ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                // カメラの許可が無いままカメラ型で起動すると、Android 14以降は例外になる。
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                if (projection) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                startForeground(NOTIFICATION_ID, n, type)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            // 前面サービスを始められなくても（型を切り替えられなくても）、通話自体は続ける。
            android.util.Log.w("DaiDaiCall", "startForeground failed (projection=$projection): $e")
            if (n === notification && !projection) stopSelf()
        }
    }

    // 画面が消えてもCPUとWi-Fiを止めさせない。前面サービスだけでは、端末がスリープに入ると
    // CPUが止まって音声の処理が途切れ、Wi-Fiも省電力になって送受信が不安定になる（2026-11-15）。
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "daidai:call").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "daidai:call").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (e: Exception) {
            // ロックを取れなくても通話自体は続ける。
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        releaseLocks()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(this)
        acquireLocks()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                // タップで、今の画面の上に通話画面を重ねて開く（`MainActivity`→Dartの`openCall`）。
                putExtra(CallNotifications.EXTRA_ACTION, CallNotifications.ACTION_OPEN_CALL)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        instance = this
        notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("DaiDai")
            .setContentText("通話中")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .build()
        applyForegroundType()
        // 開始の直後に、通話が終わって停止が先に届いていた場合（startForegroundServiceとstopServiceの
        // 競合）は、前面に出した後で、すぐに止める。そうしないと、通知が残り続ける（2026-11-16）。
        if (!wanted) {
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        /** 動いている間のサービス（画面共有の型の切り替えを、同期的に行うため）。 */
        @Volatile
        var instance: CallForegroundService? = null

        /** 通話中か（開始で立て、停止で下ろす）。開始の処理より先に停止が来た場合の判定に使う。 */
        @Volatile
        var wanted = false

        /** 画面共有の間だけ`mediaProjection`型にする／戻す。サービスが動いていなければ何もしない。 */
        fun setProjection(active: Boolean) {
            val service = instance
            if (service == null) {
                // 前面サービスが動いていない。この後のMediaProjectionの開始は失敗しうる。
                android.util.Log.w("DaiDaiCall", "setProjection($active): foreground service not running")
                return
            }
            service.projection = active
            service.applyForegroundType()
        }

        private const val CHANNEL_ID = "ongoing_call"
        private const val NOTIFICATION_ID = 7421

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "通話中",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        fun start(context: Context) {
            wanted = true
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, CallForegroundService::class.java),
                )
            } catch (e: Exception) {
                // バックグラウンドからの起動制限など。通話自体には影響させない。
            }
        }

        fun stop(context: Context) {
            wanted = false
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }
}
