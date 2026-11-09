import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../utils/friend_request_error.dart';
import '../../widgets/profile_card_picker.dart';
import '../auth/auth_gate.dart';

/// 招待リンク（`/invite/:rhingSeed`）・QRコード読み取りの両方から開かれる、
/// 友達申請の確認画面。ログイン前に開かれた場合は[AuthGate]がまずログイン・
/// Rhing Seed登録を済ませてから、この画面本体（[_InviteConfirmView]）を表示する。
class InviteScreen extends StatelessWidget {
  const InviteScreen({
    required this.rhingSeed,
    this.asDialog = false,
    super.key,
  });

  final String rhingSeed;

  /// trueなら、画面ではなくポップアップとして描く（チャット内の招待リンクをタップした時、
  /// 画面を切り替えずに開く、2026-11-09）。閉じる操作も画面遷移ではなくポップアップを閉じる。
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    // ポップアップでは`AuthGate`を通さず、ログイン中のユーザーを直接使う（`AuthGate`の
    // 読み込み中の`Scaffold`が、ポップアップいっぱいの縦長の面になってしまう為）。
    if (asDialog) {
      return Consumer(
        builder: (context, ref, _) {
          final uid = ref.watch(authStateProvider).value?.uid;
          final user = uid == null
              ? null
              : ref.watch(watchedUserProvider(uid)).value;
          if (user == null) return const _DialogLoading();
          return _InviteConfirmView(
            currentUser: user,
            inviterRhingSeed: rhingSeed,
            asDialog: true,
          );
        },
      );
    }
    return AuthGate(
      builder: (context, currentUser) => _InviteConfirmView(
        currentUser: currentUser,
        inviterRhingSeed: rhingSeed,
        asDialog: asDialog,
      ),
    );
  }
}

/// ポップアップの読み込み中の表示。
class _DialogLoading extends StatelessWidget {
  const _DialogLoading();

  @override
  Widget build(BuildContext context) => const Dialog(
    child: SizedBox(
      width: 96,
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

enum _InviteStatus { loading, invalid, self, alreadyFriends, ready, sent }

class _InviteConfirmView extends ConsumerStatefulWidget {
  const _InviteConfirmView({
    required this.currentUser,
    required this.inviterRhingSeed,
    this.asDialog = false,
  });

  final AppUser currentUser;
  final String inviterRhingSeed;
  final bool asDialog;

  @override
  ConsumerState<_InviteConfirmView> createState() => _InviteConfirmViewState();
}

class _InviteConfirmViewState extends ConsumerState<_InviteConfirmView> {
  /// 標準のカードの切り替えなどを即座に反映する為、ログイン時に一度だけ
  /// 取得した`widget.currentUser`ではなく購読中の最新のユーザーを使う
  /// （2026-10-11）。
  AppUser get _liveUser =>
      ref.watch(watchedUserProvider(widget.currentUser.userId)).value ??
      widget.currentUser;

  _InviteStatus _status = _InviteStatus.loading;
  AppUser? _inviter;
  bool _isSending = false;
  String? _errorMessage;

  /// この相手との一対で使うプロフィールカード（省略時は標準が適用される、
  /// 2026-07-29追加）。
  String? _selectedProfileCardId;

  /// 申請に添える任意メッセージ（技術仕様書8.3レイヤー2、2026-09-07追加）。
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final rhingSeed = widget.inviterRhingSeed.trim().toLowerCase();
    if (rhingSeed.isEmpty) {
      setState(() => _status = _InviteStatus.invalid);
      return;
    }

    final userRepository = ref.read(userRepositoryProvider);
    final inviter = await userRepository.findByRhingSeed(rhingSeed);
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
      final message = _messageController.text.trim();
      await friendRepository.sendRequest(
        from: widget.currentUser,
        to: inviter,
        message: message.isEmpty ? null : message,
      );
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
      setState(
        () => _errorMessage = friendRequestErrorMessage(
          e,
          ref.read(appStringsProvider),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    if (widget.asDialog) {
      // `glassAwareDialog`が`Dialog`を作るので、中身は`AlertDialog`ではなく素の列にする
      // （`AlertDialog`を入れると、外側に縦長の`Dialog`がもう1つ出る）。
      return glassAwareDialog(
        isGlass: ref.watch(appUiStyleProvider) == AppUiStyle.glass,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.inviteScreenTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _buildBody(context, strings),
              ],
            ),
          ),
        ),
      );
    }

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

  /// 閉じる。ポップアップならそれを閉じ、画面なら語らいへ戻る。
  void _close(BuildContext context) {
    if (widget.asDialog) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  Widget _buildBody(BuildContext context, Strings strings) {
    switch (_status) {
      case _InviteStatus.loading:
        return const SizedBox.shrink();
      case _InviteStatus.invalid:
        return _Message(
          text: strings.inviteScreenInvalid,
          strings: strings,
          onClose: widget.asDialog ? null : () => _close(context),
        );
      case _InviteStatus.self:
        return _Message(
          text: strings.friendSearchSelf,
          strings: strings,
          onClose: widget.asDialog ? null : () => _close(context),
        );
      case _InviteStatus.alreadyFriends:
        return _Message(
          text: strings.friendRequestAlreadyFriends,
          strings: strings,
          onClose: widget.asDialog ? null : () => _close(context),
        );
      case _InviteStatus.sent:
        return _Message(
          text: strings.friendRequestSent,
          strings: strings,
          onClose: widget.asDialog ? null : () => _close(context),
        );
      case _InviteStatus.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.handshake_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              strings.inviteConfirmDescriptionTemplate(_inviter!.rhingSeed),
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
              cards: _liveUser.profileCards,
              selectedCardId: _selectedProfileCardId,
              activeCard: _liveUser.activeProfileCard,
              onSelected: (id) => setState(() => _selectedProfileCardId = id),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              enabled: !_isSending,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: strings.friendRequestMessageLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _isSending ? null : () => _close(context),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: 8),
                // テーマの`ElevatedButtonThemeData.minimumSize`が横幅
                // `double.infinity`の為、`Row`直下に裸で置くと横幅の
                // 制約が衝突してレイアウトが破綻する（背景色に紛れて
                // ボタンが見えなくなる不具合の原因、2026-08-14修正）。
                // `Expanded`で有限の幅に収める。
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendRequest,
                    child: _isSending
                        ? const SizedBox.shrink()
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
  const _Message({
    required this.text,
    required this.strings,
    required this.onClose,
  });

  final String text;
  final Strings strings;

  /// nullなら「ホームに戻る」ボタンを出さない（ポップアップは外側のタップなどで閉じる）。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        if (onClose != null) ...[
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onClose,
            child: Text(strings.inviteScreenGoHome),
          ),
        ],
      ],
    );
  }
}
