import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saved_account.dart';
import '../repositories/saved_accounts_store.dart';
import '../repositories/switch_session_repository.dart';
import '../services/account_switcher.dart';
import '../utils/account_local_state.dart';
import '../utils/page_reload/page_reload.dart';
import 'repository_providers.dart';

/// 複数アカウントの切り替え（2026-11-11）のプロバイダー。

final switchSessionRepositoryProvider = Provider<SwitchSessionRepository>(
  (ref) => FirebaseSwitchSessionRepository(),
);

final savedAccountsStoreProvider = Provider<SavedAccountsStore>(
  (ref) => SecureSavedAccountsStore(),
);

final accountSwitcherProvider = Provider<AccountSwitcher>(
  (ref) => AccountSwitcher(
    sessions: ref.watch(switchSessionRepositoryProvider),
    store: ref.watch(savedAccountsStoreProvider),
    auth: ref.watch(authRepositoryProvider),
    resetLocalState: clearAccountBoundLocalState,
    reloadPage: reloadPage,
  ),
);

/// この端末に保存したアカウント一覧。追加・取り外しの後は`ref.invalidate`で読み直す。
final savedAccountsProvider = FutureProvider.autoDispose<List<SavedAccount>>(
  (ref) => ref.watch(accountSwitcherProvider).accounts(),
);

/// アカウントを追加している途中か（ログイン画面に案内を出す）。
final hasPendingAccountAddProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(accountSwitcherProvider).hasPendingAdd(),
);
