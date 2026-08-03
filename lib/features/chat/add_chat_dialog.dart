import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/profile_card_picker.dart';

/// 友達申請の送信ポップアップ（2026-07-29、画面遷移からポップアップ化）。
/// 相手のRhing IDを検索し、まだ友達でなければ申請を送る。既に友達の場合は
/// そのまま一対を開く（＝IDを使うのは最初の1回だけで、以降はニックネームで
/// 見分けられるようにする方針）。「＋」ボタンのメニューポップアップの上に
/// 重ねて表示される（`TalksTab._showAddMenu`参照）。
class AddChatDialogContent extends ConsumerStatefulWidget {
  const AddChatDialogContent({
    required this.currentUser,
    required this.onClose,
    required this.onCompleted,
    super.key,
  });

  final AppUser currentUser;

  /// 閉じる（×）ボタン。このポップアップ自体だけを閉じ、下に重なっている
  /// 「＋」メニューポップアップは開いたままにする。
  final VoidCallback onClose;

  /// 一対を開いて画面遷移する直前に呼ぶ。このポップアップ・その下に重なって
  /// いる「＋」メニューポップアップの両方を閉じる必要があるため、[onClose]
  /// とは別のコールバックとして分離している。
  final VoidCallback onCompleted;

  @override
  ConsumerState<AddChatDialogContent> createState() =>
      _AddChatDialogContentState();
}

class _AddChatDialogContentState extends ConsumerState<AddChatDialogContent> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  String? _errorMessage;
  String? _successMessage;

  /// 検索で見つかった、まだ友達でない相手。非nullの間、検索フォームの代わりに
  /// プロフィールカード選択を含む確認UIを表示する。
  AppUser? _pendingTarget;
  String? _selectedProfileCardId;

  Future<void> _search() async {
    final strings = ref.read(appStringsProvider);
    final rhingId = _controller.text.trim().toLowerCase().replaceFirst(
      RegExp(r'^@+'),
      '',
    );
    if (rhingId.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final userRepository = ref.read(userRepositoryProvider);
      final other = await userRepository.findByRhingId(rhingId);
      if (other == null) {
        setState(() => _errorMessage = strings.friendSearchNotFound);
        return;
      }
      if (other.userId == widget.currentUser.userId) {
        setState(() => _errorMessage = strings.friendSearchSelf);
        return;
      }

      final friendRepository = ref.read(friendRepositoryProvider);
      final alreadyFriends = await friendRepository.isFriend(
        userId: widget.currentUser.userId,
        otherUserId: other.userId,
      );

      if (alreadyFriends) {
        final dmRepository = ref.read(directMessageRepositoryProvider);
        final dm = await dmRepository.getOrCreateDirectMessage(
          widget.currentUser,
          other,
        );
        if (!mounted) return;
        widget.onCompleted();
        ref
            .read(goRouterProvider)
            .push(
              '/chat/dm',
              extra: DmChatArgs(
                currentUser: widget.currentUser,
                dm: dm,
                roomId: dm.defaultRoomId,
                // 作成直後の一対は常に「メイン」という名前の寄合が1つだけ
                // 存在する（DirectMessageRepository.getOrCreateDirectMessage/
                // FriendRepository.respond参照）。
                roomName: 'メイン',
              ),
            );
        return;
      }

      // まだ友達でない場合は即送信せず、カード選択を含む確認UIへ切り替える。
      setState(() => _pendingTarget = other);
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _cancelPending() {
    setState(() {
      _pendingTarget = null;
      _selectedProfileCardId = null;
    });
  }

  Future<void> _confirmSend() async {
    final strings = ref.read(appStringsProvider);
    final other = _pendingTarget;
    if (other == null) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    try {
      final friendRepository = ref.read(friendRepositoryProvider);
      await friendRepository.sendRequest(from: widget.currentUser, to: other);
      final selectedProfileCardId = _selectedProfileCardId;
      if (selectedProfileCardId != null) {
        await ref
            .read(userRepositoryProvider)
            .setConversationProfileCard(
              userId: widget.currentUser.userId,
              conversationId: DirectMessage.idFor(
                widget.currentUser.userId,
                other.userId,
              ),
              profileCardId: selectedProfileCardId,
            );
      }
      if (!mounted) return;
      setState(() {
        _successMessage = strings.friendRequestSent;
        _pendingTarget = null;
        _selectedProfileCardId = null;
      });
      _controller.clear();
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final pendingTarget = _pendingTarget;

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
                  strings.friendSearchTitle,
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
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: pendingTarget != null
                  ? _buildConfirmStep(context, strings, pendingTarget)
                  : _buildSearchStep(context, strings),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSearchStep(BuildContext context, Strings strings) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return [
      Text(strings.friendSearchHint),
      const SizedBox(height: 16),
      isGekiga
          ? GekigaTextField(
              controller: _controller,
              autofocus: true,
              labelText: strings.friendSearchLabel,
              prefixText: '@',
              onSubmitted: (_) => _search(),
            )
          : TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.friendSearchLabel,
                prefixText: '@',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 8),
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      ],
      if (_successMessage != null) ...[
        const SizedBox(height: 8),
        Text(
          _successMessage!,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSearching ? null : _search,
          child: _isSearching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(strings.friendSearchSearchButton),
        ),
      ),
    ];
  }

  List<Widget> _buildConfirmStep(
    BuildContext context,
    Strings strings,
    AppUser target,
  ) {
    return [
      Text('@${target.rhingId}'),
      if (_errorMessage != null) ...[
        const SizedBox(height: 8),
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      ],
      const SizedBox(height: 24),
      Text(
        strings.profileCardPickerLabel,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      ProfileCardPicker(
        strings: strings,
        cards: widget.currentUser.profileCards,
        selectedCardId: _selectedProfileCardId,
        onSelected: (id) => setState(() => _selectedProfileCardId = id),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          TextButton(
            onPressed: _isSearching ? null : _cancelPending,
            child: Text(strings.cancel),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSearching ? null : _confirmSend,
            child: _isSearching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.friendSearchButton),
          ),
        ],
      ),
    ];
  }
}
