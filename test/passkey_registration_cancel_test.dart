import 'package:daidai/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys/exceptions.dart';

// パスキーでの新規登録の中断の判定（2026-11-15）。提案もセキュリティキーも断った時に
// `Instance of ...`がエラー表示されていた。
void main() {
  test('利用者の中断・使えるパスキー無しは中断として扱う', () {
    expect(
      isPasskeyRegistrationCancellation(PasskeyAuthCancelledException()),
      isTrue,
    );
    expect(
      isPasskeyRegistrationCancellation(NoCredentialsAvailableException()),
      isTrue,
    );
  });

  test('Webのブラウザが返す、型が分からない例外も中断として扱う', () {
    expect(isPasskeyRegistrationCancellation(Object()), isTrue);
    expect(isPasskeyRegistrationCancellation('NotAllowedError'), isTrue);
  });

  test('端末・ドメインの問題を表すパッケージの例外は中断ではない', () {
    expect(
      isPasskeyRegistrationCancellation(DeviceNotSupportedException()),
      isFalse,
    );
    expect(
      isPasskeyRegistrationCancellation(DomainNotAssociatedException('x')),
      isFalse,
    );
  });
}
