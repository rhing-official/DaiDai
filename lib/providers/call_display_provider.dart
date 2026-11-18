import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_info.dart';

/// 通話画面を出た後（DaiDaiの別の画面へ行った時）の、アプリ内のミニ表示（2026-11-18、端末ごと）。
/// 端末のみに保存し、Firestoreへは同期しない（端末の大きさ・使い方で好みが分かれるため）。
enum CallMiniStyle {
  /// 映像（無ければアイコン）と操作ボタンの付いた小窓。
  video,

  /// 「通話中」と時間だけの細いチップ。タップで通話画面へ戻る。
  bar,

  /// 何も出さない。戻るには、通話中の寄合の標をタップする（モバイルは通知からも戻れる）。
  none;

  static CallMiniStyle? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// 既定。コンピューターは映像つき、モバイルは領域を取らない細いチップ。
  static CallMiniStyle get platformDefault =>
      isMobileCallPlatform ? CallMiniStyle.bar : CallMiniStyle.video;
}

/// アプリを離れた時のOS標準のピクチャーインピクチャー（Androidのみ、2026-11-18、端末ごと）。
enum CallPipPolicy {
  /// 映像か画面共有がある時だけ出す（音声だけの通話では出さない）。
  video,
  always,
  never;

  static CallPipPolicy fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return CallPipPolicy.video;
  }
}

const _miniStylePrefsKey = 'callMiniStyle';
const _pipPolicyPrefsKey = 'callPipPolicy';

final initialCallMiniStyleProvider = Provider<CallMiniStyle>(
  (ref) => CallMiniStyle.platformDefault,
);
final initialCallPipPolicyProvider = Provider<CallPipPolicy>(
  (ref) => CallPipPolicy.video,
);

Future<CallMiniStyle> loadInitialCallMiniStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return CallMiniStyle.fromName(prefs.getString(_miniStylePrefsKey)) ??
      CallMiniStyle.platformDefault;
}

Future<CallPipPolicy> loadInitialCallPipPolicy() async {
  final prefs = await SharedPreferences.getInstance();
  return CallPipPolicy.fromName(prefs.getString(_pipPolicyPrefsKey));
}

class CallMiniStyleNotifier extends Notifier<CallMiniStyle> {
  @override
  CallMiniStyle build() => ref.watch(initialCallMiniStyleProvider);

  Future<void> set(CallMiniStyle value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_miniStylePrefsKey, value.name);
  }
}

class CallPipPolicyNotifier extends Notifier<CallPipPolicy> {
  @override
  CallPipPolicy build() => ref.watch(initialCallPipPolicyProvider);

  Future<void> set(CallPipPolicy value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pipPolicyPrefsKey, value.name);
  }
}

final callMiniStyleProvider =
    NotifierProvider<CallMiniStyleNotifier, CallMiniStyle>(
      CallMiniStyleNotifier.new,
    );

final callPipPolicyProvider =
    NotifierProvider<CallPipPolicyNotifier, CallPipPolicy>(
      CallPipPolicyNotifier.new,
    );

/// 今この瞬間にOS標準のPiPへ入ってよいか（方針＋映像の有無）。
bool callPipAllowed(CallPipPolicy policy, {required bool hasVideo}) =>
    switch (policy) {
      CallPipPolicy.always => true,
      CallPipPolicy.video => hasVideo,
      CallPipPolicy.never => false,
    };
