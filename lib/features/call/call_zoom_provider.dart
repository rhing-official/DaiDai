import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_call_session.dart';

/// ウィンドウ1つの拡縮の状態（2026-11-17）。移動量は枠の大きさに対する比で持つ。ミニ表示から
/// 通話画面へ戻した時に、枠の大きさ・並びが変わっていても、その大きさに合わせて戻せる。
class CallZoomEntry {
  const CallZoomEntry({required this.scale, required this.relativeOffset});

  final double scale;
  final Offset relativeOffset;

  /// 枠[size]での移動量。
  Offset offsetFor(Size size) =>
      Offset(relativeOffset.dx * size.width, relativeOffset.dy * size.height);

  static CallZoomEntry of(double scale, Offset offset, Size size) =>
      CallZoomEntry(
        scale: scale,
        relativeOffset: size.isEmpty
            ? Offset.zero
            : Offset(offset.dx / size.width, offset.dy / size.height),
      );
}

/// 通話画面のウィンドウごとの拡縮を、通話が続く間だけ持つ（キーは`CallTileSpec.key`）。
/// ミニ表示にして通話画面を閉じても、戻した時に拡縮が残る。通話が終わる・別の通話に
/// 変わると空になる。
class CallZoomNotifier extends Notifier<Map<String, CallZoomEntry>> {
  @override
  Map<String, CallZoomEntry> build() {
    ref.watch(activeCallSessionProvider.select((s) => s?.controllerListenable));
    return const {};
  }

  void put(String key, CallZoomEntry? entry) {
    final next = {...state};
    if (entry == null || entry.scale <= 1.0) {
      if (next.remove(key) == null) return;
    } else {
      next[key] = entry;
    }
    state = next;
  }

  /// [valid]に無いキー（共有の終了・退出で無くなったウィンドウ）を捨てる。
  void retain(Set<String> valid) {
    final next = {
      for (final e in state.entries)
        if (valid.contains(e.key)) e.key: e.value,
    };
    if (next.length != state.length) state = next;
  }
}

final callZoomProvider =
    NotifierProvider<CallZoomNotifier, Map<String, CallZoomEntry>>(
      CallZoomNotifier.new,
    );
