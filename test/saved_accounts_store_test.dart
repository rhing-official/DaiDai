import 'package:daidai/models/saved_account.dart';
import 'package:daidai/repositories/saved_accounts_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

SavedAccount _account(String uid) => SavedAccount(
  uid: uid,
  sessionId: 's-$uid',
  secret: 'x-$uid',
  rhingSeed: uid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同時に保存しても、どの保存も消えない', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSavedAccountsStore();
    await Future.wait([
      store.save(_account('a')),
      store.save(_account('b')),
      store.save(_account('c')),
    ]);
    final uids = (await store.load()).map((a) => a.uid).toSet();
    expect(uids, {'a', 'b', 'c'});
  });

  test('保存と取り外しが重なっても、順に反映される', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSavedAccountsStore();
    await store.save(_account('a'));
    await Future.wait([store.remove('a'), store.save(_account('b'))]);
    final uids = (await store.load()).map((a) => a.uid).toSet();
    expect(uids, {'b'});
  });
}
