import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/call/bgm/bgm_queue.dart';
import 'repository_providers.dart';

const _volumeKey = 'bgmVolume';
const _orderKey = 'bgmPlayOrder';

/// 通話のBGMの前回の状態（音量・再生順）。アカウントに保存し（`preferences.bgmVolume`・
/// `preferences.bgmPlayOrder`）、別の端末や次の通話でも引き継ぐ（2026-11-16）。
class BgmPreferences {
  const BgmPreferences({this.volume = 0.5, this.order = BgmPlayOrder.inOrder});

  /// スライダーの位置（0〜1）。
  final double volume;
  final BgmPlayOrder order;

  BgmPreferences copyWith({double? volume, BgmPlayOrder? order}) =>
      BgmPreferences(volume: volume ?? this.volume, order: order ?? this.order);
}

BgmPlayOrder? bgmPlayOrderFromName(String? name) {
  for (final o in BgmPlayOrder.values) {
    if (o.name == name) return o;
  }
  return null;
}

class BgmPreferencesNotifier extends Notifier<BgmPreferences> {
  @override
  BgmPreferences build() {
    _load();
    return const BgmPreferences();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      state = BgmPreferences(
        volume: (prefs.getDouble(_volumeKey) ?? 0.5).clamp(0.0, 1.0),
        order:
            bgmPlayOrderFromName(prefs.getString(_orderKey)) ??
            BgmPlayOrder.inOrder,
      );
    } catch (_) {
      // 読み込めない時は標準の値のまま（通話は止めない）。
    }
  }

  /// 通話中の変更を、端末とアカウントへ保存する。変更が無ければ何もしない。
  Future<void> save({double? volume, BgmPlayOrder? order}) async {
    final next = state.copyWith(volume: volume, order: order);
    final volumeChanged = next.volume != state.volume;
    final orderChanged = next.order != state.order;
    if (!volumeChanged && !orderChanged) return;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, next.volume);
    await prefs.setString(_orderKey, next.order.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    final repo = ref.read(userRepositoryProvider);
    try {
      if (volumeChanged) {
        await repo.updateUserPreference(userId, 'bgmVolume', next.volume);
      }
      if (orderChanged) {
        await repo.updateUserPreference(
          userId,
          'bgmPlayOrder',
          next.order.name,
        );
      }
    } catch (_) {
      // 保存に失敗しても、端末には残っている。通話は止めない。
    }
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote({double? volume, String? order}) async {
    final next = state.copyWith(
      volume: volume?.clamp(0.0, 1.0),
      order: bgmPlayOrderFromName(order),
    );
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, next.volume);
    await prefs.setString(_orderKey, next.order.name);
  }
}

final bgmPreferencesProvider =
    NotifierProvider<BgmPreferencesNotifier, BgmPreferences>(
      BgmPreferencesNotifier.new,
    );
