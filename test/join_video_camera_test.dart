import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/models/app_user_preferences.dart';
import 'package:daidai/providers/join_video_camera_on_provider.dart';

void main() {
  test('未設定の標準はオン、保存値があればそれに従う', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadInitialJoinVideoCameraOn(), isTrue);
    SharedPreferences.setMockInitialValues({'joinVideoCameraOn': false});
    expect(await loadInitialJoinVideoCameraOn(), isFalse);
  });

  test('ログイン時の同期で端末側の値が更新される', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(joinVideoCameraOnProvider), isTrue);
    await container
        .read(joinVideoCameraOnProvider.notifier)
        .syncFromRemote(false);
    expect(container.read(joinVideoCameraOnProvider), isFalse);
    expect(await loadInitialJoinVideoCameraOn(), isFalse);
  });

  test('preferencesの保存と復元（未設定はnullのまま）', () {
    expect(
      const AppUserPreferences().toJson().containsKey('joinVideoCameraOn'),
      isFalse,
    );
    final json = const AppUserPreferences(joinVideoCameraOn: false).toJson();
    expect(AppUserPreferences.fromJson(json).joinVideoCameraOn, isFalse);
  });
}
