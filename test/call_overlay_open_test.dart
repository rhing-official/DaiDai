import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/active_call_session.dart';
import 'package:daidai/features/call/webrtc_call_controller.dart';
import 'package:daidai/features/call/webrtc_group_call_controller.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/call.dart';
import 'package:daidai/repositories/call_repository.dart';
import 'package:daidai/repositories/direct_message_repository.dart';
import 'package:daidai/repositories/group_call_repository.dart';

class _NoRepo implements GroupCallRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoCallRepo implements CallRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoDmRepo implements DirectMessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSessionNotifier extends ActiveCallSessionNotifier {
  void set(ActiveCallSession? session) => state = session;
}

GroupCallSession _group(String id) => GroupCallSession(
  controller: WebrtcGroupCallController(
    groupCallId: id,
    currentUser: const AppUser(userId: 'u', rhingSeed: 's'),
    isVideo: false,
    groupCallRepository: _NoRepo(),
  ),
  groupCallId: id,
  groupId: 'g',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 通話コントローラーが効果音用に作るaudioplayersのチャンネルを空実装にする。
  for (final name in [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  late ProviderContainer container;
  late _FakeSessionNotifier notifier;

  setUp(() {
    notifier = _FakeSessionNotifier();
    container = ProviderContainer(
      overrides: [activeCallSessionProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    // 購読を維持する（auto-disposeでなくても、状態を保つため）。
    container.listen(callOverlayOpenProvider, (_, _) {});
  });

  test('通話が無い間は閉じている', () {
    expect(container.read(callOverlayOpenProvider), isFalse);
  });

  test('広場の通話を始めると自動で開き、閉じても通話は続く', () {
    final session = _group('c1');
    notifier.set(session);
    expect(container.read(callOverlayOpenProvider), isTrue);
    container.read(callOverlayOpenProvider.notifier).close();
    expect(container.read(callOverlayOpenProvider), isFalse);
    expect(container.read(activeCallSessionProvider), same(session));
    container.read(callOverlayOpenProvider.notifier).open();
    expect(container.read(callOverlayOpenProvider), isTrue);
  });

  test('ドック状態の変更（同じ通話）では閉じ直さない', () {
    notifier.set(_group('c1'));
    container.read(callOverlayOpenProvider.notifier).close();
    notifier.set(
      (container.read(activeCallSessionProvider)! as GroupCallSession)
          .copyWithMinimized(true),
    );
    expect(container.read(callOverlayOpenProvider), isFalse);
  });

  test('通話が終わると閉じ、次の通話で再び自動で開く', () {
    notifier.set(_group('c1'));
    notifier.set(null);
    expect(container.read(callOverlayOpenProvider), isFalse);
    notifier.set(_group('c2'));
    expect(container.read(callOverlayOpenProvider), isTrue);
  });

  test('1対1の着信は応答前は開かず、応答で開く', () {
    const call = Call(
      callId: 'k',
      dmId: 'd',
      callerId: 'a',
      callerRhingSeed: 'a',
      calleeId: 'u',
      calleeRhingSeed: 'u',
      status: CallStatus.ringing,
    );
    final controller = WebrtcCallController(
      call: call,
      isCaller: false,
      callRepository: _NoCallRepo(),
      directMessageRepository: _NoDmRepo(),
    );
    notifier.set(
      OneToOneCallSession(controller: controller, call: call, isCaller: false),
    );
    expect(container.read(callOverlayOpenProvider), isFalse);
    container.read(callOverlayOpenProvider.notifier).open();
    expect(container.read(callOverlayOpenProvider), isTrue);
  });
}
