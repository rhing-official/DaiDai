package jp.rhing.daidai

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 通知音のカスタムアップロード音源をNotificationManagerへ渡すための
 * content:// URI発行のみを担う最小限のネイティブコード（2026-09-06追加、
 * lib/utils/android_notification_sound_sync.dart から呼ぶ）。
 * FileProviderは他のFlutterプラグイン経由では発行できないため、
 * この1メソッドだけをMethodChannelで公開する。
 *
 * FlutterFragmentActivity（2026-09-11変更、以前はFlutterActivity）を継承する。
 * パスコードロック機能のlocal_authパッケージがAndroidのBiometricPromptを
 * 使うにはFragmentActivityが必須のため。
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "jp.rhing.daidai/notification_sound"
    private val pipChannelName = "jp.rhing.daidai/pip"
    private var pipChannel: MethodChannel? = null
    private var callActive = false
    private val callActionChannelName = "jp.rhing.daidai/call_action"
    private var callActionChannel: MethodChannel? = null

    /** 着信通知の「応答」で開かれた時の、Dart側がまだ受け取っていない操作。 */
    private var pendingCallAction: Map<String, String?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleCallIntent(intent, deliver = false)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCallIntent(intent, deliver = true)
    }

    /**
     * 着信通知から開かれた時の処理（2026-11-12）。ロック画面の上に表示し、「応答」なら通知を
     * 消してDart側へ渡す。全画面（ロック画面の着信）で開かれた場合は、アプリ内のバナーで
     * 応答・拒否してもらうため、表示だけする。
     */
    private fun handleCallIntent(intent: android.content.Intent?, deliver: Boolean) {
        if (intent == null) return
        val ring = intent.getBooleanExtra(CallNotifications.EXTRA_RING, false)
        val action = intent.getStringExtra(CallNotifications.EXTRA_ACTION)
        if (!ring && action == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        if (action != CallNotifications.ACTION_ANSWER) return
        val callId = intent.getStringExtra(CallNotifications.EXTRA_CALL_ID) ?: return
        CallNotifications.cancel(this, callId)
        val map = mapOf(
            "kind" to intent.getStringExtra(CallNotifications.EXTRA_KIND),
            "callId" to callId,
            "groupId" to intent.getStringExtra(CallNotifications.EXTRA_GROUP_ID),
        )
        // 同じIntentで再作成されても二重に処理しない。
        intent.removeExtra(CallNotifications.EXTRA_ACTION)
        if (deliver && callActionChannel != null) {
            callActionChannel?.invokeMethod("answer", map)
        } else {
            pendingCallAction = map
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 通話中にアプリを離れた時、OS標準のピクチャーインピクチャーへ入る
        // （2026-10-12追加、lib/features/call/pip_controller.dart から呼ぶ）。
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setCallActive") {
                callActive = call.argument<Boolean>("active") ?: false
                updatePipParams()
                // 通話中は前面サービスで、アプリを離れても画面が消えてもOSに止められないようにする。
                if (callActive) CallForegroundService.start(applicationContext)
                else CallForegroundService.stop(applicationContext)
                result.success(null)
            } else if (call.method == "setKeepScreenOn") {
                // 映像通話中に、OSの自動消灯で通話が止まらないようにする。
                val keep = call.argument<Boolean>("keep") ?: false
                if (keep) {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        callActionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callActionChannelName)
        callActionChannel?.setMethodCallHandler { call, result ->
            if (call.method == "takePendingAction") {
                result.success(pendingCallAction)
                pendingCallAction = null
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getContentUri") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_argument", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "$packageName.fileprovider",
                            File(path),
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("file_provider_error", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun buildPipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12以降は、通話中にホームへ戻る・他のアプリへ切り替えるだけで自動的に入る。
            builder.setAutoEnterEnabled(callActive)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        buildPipParams()?.let { setPictureInPictureParams(it) }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8〜11は自動で入れないため、ホームボタン等で離れる時に手動で入る。
        if (callActive &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            buildPipParams()?.let { enterPictureInPictureMode(it) }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
