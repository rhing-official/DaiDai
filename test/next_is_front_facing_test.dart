import 'package:daidai/features/call/webrtc_media_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ネイティブ: 戻り値（切替後が前面か）をそのまま使う', () {
    // 前面→背面。戻り値はfalse（背面になった）。
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: true,
        previousFront: true,
        nativeIsFront: false,
      ),
      isFalse,
    );
    // 背面→前面。戻り値はtrue。
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: false,
        previousFront: false,
        nativeIsFront: true,
      ),
      isTrue,
    );
  });

  test('ネイティブ: 戻り値が無い（例外など）時は前回のまま', () {
    expect(
      nextIsFrontFacing(
        isWeb: false,
        settingsFront: true,
        previousFront: true,
        nativeIsFront: null,
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
        nativeIsFront: null,
      ),
      isFalse,
    );
    expect(
      nextIsFrontFacing(
        isWeb: true,
        settingsFront: null,
        previousFront: true,
        nativeIsFront: null,
      ),
      isFalse,
    );
  });
}
