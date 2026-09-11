package jp.rhing.daidai

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
