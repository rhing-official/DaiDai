import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../utils/open_conversation.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/text_prominence_colors.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_avatar.dart';
import '../../widgets/profile_card_picker.dart';

/// 友達一覧をプルダウン選択できるよう、Rhing Seedではなく呼び名（未設定ならRhing Seed）で表示する。
String _displayName(AppUser user) {
  final nickname = user.activeNickname?.text;
  return (nickname != null && nickname.isNotEmpty)
      ? nickname
      : '@${user.rhingSeed}';
}

/// 友達一覧（フルプロフィール、呼び名表示のため）を監視する。
final _candidateFriendsProvider = StreamProvider.family<List<AppUser>, String>((
  ref,
  userId,
) {
  final friendRepository = ref.watch(friendRepositoryProvider);
  final userRepository = ref.watch(userRepositoryProvider);
  return friendRepository
      .watchFriends(userId)
      .asyncMap(
        (friends) => userRepository.getUsersByIds(
          friends.map((f) => f.friendUserId).toList(),
        ),
      );
});

/// 広場（グループ）作成ポップアップ（2026-07-29、画面遷移からポップアップ化）。
/// 3人以上（自分＋2人以上）で作成する。「＋」ボタンのメニューポップアップの
/// 上に重ねて表示される（`TalksTab._showAddMenu`参照）。
///
/// 手順1（広場名・寄合を複数作るか決める）→手順2（友達をチェックボックスで
/// 選ぶ、名前検索あり）の2手順ウィザードにしている（2026-07-29）。
class CreateGroupDialogContent extends ConsumerStatefulWidget {
  const CreateGroupDialogContent({
    required this.currentUser,
    required this.onClose,
    required this.onCompleted,
    super.key,
  });

  final AppUser currentUser;

  /// 閉じる（×）ボタン。このポップアップ自体だけを閉じ、下に重なっている
  /// 「＋」メニューポップアップは開いたままにする。
  final VoidCallback onClose;

  /// 広場を開いて画面遷移する直前に呼ぶ。このポップアップ・その下に重なって
  /// いる「＋」メニューポップアップの両方を閉じる必要があるため、[onClose]
  /// とは別のコールバックとして分離している。
  final VoidCallback onCompleted;

  @override
  ConsumerState<CreateGroupDialogContent> createState() =>
      _CreateGroupDialogContentState();
}

