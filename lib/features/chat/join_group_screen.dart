import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/group_invite_preview.dart';
import '../../models/group_join_request.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../widgets/profile_card_picker.dart';
import '../auth/auth_gate.dart';

/// 招待リンク（`/join/:groupId`）・QRコード読み取りの両方から開かれる、
/// 広場への参加リクエスト確認画面。ログイン前に開かれた場合は[AuthGate]が
/// まずログイン・Rhing ID登録を済ませてから、この画面本体を表示する。
class JoinGroupScreen extends StatelessWidget {
  const JoinGroupScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return AuthGate(
      builder: (context, currentUser) =>
          _JoinGroupView(currentUser: currentUser, groupId: groupId),
    );
  }
}

enum _JoinStatus {
  loading,
  invalid,
  alreadyMember,
  pending,
  ready,
  sent,
  error,
}

class _JoinGroupView extends ConsumerStatefulWidget {
  const _JoinGroupView({required this.currentUser, required this.groupId});

  final AppUser currentUser;
  final String groupId;

  @override
  ConsumerState<_JoinGroupView> createState() => _JoinGroupViewState();
}

class _JoinGroupViewState extends ConsumerState<_JoinGroupView> {
  _JoinStatus _status = _JoinStatus.loading;
  GroupInvitePreview? _preview;
  bool _isSending = false;
  String? _errorMessage;

  /// この広場で使うプロフィールカード（省略時は標準が適用される、
  /// 2026-07-29追加）。
  String? _selectedProfileCardId;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // 以前はここでの例外がどこにも捕捉されておらず、何らかの理由（一時的な
    // 通信エラー等）で失敗すると`_status`が`loading`のまま止まり、画面が
    // スピナーが回り続けるだけで「新しいタブが開いても何も起きない」ように
    // 見える不具合になっていた。失敗時は再試行できるエラー画面を出す。
    setState(() => _status = _JoinStatus.loading);
    try {
      final groupRepository = ref.read(groupRepositoryProvider);

      final existingGroup = await groupRepository.getGroup(widget.groupId);
      if (!mounted) return;
      if (existingGroup != null) {
        setState(() => _status = _JoinStatus.alreadyMember);
        return;
      }

      final preview = await groupRepository.getInvitePreview(widget.groupId);
      if (!mounted) return;
      if (preview == null) {
        setState(() => _status = _JoinStatus.invalid);
        return;
      }

      final existingRequest = await groupRepository.getJoinRequest(
        groupId: widget.groupId,
        requesterId: widget.currentUser.userId,
      );
      if (!mounted) return;
      if (existingRequest?.status == GroupJoinRequestStatus.pending) {
        setState(() {
          _preview = preview;
          _status = _JoinStatus.pending;
        });
        return;
      }

      setState(() {
        _preview = preview;
        _status = _JoinStatus.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'エラーが発生しました: $e';
        _status = _JoinStatus.error;
      });
    }
  }

  Future<void> _requestToJoin() async {
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      final groupRepository = ref.read(groupRepositoryProvider);
      await groupRepository.requestToJoin(
        groupId: widget.groupId,
        requester: widget.currentUser,
      );
      final selectedProfileCardId = _selectedProfileCardId;
      if (selectedProfileCardId != null) {
        await ref
            .read(userRepositoryProvider)
            .setConversationProfileCard(
              userId: widget.currentUser.userId,
              conversationId: widget.groupId,
              profileCardId: selectedProfileCardId,
            );
      }
      if (!mounted) return;
      setState(() => _status = _JoinStatus.sent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _openGroup() async {
    final groupRepository = ref.read(groupRepositoryProvider);
    final group = await groupRepository.getGroup(widget.groupId);
    if (!mounted || group == null) return;
    // 複数モードでも寄合一覧のドリルダウン画面を経由せず、常にdefaultRoomIdで
    // チャット画面へ直接開く。寄合の切り替えはチャット画面上部の横スクロール
    // タブバーから行う（2026-08-03変更、以前は複数モードのみ
    // `/chat/group-rooms`を経由していた）。
    final rooms = await groupRepository
        .watchRooms(groupId: group.groupId, userId: widget.currentUser.userId)
        .first;
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == group.defaultRoomId)?.name ??
        'メイン';
    if (!mounted) return;
    ref
        .read(goRouterProvider)
        .pushReplacement(
          '/chat/group',
          extra: GroupChatArgs(
            currentUser: widget.currentUser,
            group: group,
            roomId: group.defaultRoomId,
            roomName: roomName,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(strings.groupJoinScreenTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(context, strings),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Strings strings) {
    switch (_status) {
      case _JoinStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case _JoinStatus.invalid:
        return _Message(text: strings.groupJoinInvalid, strings: strings);
      case _JoinStatus.alreadyMember:
        return _Message(
          text: strings.groupJoinAlreadyMember,
          strings: strings,
          actionLabel: strings.groupJoinOpenGroup,
          onAction: _openGroup,
        );
      case _JoinStatus.pending:
        return _Message(text: strings.groupJoinPending, strings: strings);
      case _JoinStatus.error:
        return _Message(
          text: _errorMessage ?? 'エラーが発生しました',
          strings: strings,
          actionLabel: strings.groupJoinRetry,
          onAction: _resolve,
        );
      case _JoinStatus.sent:
        return _Message(text: strings.groupJoinRequestSent, strings: strings);
      case _JoinStatus.ready:
        final preview = _preview!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: preview.iconUrl != null
                  ? NetworkImage(preview.iconUrl!)
                  : null,
              child: preview.iconUrl == null
                  ? const Icon(Icons.groups_outlined, size: 36)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              preview.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              textAlign: TextAlign.center,
            ),
            if (preview.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(preview.description, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            Text(
              strings.groupJoinDescriptionTemplate(preview.name),
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                strings.profileCardPickerLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ProfileCardPicker(
              strings: strings,
              cards: widget.currentUser.profileCards,
              selectedCardId: _selectedProfileCardId,
              activeCardName: widget.currentUser.activeProfileCard?.name,
              onSelected: (id) => setState(() => _selectedProfileCardId = id),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSending ? null : _requestToJoin,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.groupJoinRequestButton),
            ),
          ],
        );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.strings,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final Strings strings;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onAction ?? () => context.go('/'),
          child: Text(actionLabel ?? strings.inviteScreenGoHome),
        ),
      ],
    );
  }
}
