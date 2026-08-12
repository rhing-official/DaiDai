import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/message.dart';
import '../../models/profile_material.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/official_account.dart';
import '../chat/chat_screen.dart';

/// 運営向け管理画面本体（2026-08-12新設）。住人一覧・アカウント停止/解除・
/// お知らせ・便りの身だしなみの3セクションを左サイドバーで切り替える。
/// [AdminGate]経由でのみ到達する（管理者クレームを確認済み）。
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  int _selectedIndex = 0;
  bool _backfilling = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// 一度きりの`accountStatus`バックフィル（`lib/repositories/user_repository.dart`
  /// の`backfillAccountStatusOnce`参照）。運営本人が実行・べき等性確認
  /// （2回目に`backfilled: 0`になること）を終えたら、このボタン・
  /// repositoryメソッド・Cloud Function自体をまとめて削除する想定の
  /// 一時的なUI（`AdminGate`の初回管理者登録ボタンと同じ「使い捨て」の
  /// 扱い）。
  Future<void> _runBackfill() async {
    setState(() => _backfilling = true);
    try {
      final result = await ref
          .read(userRepositoryProvider)
          .backfillAccountStatusOnce();
      if (!mounted) return;
      _bannerTimer = showAutoDismissBanner(
        context,
        message:
            'accountStatus一括補修: ${result['scanned']}件中${result['backfilled']}件を補修しました',
        previousTimer: _bannerTimer,
      );
    } catch (e) {
      if (!mounted) return;
      _bannerTimer = showAutoDismissBanner(
        context,
        message: '補修に失敗しました: $e',
        previousTimer: _bannerTimer,
      );
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理画面'),
        actions: [
          IconButton(
            icon: _backfilling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_outlined),
            onPressed: _backfilling ? null : _runBackfill,
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                label: Text('住人一覧'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.campaign_outlined),
                label: Text('お知らせ'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.face_outlined),
                label: Text('身だしなみ'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const _UserListSection(),
                _AnnouncementSection(currentUser: widget.currentUser),
                const _OfficialAccountProfileSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserListSection extends ConsumerWidget {
  const _UserListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_allUsersProvider);
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('エラー: $error')),
      data: (users) {
        final sorted = [...users]
          ..sort((a, b) {
            final aTime = a.createdAt?.toDate();
            final bTime = b.createdAt?.toDate();
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        if (sorted.isEmpty) {
          return const Center(child: Text('住人がいません'));
        }
        return ListView.separated(
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _UserListTile(user: sorted[index]),
        );
      },
    );
  }
}

final _allUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAllUsersForAdmin();
});

class _UserListTile extends ConsumerWidget {
  const _UserListTile({required this.user});

  final AppUser user;

  String _formatTimestamp(DateTime? time) {
    if (time == null) return '不明';
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $hh:$mm';
  }

  String _statusLabel(AccountStatus status) {
    switch (status) {
      case AccountStatus.active:
        return '通常';
      case AccountStatus.pendingDeletion:
        return '削除申請中';
      case AccountStatus.suspended:
        return '停止中';
    }
  }

  Future<void> _confirmToggleSuspend(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final suspend = user.accountStatus != AccountStatus.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'このアカウントを停止しますか？' : 'このアカウントの停止を解除しますか？'),
        content: Text('@${user.rhingId}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(suspend ? '停止する' : '解除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(userRepositoryProvider)
        .setAccountSuspended(user.userId, suspend);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuspended = user.accountStatus == AccountStatus.suspended;
    return ListTile(
      title: Text('@${user.rhingId}'),
      subtitle: Text(
        '作成: ${_formatTimestamp(user.createdAt?.toDate())}\n'
        '最終ログイン: ${_formatTimestamp(user.lastLoginAt?.toDate())}\n'
        '状態: ${_statusLabel(user.accountStatus)}',
      ),
      isThreeLine: true,
      trailing: user.accountStatus == AccountStatus.pendingDeletion
          ? null
          : OutlinedButton(
              onPressed: () => _confirmToggleSuspend(context, ref),
              child: Text(isSuspended ? '解除' : '停止'),
            ),
    );
  }
}

/// お知らせセクション本体。管理者自身も稼働中の住人として便りからの配信を
/// 受け取るため、管理者⇔便りの一対をそのまま通常の語らいのメッセージ画面
/// （[ChatScreen]）で表示し、送信だけ`broadcastAnnouncement`（全住人への
/// 一斉配信）に差し替える（2026-08-12更新、旧: 単純なテキスト欄+送信
/// ボタンのみのUIだった）。これにより住人側も同じ[ChatScreen]で普通の
/// 一対として配信内容を読める。
class _AnnouncementSection extends ConsumerWidget {
  const _AnnouncementSection({required this.currentUser});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final dmId = DirectMessage.idFor(currentUser.userId, officialAccountUid);

    Future<void> send(
      String content, {
      bool silent = false,
      Message? replyTo,
    }) => ref.read(userRepositoryProvider).broadcastAnnouncement(content);

