package jp.rhing.daidai

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.os.PowerManager
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
        // 新しいエンジンには通話が無い。前の画面（エンジン）が終わった後も前面サービスだけが
        // 残っていた場合（通話の終了を伝える相手が居なくなった時）に、ここで止める（2026-11-16）。
        callActive = false
        CallForegroundService.stop(applicationContext)
        // 通話中にアプリを離れた時、OS標準のピクチャーインピクチャーへ入る
        // （2026-10-12追加、lib/features/call/pip_controller.dart から呼ぶ）。
        // 画面共有の許可を得た直後（MediaProjectionを作る前）に、前面サービスへ`mediaProjection`型を
        // 足す（Android 14以降の必須条件。third_party/flutter_webrtcのパッチのフック）。
        com.cloudwebrtc.webrtc.GetUserMediaImpl.beforeScreenCapture = Runnable {
            CallForegroundService.setProjection(true)
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setCallActive") {
                callActive = call.argument<Boolean>("active") ?: false
                // 通話中は前面サービスで、アプリを離れても画面が消えてもOSに止められないようにする。
                // 通話が終わった時にサービスが残ると、「通話中」の通知と実行中のアプリの表示が
                // 消えない為、PiPの処理（例外になりうる）より先に、確実に止める（2026-11-16）。
                if (callActive) CallForegroundService.start(applicationContext)
                else CallForegroundService.stop(applicationContext)
                try {
                    updatePipParams()
                    // 通話が終わった時、既にPiPの小窓に入っていたら閉じる（残ると、終わった通話の
                    // 最後の映像がホーム画面の上に出たままになる）。
                    if (!callActive) dismissPipIfNoCall()
                } catch (e: Exception) {
                    // PiPの更新に失敗しても、通話の開始・終了の処理は済んでいる。
                }
                result.success(null)
            } else if (call.method == "setScreenShareActive") {
                // 画面共有の終了で、前面サービスの型から`mediaProjection`を外す（開始側は、
                // flutter_webrtcの許可直後のフックで行う）。
                if (call.argument<Boolean>("active") != true) CallForegroundService.setProjection(false)
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
            } else if (call.method == "isDeviceLocked") {
                // 画面がロックされているか（着信を全画面で出すかの判断に使う）。
                val keyguard = getSystemService(android.content.Context.KEYGUARD_SERVICE)
                    as android.app.KeyguardManager
                result.success(keyguard.isKeyguardLocked)
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
            // Android 12以降は、通話中にホームへ戻ると自動的に入る。最近のアプリ画面からの切り替えは
            // 自動では入らないため、onUserLeaveHintで手動で入る。
            builder.setAutoEnterEnabled(callActive)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        buildPipParams()?.let { setPictureInPictureParams(it) }
    }

    // 画面（アクティビティ）が無くなると、Flutterのエンジンも無くなり、通話（Dart側のWebRTC）は続けられない。
    // 通話の終了をサービスへ伝える相手が居なくなる為、ここで前面サービスを止める（2026-11-16）。
    override fun onDestroy() {
        callActive = false
        CallForegroundService.stop(applicationContext)
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8〜11は自動で入れないため、離れる時に手動で入る。Android 12以降も、自動入室は
        // 「ホームへ戻る」でしか働かず、最近のアプリ画面からの切り替えでは入らないため、手動で入る
        // （既に入っている・入りかけの時は何もしない）。
        if (callActive &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !isInPictureInPictureMode
        ) {
            buildPipParams()?.let { enterPictureInPictureMode(it) }
        }
    }

    // PiPの小窓を×で閉じると、アクティビティだけが止まり、Flutterのエンジンが外れる。その後も
    // 通話（映像の描画）が続くと、外れたエンジンへ描画を要求してアプリが落ちる
    // （"FlutterJNI is not attached to native"）。落ちると退出の処理も走らず、次の参加が不安定になる。
    // 画面の消灯でも止まるため、操作できる状態（点灯中）の時だけ「閉じられた」とみなして通話を終える。
    override fun onStop() {
        super.onStop()
        if (!callActive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val interactive = (getSystemService(POWER_SERVICE) as PowerManager).isInteractive
        if (isInPictureInPictureMode && interactive) {
            pipChannel?.invokeMethod("pipDismissed", null)
        }
    }

    /// 通話が無いのにPiPの小窓が出ている時に、小窓を閉じる（アプリは終了させない）。
    private fun dismissPipIfNoCall() {
        if (callActive) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isInPictureInPictureMode) moveTaskToBack(true)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
        // 通話が終わった直後に遅れてPiPへ入った場合の保険。
        if (isInPictureInPictureMode) dismissPipIfNoCall()
    }
}