class _CreateGroupDialogContentState
    extends ConsumerState<CreateGroupDialogContent> {
  static const _totalSteps = 2;

  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _members = <AppUser>[];

  int _step = 1;
  bool _isCreating = false;
  String? _errorMessage;

  /// 寄合を複数扱うか（2026-07-29追加）。falseを選んだ場合、後から
  /// ハンバーガーメニューの「寄合を複数扱う」でtrueに切り替えられる
  /// （逆方向は不可、`Group.roomsEnabled`参照）。
  bool _roomsEnabled = true;

  /// この広場で使うプロフィールカード（nullは標準に追従、2026-10-11追加）。
  String? _selectedProfileCardId;

  void _goToStep2() {
    if (_nameController.text.trim().isEmpty) {
      setState(
        () => _errorMessage = ref
            .read(appStringsProvider)
            .createGroupNameRequiredError,
      );
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = 2;
    });
  }

  void _goBackToStep1() {
    setState(() {
      _errorMessage = null;
      _step = 1;
    });
  }

  Future<void> _createGroup() async {
    if (_members.length < 2) {
      setState(
        () => _errorMessage = ref
            .read(appStringsProvider)
            .createGroupMinMembersError(2 - _members.length),
      );
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final groupRepository = ref.read(groupRepositoryProvider);
      final group = await groupRepository.createGroup(
        name: _nameController.text.trim(),
        owner: widget.currentUser,
        members: _members,
        roomsEnabled: _roomsEnabled,
      );
      final selectedProfileCardId = _selectedProfileCardId;
      if (selectedProfileCardId != null) {
        try {
          await ref
              .read(userRepositoryProvider)
              .setConversationProfileCard(
                userId: widget.currentUser.userId,
                conversationId: group.groupId,
                profileCardId: selectedProfileCardId,
              );
        } catch (e) {
          // 広場自体は作成済みのため巻き戻さず、カードは後から広場の設定で選べる。
          debugPrint('広場作成時のプロフィールカード保存に失敗: $e');
        }
      }
      // 作成直後の広場は常に「メイン」という名前の寄合が1つだけ存在する
      // （GroupRepository.createGroup参照）。
      final rooms = await groupRepository
          .watchRooms(groupId: group.groupId, userId: widget.currentUser.userId)
          .first;

      if (!mounted || rooms.isEmpty) return;
      widget.onCompleted();
      // 設定した語らいレイアウトどおりに開く（2026-10-11変更）。
      await openGroupInTalks(ref, group, roomId: rooms.first.roomId);
    } catch (e) {
      setState(
        () => _errorMessage = ref
            .read(appStringsProvider)
            .genericErrorTemplate(e),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ref.watch(appStringsProvider).createGroupTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StepIndicator(currentStep: _step, totalSteps: _totalSteps),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _step == 1 ? _buildStep1() : _buildStep2(),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStep1() {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final strings = ref.watch(appStringsProvider);
    final liveUser =
        ref.watch(watchedUserProvider(widget.currentUser.userId)).value ??
        widget.currentUser;
    return [
      isGekiga
          ? GekigaTextField(
              controller: _nameController,
              autofocus: true,
              labelText: strings.createGroupNameLabel,
              onSubmitted: (_) => _goToStep2(),
            )
          : TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.createGroupNameLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _goToStep2(),
            ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _roomsEnabled,
        title: Text(strings.createGroupMultiRoomTitle),
        subtitle: Text(strings.createGroupMultiRoomSubtitle),
        onChanged: (value) => setState(() => _roomsEnabled = value),
      ),
      const SizedBox(height: 8),
      Text(
        strings.profileCardPickerLabel,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      ProfileCardPicker(
        strings: strings,
        cards: liveUser.profileCards,
        selectedCardId: _selectedProfileCardId,
        activeCard: liveUser.activeProfileCard,
        onSelected: (id) => setState(() => _selectedProfileCardId = id),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 8),
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _goToStep2,
          child: Text(strings.createGroupNextButton),
        ),
      ),
    ];
  }

  List<Widget> _buildStep2() {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final strings = ref.watch(appStringsProvider);
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isCreating ? null : _goBackToStep1,
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(strings.createGroupMemberStepTitle)),
        ],
      ),
      const SizedBox(height: 8),
      isGekiga
          ? GekigaTextField(
              controller: _searchController,
              labelText: strings.createGroupSearchLabel,
              prefixIcon: const Icon(Icons.search, color: GekigaColors.onPanel),
              onChanged: (_) => setState(() {}),
            )
          : TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: strings.createGroupSearchLabel,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
      const SizedBox(height: 8),
      Consumer(
        builder: (context, ref, _) {
          final friendsAsync = ref.watch(
            _candidateFriendsProvider(widget.currentUser.userId),
          );
          final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
          final emptyStateColor = isGekiga
              ? GekigaColors.onPanel.withValues(alpha: 0.75)
              : resolveTertiaryTextColor(context, isGlass: isGlass);
          return friendsAsync.when(
            data: (friends) {
              if (friends.isEmpty) {
                return Text(
                  strings.createGroupNoFriends,
                  style: TextStyle(color: emptyStateColor),
                );
              }
              final query = _searchController.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? friends
                  : friends
                        .where(
                          (u) =>
                              _displayName(u).toLowerCase().contains(query) ||
                              u.rhingSeed.toLowerCase().contains(query),
                        )
                        .toList();
              if (filtered.isEmpty) {
                return Text(
                  strings.createGroupNoMatch,
                  style: TextStyle(color: emptyStateColor),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final friend = filtered[index];
                    final selected = _members.any(
                      (m) => m.userId == friend.userId,
                    );
                    final icon = friend.activeIcon;
                    return CheckboxListTile(
                      value: selected,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: isGlass
                          ? GlassAvatar(
                              size: 40,
                              image: icon != null
                                  ? NetworkImage(icon.url)
                                  : null,
                              fallback: icon != null
                                  ? null
                                  : Icon(
                                      Icons.person,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                            )
                          : CircleAvatar(
                              backgroundImage: icon != null
                                  ? NetworkImage(icon.url)
                                  : null,
                              backgroundColor: Colors.transparent,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              child: icon == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                      title: Text(_displayName(friend)),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _members.add(friend);
                        } else {
                          _members.removeWhere(
                            (m) => m.userId == friend.userId,
                          );
                        }
                        _errorMessage = null;
                      }),
                    );
                  },
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text(
              strings.createGroupFriendsLoadError(e),
              style: const TextStyle(color: Colors.red),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      Text(
        strings.createGroupSelectedCount(_members.length),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 8),
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isCreating ? null : _createGroup,
          child: _isCreating
              ? const SizedBox.shrink()
              : Text(strings.commonCreate),
        ),
      ),
    ];
  }
}

/// ポップアップ上部の「今どの手順にいるか」を丸数字で示すインジケーター
/// （2026-07-29追加）。現在の手順・完了済みの手順は塗りつぶし、
/// 手順同士は横線で繋ぐ。
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var step = 1; step <= totalSteps; step++) ...[
          if (step > 1)
            Container(
              width: 32,
              height: 2,
              color: step <= currentStep
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          _StepCircle(number: step, filled: step <= currentStep),
        ],
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({required this.number, required this.filled});

  final int number;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colorScheme.primary : Colors.transparent,
        border: Border.all(
          color: filled ? colorScheme.primary : colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: filled ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
