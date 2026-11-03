import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';

import 'bgm/call_bgm.dart';
import 'bgm/call_bgm_sheet.dart';
import 'call_controls.dart';

/// 通話中のコントロールボタン列（マイク・スピーカー・音声⇔ビデオ切替・
/// カメラ前後切替・通話終了）。1対1（`CallScreen`）・広場（`GroupCallScreen`）
/// 両方で共有する（2026-08-19新設。それまでは両画面がほぼ同じボタン列を
/// 個別に実装しており、見た目の再設計のたびに二重にメンテナンスする必要が
/// あった）。1対1・広場のコントローラー（`WebrtcCallController`/
/// `WebrtcGroupCallController`）に共通の基底クラスは無いため、コントローラー
/// を直接受け取らず、必要な値・コールバックだけをまとめて渡す。
class CallControlBar extends ConsumerWidget {
  const CallControlBar({
    required this.isGekiga,
    required this.isGlass,
    required this.enabled,
    required this.muted,
    required this.onToggleMute,
    required this.speakerOn,
    required this.onToggleSpeaker,
    required this.showSpeakerToggle,
    required this.switchingCallType,
    required this.onToggleVideoType,
    required this.isVideo,
    required this.hasMultipleCameras,
    required this.switchingCamera,
    required this.onSwitchCamera,
    required this.onHangUp,
    this.bgmBinding,
    this.videoFailed = false,
    super.key,
  });

  final bool isGekiga;
  final bool isGlass;

  /// 通話が接続済み（active）かどうか。マイク・スピーカー・切替系ボタンは
  /// このフラグでのみ有効/無効を切り替える（通話終了ボタンは常に有効）。
  final bool enabled;

  final bool muted;
  final VoidCallback onToggleMute;

  /// スピーカー（受話口との切替）のボタンは、モバイルで、Bluetoothや有線の
  /// ヘッドセットに接続していない時だけ出す（[showSpeakerToggle]、2026-11-01。
  /// 接続中は端末のOSが出力先を自動で切り替える）。
  final bool speakerOn;
  final VoidCallback onToggleSpeaker;
  final bool showSpeakerToggle;

  final bool switchingCallType;

  /// nullなら音声⇔ビデオ切替ボタン自体を表示しない（カメラが1台も無い
  /// 端末での発信者側想定、`cameraAvailabilityProvider`参照）。
  final VoidCallback? onToggleVideoType;

  final bool isVideo;

  /// フロント/バックカメラ等、映像入力デバイスを2台以上持つ端末かどうか。
  /// falseならカメラ前後切替ボタン自体を表示しない。
  final bool hasMultipleCameras;
  final bool switchingCamera;
  final VoidCallback onSwitchCamera;

  final VoidCallback onHangUp;

  /// 通話のBGM（2026-11-03、Webのみ）。nullなら、BGMを流す権限が無い（Web以外は
  /// ボタンの枠も出さない）。権限が無くても枠は残し、他のボタンの位置を動かさない。
  final CallBgmBinding? bgmBinding;

  /// 映像をオンにできなかった直後（注意書きを出す、2026-11-03）。
  final bool videoFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ボタンの数が変わると`spaceEvenly`が全ボタンの位置を再配分してしまい、
    // 音声⇔ビデオ切替のたびに他のボタン（マイク・通話終了等）の座標まで
    // ずれて見える不具合があった（2026-08-19判明）。表示しないボタンも
    // 常に同じ順序でRowに含め、[_maybeHidden]で見た目とヒットテストだけを
    // 消す（同じ大きさの空きスロットとして扱う）ことで、各ボタンの位置を
    // 常に固定する。加えて、Row自体を幅固定のコンテナで包む（PC埋め込み
    // ペイン・全画面モバイルなど置かれる場所によってコンテナの幅が違っても
    // 常に同じ大きさで描画されるようにするため、2026-08-19追加）。
    final maxWidth = CallBgm.isSupported ? 420.0 : 360.0;
    final bar = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // 狭い画面（BGMのボタンを含めて幅が足りない時）は、全体を縮めて収める
        // （ボタンの並びと位置は変えない）。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: maxWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallRoundButton(
                  icon: muted ? Icons.mic_off : Icons.mic,
                  color: Colors.grey[700]!,
                  isGekiga: isGekiga,
                  isGlass: isGlass,
                  onPressed: enabled ? onToggleMute : null,
                ),
                _maybeHidden(
                  visible: showSpeakerToggle,
                  child: CallRoundButton(
                    icon: speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                    color: Colors.grey[700]!,
                    isGekiga: isGekiga,
                    isGlass: isGlass,
                    onPressed: enabled ? onToggleSpeaker : null,
                  ),
                ),
                _maybeHidden(
                  visible: onToggleVideoType != null,
                  child: CallRoundButton(
                    icon: isVideo ? Icons.videocam : Icons.videocam_off,
                    color: Colors.grey[700]!,
                    isGekiga: isGekiga,
                    isGlass: isGlass,
                    onPressed: enabled && !switchingCallType
                        ? onToggleVideoType
                        : null,
                  ),
                ),
                _maybeHidden(
                  visible: isVideo && hasMultipleCameras,
                  child: CallRoundButton(
                    icon: Icons.cameraswitch,
                    color: Colors.grey[700]!,
                    isGekiga: isGekiga,
                    isGlass: isGlass,
                    onPressed: enabled && !switchingCamera
                        ? onSwitchCamera
                        : null,
                  ),
                ),
                if (CallBgm.isSupported)
                  _maybeHidden(
                    visible: bgmBinding != null,
                    child: CallRoundButton(
                      icon: bgmBinding?.bgm.playing ?? false
                          ? Icons.music_note
                          : Icons.music_note_outlined,
                      color: Colors.grey[700]!,
                      isGekiga: isGekiga,
                      isGlass: isGlass,
                      onPressed: enabled && bgmBinding != null
                          ? () => showCallBgmSheet(context, bgmBinding!)
                          : null,
                    ),
                  ),
                CallRoundButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  isGekiga: isGekiga,
                  isGlass: isGlass,
                  onPressed: onHangUp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!videoFailed) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            ref.watch(appStringsProvider).callVideoFailed,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
          ),
        ),
        bar,
      ],
    );
  }

  /// [visible]がfalseの間も[child]と同じ大きさのスロットを保ったまま、
  /// 見た目とタップ判定だけを消す（build参照）。
  Widget _maybeHidden({required bool visible, required Widget child}) {
    if (visible) return child;
    return IgnorePointer(child: Opacity(opacity: 0, child: child));
  }
}
