import 'package:daidai/features/call/active_call_session.dart';
import 'package:daidai/features/call/webrtc_group_call_controller.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/repositories/group_call_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoRepo implements GroupCallRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  test('通話中の通知のタップ: 通話が無ければ開かない', () {
    expect(shouldReopenCallFromNotification(null), isFalse);
  });

  test('同じ通話か: 無ければfalse（ミニ表示で入れ替わったセッションは同じ通話として扱う）', () {
    expect(isSameCallSession(null, null), isFalse);
  });

  test('ミニ表示で入れ替わったセッションは、同じ通話として扱い、別の通話とは区別する', () {
    GroupCallSession make(String id) => GroupCallSession(
      controller: WebrtcGroupCallController(
        groupCallId: id,
        currentUser: const AppUser(userId: 'u', rhingSeed: 's'),
        isVideo: false,
        groupCallRepository: _NoRepo(),
      ),
      groupCallId: id,
      groupId: 'g',
    );
    final original = make('a');
    final minimized = original.copyWithMinimized(true);
    expect(identical(original, minimized), isFalse);
    expect(isSameCallSession(original, minimized), isTrue);
    expect(isSameCallSession(original, make('b')), isFalse);
    expect(shouldReopenCallFromNotification(minimized), isTrue);
    expect(shouldReopenCallFromNotification(original), isFalse);
  });
}