    return StreamBuilder<List<DirectMessage>>(
      stream: dmRepository.watchDirectMessages(currentUser.userId),
      builder: (context, snapshot) {
        final dm = (snapshot.data ?? const []).firstWhereOrNull(
          (d) => d.dmId == dmId,
        );
        // まだ一度も配信していない場合は便りとの一対自体が存在しないため、
        // 履歴は空のまま表示する（初回の配信で`broadcastAnnouncement`が
        // 一対・寄合を自動作成する）。
        return ChatScreen(
          key: ValueKey('admin-broadcast-${dm?.defaultRoomId ?? 'none'}'),
          title: '',
          currentUserId: currentUser.userId,
          isDm: true,
          conversationId: dm?.dmId,
          messagesStream: dm == null
              ? const Stream.empty()
              : dmRepository
                    .watchMessages(dm.dmId, dm.defaultRoomId)
                    .map(
                      (messages) => messages
                          .where(
                            (m) => !m.hiddenFor.contains(currentUser.userId),
                          )
                          .toList(),
                    ),
          onSend: send,
        );
      },
    );
  }
}

/// 便り（公式アカウント）の身だしなみ（アイコン・呼び名）セクション
/// （2026-08-12追加）。便りはFirebase Authに対応する実アカウントを持たない
/// ため、通常の身だしなみタブ（`lib/features/profile/profile_tab.dart`の
/// 蔵・工房）は使えず、管理者がここから直接編集する。firestore.rules・
/// storage.rulesに、`officialAccountUid`宛の書き込みに限定した管理者
/// クレーム経由の例外を追加している。蔵の複数枠管理はせず、常に最新の
/// 1件だけを残す（アップロード・保存のたびに古い素材を置き換える）簡易版。
class _OfficialAccountProfileSection extends ConsumerStatefulWidget {
  const _OfficialAccountProfileSection();

  @override
  ConsumerState<_OfficialAccountProfileSection> createState() =>
      _OfficialAccountProfileSectionState();
}

class _OfficialAccountProfileSectionState
    extends ConsumerState<_OfficialAccountProfileSection> {
  late final Stream<AppUser?> _userStream;
  final _nicknameController = TextEditingController();
  bool _nicknameInitialized = false;
  bool _uploadingIcon = false;
  bool _savingNickname = false;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _userStream = ref
        .read(userRepositoryProvider)
        .watchUser(officialAccountUid);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _showBanner(String message) {
    if (!mounted) return;
    _bannerTimer = showAutoDismissBanner(
      context,
      message: message,
      previousTimer: _bannerTimer,
    );
  }

  /// アイコンを新しく1枚アップロードし、既存のアイコンは全て置き換える
  /// （便りは複数枠を使い分ける必要が無いため、常に最新の1枚のみ残す）。
  Future<void> _pickAndUploadIcon(AppUser user) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      final bytes = await picked.readAsBytes();
      final material = await repo.uploadIcon(officialAccountUid, bytes);
      await repo.addToProfileList(
        officialAccountUid,
        'icons',
        material.toJson(),
      );
      await repo.setProfileField(
        officialAccountUid,
        'activeIconId',
        material.id,
      );
      for (final old in user.icons) {
        await repo.removeFromProfileList(
          officialAccountUid,
          'icons',
          old.toJson(),
        );
        await repo.deleteProfileMaterial(old);
      }
    } catch (e) {
      _showBanner('アイコンの更新に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  /// 呼び名を保存する。既存の登録は全て置き換え、常に1件だけ残す。
  Future<void> _saveNickname(AppUser user) async {
    final text = _nicknameController.text.trim();
    if (text.isEmpty) return;
    if (user.nicknames.length == 1 && user.nicknames.first.text == text) {
      return;
    }
    setState(() => _savingNickname = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      for (final old in user.nicknames) {
        await repo.removeFromProfileList(
          officialAccountUid,
          'nicknames',
          old.toJson(),
        );
      }
      final updated = Nickname(id: 'official', text: text);
      await repo.addToProfileList(
        officialAccountUid,
        'nicknames',
        updated.toJson(),
      );
      await repo.setProfileField(
        officialAccountUid,
        'activeNicknameId',
        'official',
      );
    } catch (e) {
      _showBanner('呼び名の更新に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data;
        if (user == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'まだお知らせを一度も配信していないため、便りのプロフィールが'
              'まだ作成されていません。先に「お知らせ」タブから一度配信すると、'
              '自動的に作成されます。',
            ),
          );
        }
        if (!_nicknameInitialized) {
          _nicknameInitialized = true;
          _nicknameController.text = user.effectiveNickname?.text ?? '';
        }
        final icon = user.effectiveIcon;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: icon == null
                          ? null
                          : NetworkImage(icon.url),
                      child: icon == null
                          ? const Icon(Icons.campaign_outlined, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      onPressed: _uploadingIcon
                          ? null
                          : () => _pickAndUploadIcon(user),
                      child: _uploadingIcon
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('アイコンを変更'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(labelText: '呼び名'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _savingNickname
                          ? null
                          : () => _saveNickname(user),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
