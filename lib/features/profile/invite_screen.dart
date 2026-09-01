import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/profile_card_picker.dart';
import '../auth/auth_gate.dart';

/// 招待リンク（`/invite/:rhingId`）・QRコード読み取りの両方から開かれる、
/// 友達申請の確認画面。ログイン前に開かれた場合は[AuthGate]がまずログイン・
/// Rhing ID登録を済ませてから、この画面本体（[_InviteConfirmView]）を表示する。
class InviteScreen extends StatelessWidget {
  const InviteScreen({required this.rhingId, super.key});

  final String rhingId;

  @override
  Widget build(BuildContext context) {
    return AuthGate(
      builder: (context, currentUser) =>
          _InviteConfirmView(currentUser: currentUser, inviterRhingId: rhingId),
    );
  }
}

enum _InviteStatus { loading, invalid, self, alreadyFriends, ready, sent }

class _InviteConfirmView extends ConsumerStatefulWidget {
  const _InviteConfirmView({
    required this.currentUser,
    required this.inviterRhingId,
  });

  final AppUser currentUser;
  final String inviterRhingId;

  @override
  ConsumerState<_InviteConfirmView> createState() => _InviteConfirmViewState();
}

class _InviteConfirmViewState extends ConsumerState<_InviteConfirmView> {
  _InviteStatus _status = _InviteStatus.loading;
  AppUser? _inviter;
  bool _isSending = false;
  String? _errorMessage;

  /// この相手との一対で使うプロフィールカード（省略時は標準が適用される、
  /// 2026-07-29追加）。
  String? _selectedProfileCardId;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final rhingId = widget.inviterRhingId.trim().toLowerCase();
    if (rhingId.isEmpty) {
      setState(() => _status = _InviteStatus.invalid);
      return;
    }

    final userRepository = ref.read(userRepositoryProvider);
    final inviter = await userRepository.findByRhingId(rhingId);
    if (!mounted) return;
    if (inviter == null) {
      setState(() => _status = _InviteStatus.invalid);
      return;
    }
    if (inviter.userId == widget.currentUser.userId) {
      setState(() => _status = _InviteStatus.self);
      return;
    }

    final friendRepository = ref.read(friendRepositoryProvider);
    final alreadyFriends = await friendRepository.isFriend(
      userId: widget.currentUser.userId,
      otherUserId: inviter.userId,
    );
    if (!mounted) return;
    setState(() {
      _inviter = inviter;
      _status = alreadyFriends
          ? _InviteStatus.alreadyFriends
          : _InviteStatus.ready;
    });
  }

  Future<void> _sendRequest() async {
    final inviter = _inviter;
    if (inviter == null) return;

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      final friendRepository = ref.read(friendRepositoryProvider);
      await friendRepository.sendRequest(from: widget.currentUser, to: inviter);
      final selectedProfileCardId = _selectedProfileCardId;
      if (selectedProfileCardId != null) {
        await ref
            .read(userRepositoryProvider)
            .setConversationProfileCard(
              userId: widget.currentUser.userId,
              conversationId: DirectMessage.idFor(
                widget.currentUser.userId,
                inviter.userId,
              ),
              profileCardId: selectedProfileCardId,
            );
      }
      if (!mounted) return;
      setState(() => _status = _InviteStatus.sent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(strings.inviteScreenTitle),
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
      case _InviteStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case _InviteStatus.invalid:
        return _Message(text: strings.inviteScreenInvalid, strings: strings);
      case _InviteStatus.self:
        return _Message(text: strings.friendSearchSelf, strings: strings);
      case _InviteStatus.alreadyFriends:
        return _Message(
          text: strings.friendRequestAlreadyFriends,
          strings: strings,
        );
      case _InviteStatus.sent:
        return _Message(text: strings.friendRequestSent, strings: strings);
      case _InviteStatus.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.handshake_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              strings.inviteConfirmDescriptionTemplate(_inviter!.rhingId),
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
            Row(
              children: [
                TextButton(
                  onPressed: _isSending ? null : () => context.go('/'),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: 8),
                // テーマの`ElevatedButtonThemeData.minimumSize`が横幅
                // `double.infinity`のため、`Row`直下に裸で置くと横幅の
                // 制約が衝突してレイアウトが破綻する（背景色に紛れて
                // ボタンが見えなくなる不具合の原因、2026-08-14修正）。
                // `Expanded`で有限の幅に収める。
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendRequest,
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(strings.inviteScreenSendButton),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.strings});

  final String text;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/'),
          child: Text(strings.inviteScreenGoHome),
        ),
      ],
    );
  }
}
