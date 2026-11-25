package jp.rhing.daidai

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Rational
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
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

    /** 設定と映像の有無から、Dart側が決めた「OS標準のPiPへ入ってよいか」（2026-11-18）。 */
    private var pipAllowed = true
    private var recordingCallback: AudioManager.AudioRecordingCallback? = null
    private var lastMicSilenced = false
    private val callActionChannelName = "jp.rhing.daidai/call_action"
    private var callActionChannel: MethodChannel? = null

    /** 着信通知の「応答」で開かれた時の、Dart側がまだ受け取っていない操作。 */
    private var pendingCallAction: Map<String, String?>? = null

    /** 着信の全画面インテントで開かれた時の、Dart側がまだ受け取っていない着信の情報。 */
    private var pendingRingLaunch: Map<String, Any?>? = null

    /**
     * 着信・応答の操作でロック画面の上に表示している間はtrue（2026-11-18）。通話・着信が終わったら
     * [releaseOverLock]で外し、端末の認証を求める。
     */
    private var shownOverLock = false

    /**
     * 「ロック画面の上に表示する」設定（`setShowWhenLocked`・`setTurnScreenOn`）を、オンにしたままか
     * （2026-11-26）。ロックされていない時に着信・応答で開いた場合も、オンにする。外さないと、通話の後で
     * 端末をロックして画面を点けた時に、語らい一覧がロック画面の上に出てしまう。
     */
    private var showWhenLockedOn = false

    /**
     * ロック画面の上の通話中は、戻る操作でアプリの他の画面へ移る前に、端末の認証（生体認証など）を
     * 求める（Dartが切り替える）。認証に成功したら、Dartへ知らせて通常の戻る操作をさせる。
     */
    private val lockedCallBackBlocker = object : androidx.activity.OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {
            requestUnlock { unlocked ->
                if (unlocked) callActionChannel?.invokeMethod("lockedBackUnlocked", null)
            }
        }
    }

    /**
     * OS標準の端末の認証画面（生体認証・PIN・パターン）を出す。成功したら[onResult]にtrue、
     * キャンセル・失敗はfalse。画面ロックを使っていない端末はそのままtrue（ロック中ではない）。
     */
    private fun requestUnlock(onResult: (Boolean) -> Unit) {
        val keyguard = getSystemService(android.content.Context.KEYGUARD_SERVICE)
            as android.app.KeyguardManager
        if (!keyguard.isKeyguardLocked) {
            onResult(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            onResult(false)
            return
        }
        keyguard.requestDismissKeyguard(
            this,
            object : android.app.KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = onResult(true)
                override fun onDismissCancelled() = onResult(false)
                override fun onDismissError() = onResult(false)
            },
        )
    }

    private fun isKeyguardLocked(): Boolean {
        val keyguard = getSystemService(android.content.Context.KEYGUARD_SERVICE)
            as android.app.KeyguardManager
        return keyguard.isKeyguardLocked
    }

    /**
     * ロック画面の上の表示をやめる。端末がまだロック中なら、ロック画面（認証）が前面に戻り、
     * 認証するまでアプリは操作できない。ユーザーが自分で解除済みなら何もしない。
     */
    private fun releaseOverLock() {
        lockedCallBackBlocker.isEnabled = false
        shownOverLock = false
        // ロックされていなかった時に開いた場合も、設定は必ず外す（外さないと、後でロックした時に
        // ロック画面の上にアプリが出る）。
        if (!showWhenLockedOn) return
        showWhenLockedOn = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(this, lockedCallBackBlocker)
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
        // 通話中の通知のタップ: 今の画面に重ねて通話画面を開く（2026-11-18）。画面は変えず、
        // ロック画面の上に出す設定もしない。起動直後（まだ通話が無い）は何もしない。
        if (action == CallNotifications.ACTION_OPEN_CALL) {
            intent.removeExtra(CallNotifications.EXTRA_ACTION)
            if (deliver) callActionChannel?.invokeMethod("openCall", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            showWhenLockedOn = true
        }
        // ロック中に開かれた時だけ、終了後に認証を求める対象にする。
        if (isKeyguardLocked()) shownOverLock = true
        if (ring) {
            // 全画面の応答/拒否を、Firestoreの検知を待たずに出すための情報（2026-11-18）。
            val callId = intent.getStringExtra(CallNotifications.EXTRA_CALL_ID)
            if (callId != null) {
                val ringMap = mapOf<String, Any?>(
                    "kind" to intent.getStringExtra(CallNotifications.EXTRA_KIND),
                    "callId" to callId,
                    "groupId" to intent.getStringExtra(CallNotifications.EXTRA_GROUP_ID),
                    "callerName" to intent.getStringExtra(CallNotifications.EXTRA_CALLER_NAME),
                    "iconUrl" to intent.getStringExtra(CallNotifications.EXTRA_ICON_URL),
                    "isVideo" to intent.getBooleanExtra(CallNotifications.EXTRA_IS_VIDEO, false),
                    "recipientId" to intent.getStringExtra(CallNotifications.EXTRA_RECIPIENT_ID),
                )
                intent.removeExtra(CallNotifications.EXTRA_RING)
                if (deliver && callActionChannel != null) {
                    callActionChannel?.invokeMethod("ringLaunch", ringMap)
                } else {
                    pendingRingLaunch = ringMap
                }
            }
        }
        if (action != CallNotifications.ACTION_ANSWER) return
        val callId = intent.getStringExtra(CallNotifications.EXTRA_CALL_ID) ?: return
        CallNotifications.cancel(this, callId)
        val map = mapOf(
            "kind" to intent.getStringExtra(CallNotifications.EXTRA_KIND),
            "callId" to callId,
            "groupId" to intent.getStringExtra(CallNotifications.EXTRA_GROUP_ID),
            "recipientId" to intent.getStringExtra(CallNotifications.EXTRA_RECIPIENT_ID),
        )
        // 同じIntentで再作成されても二重に処理しない。
        intent.removeExtra(CallNotifications.EXTRA_ACTION)
        if (deliver && callActionChannel != null) {
            callActionChannel?.invokeMethod("answer", map)
        } else {
            pendingCallAction = map
        }
    }

    /**
     * ソフトキーボードの開閉の途中の高さ（dp）を、毎フレームDartへ送る（2026-11-21）。
     * FlutterのviewInsetsは、この端末（Android 16）では動きが終わった後に1回だけ最終値で届き、
     * メッセージ一覧・入力欄がキーボードより遅れて動いていた（lib/utils/ime_progress.dart）。
     */
    private fun setUpImeProgress(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.rhing.daidai/ime")
        val imeType = WindowInsetsCompat.Type.ime()
        ViewCompat.setWindowInsetsAnimationCallback(
            window.decorView,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: List<WindowInsetsAnimationCompat>,
                ): WindowInsetsCompat {
                    if (runningAnimations.any { it.typeMask and imeType != 0 }) {
                        val px = insets.getInsets(imeType).bottom
                        channel.invokeMethod("progress", px / resources.displayMetrics.density.toDouble())
                    }
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and imeType != 0) channel.invokeMethod("end", null)
                }
            },
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setUpImeProgress(flutterEngine)
        // 変換中の文字の、キーボードが付けた背景色（カーソルの位置の表示）をFlutterへ送る（2026-11-26）。
        val imeSpanChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.rhing.daidai/ime_spans")
        val imeSpanBridge = ImeSpanBridge(this, imeSpanChannel)
        imeSpanChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> imeSpanBridge.start()
                "stop" -> imeSpanBridge.stop()
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(null)
        }
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
        // 共有していたアプリを閉じる・システムの「共有を停止」などで画面共有の元が終わった時、
        // Dart側にも共有を終えさせる（2026-11-16）。
        com.cloudwebrtc.webrtc.GetUserMediaImpl.onScreenCaptureStopped = Runnable {
            runOnUiThread { pipChannel?.invokeMethod("screenShareStopped", null) }
        }
        pipChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setCallActive") {
                callActive = call.argument<Boolean>("active") ?: false
                // 通話中は前面サービスで、アプリを離れても画面が消えてもOSに止められないようにする。
                // 通話が終わった時にサービスが残ると、「通話中」の通知と実行中のアプリの表示が
                // 消えない為、PiPの処理（例外になりうる）より先に、確実に止める（2026-11-16）。
                if (callActive) CallForegroundService.start(applicationContext)
                else CallForegroundService.stop(applicationContext)
                // 通話中だけ、自分のマイクが他のアプリに奪われて無音にされていないか監視する。
                if (callActive) registerMicCallback() else unregisterMicCallback()
                try {
                    updatePipParams()
                    // 通話が終わった時、既にPiPの小窓に入っていたら閉じる（残ると、終わった通話の
                    // 最後の映像がホーム画面の上に出たままになる）。
                    if (!callActive) dismissPipIfNoCall()
                } catch (e: Exception) {
                    // PiPの更新に失敗しても、通話の開始・終了の処理は済んでいる。
                }
                result.success(null)
            } else if (call.method == "isMicBusy") {
                // 今、他のアプリがマイクを使っているか（通話に入る前の注意用。Android 7以降）。
                var busy = false
                try {
                    val am = getSystemService(AUDIO_SERVICE) as AudioManager
                    busy = am.activeRecordingConfigurations.isNotEmpty()
                } catch (e: Exception) {
                    busy = false
                }
                result.success(busy)
            } else if (call.method == "setPipAllowed") {
                pipAllowed = call.argument<Boolean>("allowed") ?: true
                try {
                    updatePipParams()
                } catch (e: Exception) {
                    // 更新に失敗しても、次に離れる時の判定（pipAllowed）は効く。
                }
                result.success(null)
            } else if (call.method == "enterPip") {
                // 通話画面の戻るボタンで、OS標準のPiPに入る（2026-11-16）。入れたかを返す。
                var entered = false
                if (callActive && pipAllowed &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !isInPictureInPictureMode
                ) {
                    try {
                        buildPipParams()?.let { entered = enterPictureInPictureMode(it) }
                    } catch (e: Exception) {
                        entered = false
                    }
                }
                result.success(entered)
            } else if (call.method == "setScreenShareActive") {
                // 画面共有の終了で、前面サービスの型から`mediaProjection`を外す（開始側は、
                // flutter_webrtcの許可直後のフックで行う）。
                if (call.argument<Boolean>("active") != true) CallForegroundService.setProjection(false)
                result.success(null)
            } else if (call.method == "setScreenAudio") {
                // 画面共有の最中に、端末の再生音（動画・ゲームなど）を、マイクの音声へ混ぜて送る／止める
                // （Android 10以降。third_party/flutter_webrtcの`ScreenAudioMixer`）。
                val active = call.argument<Boolean>("active") ?: false
                result.success(com.cloudwebrtc.webrtc.ScreenAudioMixer.setWanted(active))
            } else if (call.method == "setScreenAudioMicMuted") {
                com.cloudwebrtc.webrtc.ScreenAudioMixer.setMicMuted(call.argument<Boolean>("muted") ?: false)
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
            } else if (call.method == "takePendingRing") {
                result.success(pendingRingLaunch)
                pendingRingLaunch = null
            } else if (call.method == "releaseOverLock") {
                releaseOverLock()
                result.success(null)
            } else if (call.method == "requestUnlock") {
                requestUnlock { unlocked -> result.success(unlocked) }
            } else if (call.method == "setLockedCallMode") {
                lockedCallBackBlocker.isEnabled = call.argument<Boolean>("on") ?: false
                result.success(null)
            } else if (call.method == "isDndActive") {
                // 端末のおやすみモードが今オンか（アプリ内の着信音を止める判断に使う、2026-11-25）。
                result.success(CallNotifications.isDndActive(this))
            } else if (call.method == "hasDndAccess") {
                // 端末の「おやすみモードの許可」を持っているか（緊急の着信の貫通に要る、2026-11-25）。
                result.success(CallNotifications.hasPolicyAccess(this))
            } else if (call.method == "openDndAccessSettings") {
                // 端末の「おやすみモードの許可」の設定画面を開く。
                startActivity(
                    android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
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
            builder.setAutoEnterEnabled(callActive && pipAllowed)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        buildPipParams()?.let { setPictureInPictureParams(it) }
    }

    // 画面（アクティビティ）が無くなると、Flutterのエンジンも無くなり、通話（Dart側のWebRTC）は続けられない。
    // 通話の終了をサービスへ伝える相手が居なくなる為、ここで前面サービスを止める（2026-11-16）。
    /**
     * 自分の録音（詳細が見える設定＝他のアプリの匿名化された設定ではない）が、OSに無音にされたかを
     * Dartへ伝える（`micSilenced`）。他のアプリが通話でマイクを使っている間などに起きる（Android 10以降）。
     */
    private fun registerMicCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || recordingCallback != null) return
        try {
            val am = getSystemService(AUDIO_SERVICE) as AudioManager
            val cb = object : AudioManager.AudioRecordingCallback() {
                override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
                    val silenced = configs.any { it.clientAudioSource >= 0 && it.isClientSilenced }
                    if (silenced != lastMicSilenced) {
                        lastMicSilenced = silenced
                        pipChannel?.invokeMethod("micSilenced", silenced)
                    }
                }
            }
            am.registerAudioRecordingCallback(cb, Handler(Looper.getMainLooper()))
            recordingCallback = cb
        } catch (e: Exception) {
            recordingCallback = null
        }
    }

    private fun unregisterMicCallback() {
        val cb = recordingCallback ?: return
        try {
            (getSystemService(AUDIO_SERVICE) as AudioManager).unregisterAudioRecordingCallback(cb)
        } catch (e: Exception) {
        }
        recordingCallback = null
        if (lastMicSilenced) {
            lastMicSilenced = false
            pipChannel?.invokeMethod("micSilenced", false)
        }
    }

    override fun onDestroy() {
        unregisterMicCallback()
        callActive = false
        CallForegroundService.stop(applicationContext)
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8〜11は自動で入れないため、離れる時に手動で入る。Android 12以降も、自動入室は
        // 「ホームへ戻る」でしか働かず、最近のアプリ画面からの切り替えでは入らないため、手動で入る
        // （既に入っている・入りかけの時は何もしない）。
        if (callActive && pipAllowed &&
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
        // 通話が無いのに、ロック画面の上に表示する設定が残っていたら外す（2026-11-26）。Dartからの
        // 解除（`releaseOverLock`）が届かなかった場合の保険。
        if (!callActive && showWhenLockedOn) releaseOverLock()
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
