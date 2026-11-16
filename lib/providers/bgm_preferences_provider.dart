import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/call/bgm/bgm_queue.dart';
import 'repository_providers.dart';

const _volumeKey = 'bgmVolume';
const _orderKey = 'bgmPlayOrder';
const _tabKey = 'bgmTab';
const _albumKey = 'bgmAlbumId';
const _lastTrackKey = 'bgmLastTrackId';
const _lastPositionKey = 'bgmLastPositionMs';
const _lastQueueAlbumKey = 'bgmLastQueueAlbumId';
const _lastQueueFavoritesKey = 'bgmLastQueueFavorites';

/// 最後に再生していた曲（2026-11-16）。曲・アルバムのidは、その端末のIndexedDBで採番した値で、
/// 別の端末には無い為、**端末にだけ保存し、アカウントへは書かない**（曲名も保存しない）。
class BgmLastPlayed {
  const BgmLastPlayed({
    required this.trackId,
    required this.positionMs,
    this.queueAlbumId,
    this.queueFavorites = false,
  });

  final String trackId;
  final int positionMs;

  /// どこから流していたか（アルバムのid、nullはすべての曲）。次に流す曲の範囲になる。
  final String? queueAlbumId;
  final bool queueFavorites;

  @override
  bool operator ==(Object other) =>
      other is BgmLastPlayed &&
      other.trackId == trackId &&
      other.positionMs == positionMs &&
      other.queueAlbumId == queueAlbumId &&
      other.queueFavorites == queueFavorites;

  @override
  int get hashCode =>
      Object.hash(trackId, positionMs, queueAlbumId, queueFavorites);
}

/// 通話のBGMの前回の状態。
/// - 音量・再生順・タブ: アカウントに保存し（`preferences.bgmVolume`・`bgmPlayOrder`・`bgmTab`）、
///   別の端末や次の通話でも引き継ぐ。
/// - 選んでいたアルバム・最後に再生した曲: 端末にだけ保存する（idが端末固有の為）。
class BgmPreferences {
  const BgmPreferences({
    this.volume = 0.5,
    this.order = BgmPlayOrder.inOrder,
    this.tab = 0,
    this.albumId,
    this.lastPlayed,
  });

  /// スライダーの位置（0〜1）。
  final double volume;
  final BgmPlayOrder order;

  /// シートで最後に開いていたタブ（0: アーティスト別、1: アルバム、2: お気に入り）。
  final int tab;

  /// シートで最後に選んでいたアルバム（端末のみ。nullはすべての曲）。
  final String? albumId;
  final BgmLastPlayed? lastPlayed;

  BgmPreferences copyWith({
    double? volume,
    BgmPlayOrder? order,
    int? tab,
    String? albumId,
    bool clearAlbumId = false,
    BgmLastPlayed? lastPlayed,
    bool clearLastPlayed = false,
  }) => BgmPreferences(
    volume: volume ?? this.volume,
    order: order ?? this.order,
    tab: tab ?? this.tab,
    albumId: clearAlbumId ? null : (albumId ?? this.albumId),
    lastPlayed: clearLastPlayed ? null : (lastPlayed ?? this.lastPlayed),
  );
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
      final trackId = prefs.getString(_lastTrackKey);
      state = BgmPreferences(
        volume: (prefs.getDouble(_volumeKey) ?? 0.5).clamp(0.0, 1.0),
        order:
            bgmPlayOrderFromName(prefs.getString(_orderKey)) ??
            BgmPlayOrder.inOrder,
        tab: (prefs.getInt(_tabKey) ?? 0).clamp(0, 2),
        albumId: prefs.getString(_albumKey),
        lastPlayed: trackId == null
            ? null
            : BgmLastPlayed(
                trackId: trackId,
                positionMs: prefs.getInt(_lastPositionKey) ?? 0,
                queueAlbumId: prefs.getString(_lastQueueAlbumKey),
                queueFavorites: prefs.getBool(_lastQueueFavoritesKey) ?? false,
              ),
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
    await _writeRemote({
      if (volumeChanged) 'bgmVolume': next.volume,
      if (orderChanged) 'bgmPlayOrder': next.order.name,
    });
  }

  /// シートのタブを、端末とアカウントへ保存する。
  Future<void> saveTab(int tab) async {
    final value = tab.clamp(0, 2);
    if (value == state.tab) return;
    state = state.copyWith(tab: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tabKey, value);
    await _writeRemote({'bgmTab': value});
  }

  /// 選んでいるアルバムを、端末にだけ保存する（idは端末固有）。
  Future<void> saveAlbumId(String? albumId) async {
    if (albumId == state.albumId) return;
    state = albumId == null
        ? state.copyWith(clearAlbumId: true)
        : state.copyWith(albumId: albumId);
    final prefs = await SharedPreferences.getInstance();
    if (albumId == null) {
      await prefs.remove(_albumKey);
    } else {
      await prefs.setString(_albumKey, albumId);
    }
  }

  /// 最後に再生していた曲と位置を、端末にだけ保存する。nullなら消す。
  Future<void> saveLastPlayed(BgmLastPlayed? value) async {
    if (value == state.lastPlayed) return;
    state = value == null
        ? state.copyWith(clearLastPlayed: true)
        : state.copyWith(lastPlayed: value);
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_lastTrackKey);
      await prefs.remove(_lastPositionKey);
      await prefs.remove(_lastQueueAlbumKey);
      await prefs.remove(_lastQueueFavoritesKey);
      return;
    }
    await prefs.setString(_lastTrackKey, value.trackId);
    await prefs.setInt(_lastPositionKey, value.positionMs);
    if (value.queueAlbumId == null) {
      await prefs.remove(_lastQueueAlbumKey);
    } else {
      await prefs.setString(_lastQueueAlbumKey, value.queueAlbumId!);
    }
    await prefs.setBool(_lastQueueFavoritesKey, value.queueFavorites);
  }

  Future<void> _writeRemote(Map<String, Object?> fields) async {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    final repo = ref.read(userRepositoryProvider);
    try {
      for (final entry in fields.entries) {
        await repo.updateUserPreference(userId, entry.key, entry.value);
      }
    } catch (_) {
      // 保存に失敗しても、端末には残っている。通話は止めない。
    }
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote({double? volume, String? order, int? tab}) async {
    final next = state.copyWith(
      volume: volume?.clamp(0.0, 1.0),
      order: bgmPlayOrderFromName(order),
      tab: tab?.clamp(0, 2),
    );
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, next.volume);
    await prefs.setString(_orderKey, next.order.name);
    await prefs.setInt(_tabKey, next.tab);
  }
}

final bgmPreferencesProvider =
    NotifierProvider<BgmPreferencesNotifier, BgmPreferences>(
      BgmPreferencesNotifier.new,
    );
