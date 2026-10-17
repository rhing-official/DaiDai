import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';
import '../../../l10n/tutorial_content.dart';
import '../../../models/app_user.dart';
import '../../../providers/repository_providers.dart';
import '../../../repositories/user_repository.dart';
import '../../../router/back_stack.dart';
import '../../../widgets/nav_chip.dart';
import '../../profile/profile_tab.dart';
import 'tutorial_target.dart';

/// 練習用のユーザー。実在のアカウントとは無関係の偽データ。
const _practiceUser = AppUser(
  userId: 'practice-user',
  rhingSeed: 'practice',
  displayName: 'Practice',
);

/// 練習用の`UserRepository`。メモリ上の偽ユーザーを返すだけで、何も書き込まない。
class _PracticeUserRepository implements UserRepository {
  @override
  Stream<AppUser?> watchUser(String userId) => Stream.value(_practiceUser);

  @override
  Future<void> syncInvitePreview(String userId) async {}

  @override
  Future<void> refreshInviteLink(String userId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 練習用のホーム（2026-10-17追加）。本物のナビチップ・身だしなみタブを、偽の
/// ユーザーと書き込まないリポジトリを入れた入れ子の[ProviderScope]の中で動かす。
/// 画面にはユーザーに不要な説明（「練習モード」等）は出さない。
/// 本物のホームの状態・データには一切触れず、ガイドの案内の層が丸で示した場所
/// 以外は押せないため、ユーザーは道順を実際に押して覚えられる。
/// 戻る・進む履歴も専用のものに差し替え、本物の履歴を汚さない。
class PracticeHome extends StatelessWidget {
  const PracticeHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(_PracticeUserRepository()),
        backStackControllerProvider.overrideWith((ref) {
          final controller = BackStackController();
          ref.onDispose(controller.dispose);
          return controller;
        }),
      ],
      child: const _PracticeHomeBody(),
    );
  }
}

class _PracticeHomeBody extends ConsumerStatefulWidget {
  const _PracticeHomeBody();

  @override
  ConsumerState<_PracticeHomeBody> createState() => _PracticeHomeBodyState();
}

class _PracticeHomeBodyState extends ConsumerState<_PracticeHomeBody> {
  int _selectedIndex = 0;

  static const _icons = [
    Icons.forum_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
  ];
  static const _iconSizes = [24.0, 28.0, 28.0];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    const placeholder = SizedBox.shrink();
    return ChipNavShell(
      icons: _icons,
      iconSizes: _iconSizes,
      labels: [strings.navTalk, strings.navProfile, strings.navSettings],
      selectedIndex: _selectedIndex,
      onSelected: (i) => setState(() => _selectedIndex = i),
      chipWrapper: (index, chip) => index == 1
          ? TutorialTarget(id: TutorialTargetIds.navProfile, child: chip)
          : chip,
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          placeholder,
          const ProfileTab(currentUser: _practiceUser),
          placeholder,
        ],
      ),
    );
  }
}
