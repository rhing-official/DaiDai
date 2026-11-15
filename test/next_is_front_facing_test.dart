import 'package:daidai/features/call/webrtc_media_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ネイティブ: 設定が古くても、切替に成功したら前回の反対', () {
    // 外カメラに切替後も、設定は作成時の「前面」のまま返る。
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: true,
        previousFront: true,
        switchSucceeded: true,
      ),
      isFalse,
    );
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: false,
        previousFront: false,
        switchSucceeded: true,
      ),
      isTrue,
    );
  });

  test('ネイティブ: 切替に失敗したら前回のまま', () {
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: true,
        previousFront: true,
        switchSucceeded: false,
      ),
      isTrue,
    );
  });

  test('Web: 設定を使う。取れなければ前回の反対', () {
    expect(
      nextIsFrontFacing(
        isWeb: true,
        settingsFront: false,
        previousFront: true,
        switchSucceeded: true,
      ),
      isFalse,
    );
    expect(
      nextIsFrontFacing(
        isWeb: true,
        settingsFront: null,
        previousFront: true,
        switchSucceeded: true,
      ),
      isFalse,
    );
  });
}
