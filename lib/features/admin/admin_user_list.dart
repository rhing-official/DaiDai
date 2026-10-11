import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/generated_avatar.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/profile_card_view.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';

/// 管理画面の住人一覧の取得元（`limit(500)`、並べ替えはUI側）。テストで
/// 差し替えられるよう公開している。
final allUsersForAdminProvider = StreamProvider.autoDispose<List<AppUser>>((
  ref,
) {
  return ref.watch(userRepositoryProvider).watchAllUsersForAdmin();
});

/// プロフィール確認で描くカードの基準サイズ（住人側の`UserProfileCardDialog`が
/// 広い画面で使う幅480・高さ600と同じ。高さは幅×1.25）。
const kAdminProfileCardWidth = 480.0;
const kAdminProfileCardHeight = 600.0;

/// 一括停止/解除で1回に扱える最大件数（サーバー側`BULK_SUSPEND_MAX`と同じ）。
const kAdminBulkSuspendMax = 100;

/// 状態の絞り込み。
enum AdminUserFilter {
  all('すべて'),
  active('通常'),
  suspended('停止中'),
  pendingDeletion('削除申請中');

  const AdminUserFilter(this.label);
  final String label;
}

/// 並べ替え。
enum AdminUserSort {
  createdDesc('作成日（新しい順）'),
  createdAsc('作成日（古い順）'),
  lastLoginDesc('最終ログイン（新しい順）');

  const AdminUserSort(this.label);
  final String label;
}

/// 一覧の検索・状態の絞り込み・並べ替え。[query]は`@rhingSeed`の部分一致
/// （先頭の`@`・大文字小文字は無視）。日時が無いユーザーは常に末尾へ。
List<AppUser> filterAdminUsers(
  List<AppUser> users, {
  String query = '',
  AdminUserFilter filter = AdminUserFilter.all,
  AdminUserSort sort = AdminUserSort.createdDesc,
}) {
  final needle = query.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
  final result = users.where((user) {
    if (needle.isNotEmpty && !user.rhingSeed.toLowerCase().contains(needle)) {
      return false;
    }
    return switch (filter) {
      AdminUserFilter.all => true,
      AdminUserFilter.active => user.accountStatus == AccountStatus.active,
      AdminUserFilter.suspended =>
        user.accountStatus == AccountStatus.suspended,
      AdminUserFilter.pendingDeletion =>
        user.accountStatus == AccountStatus.pendingDeletion,
    };
  }).toList();

  DateTime? timeOf(AppUser user) => switch (sort) {
    AdminUserSort.lastLoginDesc => user.lastLoginAt?.toDate(),
    _ => user.createdAt?.toDate(),
  };
  result.sort((a, b) {
    final aTime = timeOf(a);
    final bTime = timeOf(b);
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return sort == AdminUserSort.createdAsc
        ? aTime.compareTo(bTime)
        : bTime.compareTo(aTime);
  });
  return result;
}

/// 一括操作の対象に選べるか。自分自身・削除申請中は選べない
/// （サーバー側でも同じ条件で除外される）。
bool isAdminUserSelectable(AppUser user, String currentUserId) {
  return user.userId != currentUserId &&
      user.accountStatus != AccountStatus.pendingDeletion;
}

String _formatTimestamp(DateTime? time) {
  if (time == null) return '不明';
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '$y/$m/$d $hh:$mm';
}

/// ガラススタイルの時だけ[GlassAlertDialog]、それ以外は[AlertDialog]で
/// 確認ダイアログを作る。
Widget _adminDialog(
  WidgetRef ref, {
  required Widget title,
  required Widget content,
  required List<Widget> actions,
}) {
  return ref.read(appUiStyleProvider) == AppUiStyle.glass
      ? GlassAlertDialog(title: title, content: content, actions: actions)
      : KeyboardAlertDialog(title: title, content: content, actions: actions);
}

/// 後戻りしにくい確定ボタンの固定の濃い赤（CLAUDE.mdのボタン配色規約）。
final _destructiveStyle = FilledButton.styleFrom(
  backgroundColor: Colors.red.shade700,
  foregroundColor: Colors.white,
);

/// 住人一覧（管理画面、2026-10-10刷新）。住人が設定したカードやアイコンは
/// 一覧に出さず、IDから決まる色の[GeneratedAvatar]と`@rhingSeed`で識別する
/// （プライバシー保護）。見つけるには検索・状態の絞り込み・並べ替えを使う。
/// チェックで複数選択して一括停止/解除ができる。
class AdminUserListSection extends ConsumerStatefulWidget {
  const AdminUserListSection({required this.currentUserId, super.key});

  /// 操作している管理者自身のuserId（一括操作の対象から外す）。
  final String currentUserId;

  @override
  ConsumerState<AdminUserListSection> createState() =>
      _AdminUserListSectionState();
}

class _AdminUserListSectionState extends ConsumerState<AdminUserListSection> {
  final _searchController = TextEditingController();
  AdminUserFilter _filter = AdminUserFilter.all;
  AdminUserSort _sort = AdminUserSort.createdDesc;
  final Set<String> _selected = {};
  bool _busy = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _searchController.dispose();
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

  /// 選択した住人をまとめて停止/解除する（確認ダイアログ付き）。
  Future<void> _bulkSuspend(List<AppUser> selectedUsers, bool suspend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final seeds = selectedUsers.map((u) => '@${u.rhingSeed}').join('\n');
        return _adminDialog(
          ref,
          title: Text(
            suspend
                ? '${selectedUsers.length}件のアカウントを停止しますか？'
                : '${selectedUsers.length}件のアカウントの停止を解除しますか？',
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(child: Text(seeds)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('やめる'),
            ),
            FilledButton(
              style: suspend ? _destructiveStyle : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(suspend ? '停止する' : '解除する'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(userRepositoryProvider)
          .setAccountsSuspended([
            for (final u in selectedUsers) u.userId,
          ], suspend);
      if (!mounted) return;
      setState(() => _selected.removeAll(result.changed));
      final skippedNote = result.skipped.isEmpty
          ? ''
          : '（${result.skipped.length}件は対象外）';
      _showBanner(
        '${result.changed.length}件を${suspend ? '停止' : '解除'}しました$skippedNote',
      );
    } catch (e) {
      _showBanner('一括${suspend ? '停止' : '解除'}に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersForAdminProvider);
    return usersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Center(child: Text('エラー: $error')),
      data: (users) {
        final visible = filterAdminUsers(
          users,
          query: _searchController.text,
          filter: _filter,
          sort: _sort,
        );
        final selectable = [
          for (final u in visible)
            if (isAdminUserSelectable(u, widget.currentUserId)) u,
        ];
        // 絞り込みで見えなくなった選択は保持するが、一覧から消えた（削除等）
        // idは数えない。
        final knownIds = {for (final u in users) u.userId};
        final selectedUsers = [
          for (final u in users)
            if (_selected.contains(u.userId) &&
                knownIds.contains(u.userId) &&
                isAdminUserSelectable(u, widget.currentUserId))
              u,
        ];
        final overLimit = selectedUsers.length > kAdminBulkSuspendMax;
        final allSelected =
            selectable.isNotEmpty &&
            selectable.every((u) => _selected.contains(u.userId));

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '@rhingSeedで検索',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (final f in AdminUserFilter.values)
                                  ChoiceChip(
                                    label: Text(f.label),
                                    selected: _filter == f,
                                    onSelected: (_) =>
                                        setState(() => _filter = f),
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<AdminUserSort>(
                            icon: const Icon(Icons.sort),
                            onSelected: (v) => setState(() => _sort = v),
                            itemBuilder: (context) => [
                              for (final s in AdminUserSort.values)
                                CheckedPopupMenuItem(
                                  value: s,
                                  checked: _sort == s,
                                  child: Text(s.label),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _SelectionBar(
                  allSelected: allSelected,
                  anySelectable: selectable.isNotEmpty,
                  selectedCount: selectedUsers.length,
                  overLimit: overLimit,
                  busy: _busy,
                  onToggleAll: (value) => setState(() {
                    if (value == true) {
                      _selected.addAll(selectable.map((u) => u.userId));
                    } else {
                      _selected.removeAll(selectable.map((u) => u.userId));
                    }
                  }),
                  onSuspend: () => _bulkSuspend(selectedUsers, true),
                  onUnsuspend: () => _bulkSuspend(selectedUsers, false),
                  onClear: () => setState(_selected.clear),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('該当する住人がいません'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final user = visible[index];
                            return _UserRow(
                              user: user,
                              selectable: isAdminUserSelectable(
                                user,
                                widget.currentUserId,
                              ),
                              selected: _selected.contains(user.userId),
                              onSelected: (value) => setState(() {
                                if (value == true) {
                                  _selected.add(user.userId);
                                } else {
                                  _selected.remove(user.userId);
                                }
                              }),
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => _UserDetailDialog(
                                  userId: user.userId,
                                  initial: user,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 全選択のチェックボックスと、選択中の件数・一括操作ボタンの帯。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.allSelected,
    required this.anySelectable,
    required this.selectedCount,
    required this.overLimit,
    required this.busy,
    required this.onToggleAll,
    required this.onSuspend,
    required this.onUnsuspend,
    required this.onClear,
  });

  final bool allSelected;
  final bool anySelectable;
  final int selectedCount;
  final bool overLimit;
  final bool busy;
  final ValueChanged<bool?> onToggleAll;
  final VoidCallback onSuspend;
  final VoidCallback onUnsuspend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: anySelectable && !busy ? onToggleAll : null,
          ),
          Expanded(
            child: Text(
              overLimit
                  ? '$selectedCount件選択中（一度に操作できるのは$kAdminBulkSuspendMax件までです）'
                  : hasSelection
                  ? '$selectedCount件選択中'
                  : '表示中をすべて選択',
            ),
          ),
          if (hasSelection) ...[
            TextButton(
              onPressed: busy ? null : onClear,
              child: const Text('選択解除'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: busy || overLimit ? null : onUnsuspend,
              child: const Text('解除'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: _destructiveStyle,
              onPressed: busy || overLimit ? null : onSuspend,
              child: const Text('停止'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 状態の小さなバッジ。停止中は固定の濃い赤に白文字（CLAUDE.mdの配色規約）。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (user.accountStatus) {
      AccountStatus.active => (
        '通常',
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurface,
      ),
      AccountStatus.suspended => (
        user.autoSuspendedUntil == null
            ? '停止中'
            : '停止中（〜${_formatTimestamp(user.autoSuspendedUntil!.toDate())}）',
        Colors.red.shade700,
        Colors.white,
      ),
      AccountStatus.pendingDeletion => (
        '削除申請中',
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 12)),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.selectable,
    required this.selected,
    required this.onSelected,
    required this.onTap,
  });

  final AppUser user;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: selectable
                    ? Checkbox(value: selected, onChanged: onSelected)
                    : null,
              ),
              GeneratedAvatar(seed: user.userId, label: user.rhingSeed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${user.rhingSeed}', style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '作成: ${_formatTimestamp(user.createdAt?.toDate())}　'
                      '最終ログイン: ${_formatTimestamp(user.lastLoginAt?.toDate())}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「プロフィールを確認」の理由（サーバーの記録用の値と対応）。
enum _ProfileViewReason {
  report('report', '通報への対応'),
  investigation('investigation', '不正利用の調査'),
  other('other', 'その他');

  const _ProfileViewReason(this.value, this.label);
  final String value;
  final String label;
}

/// 住人の詳細。既定は管理に必要なメタ情報のみで、プロフィール（既定の
/// カード）は「プロフィールを確認」で理由を選び、サーバーに記録できた時だけ
/// 表示する（ダイアログを閉じれば元に戻る）。
class _UserDetailDialog extends ConsumerStatefulWidget {
  const _UserDetailDialog({required this.userId, required this.initial});

  final String userId;
  final AppUser initial;

  @override
  ConsumerState<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends ConsumerState<_UserDetailDialog> {
  bool _revealed = false;
  bool _busy = false;

  /// 直近の操作の失敗理由。3秒で消えるバナーだと見落とすため（関数が
  /// 未デプロイ・通信失敗の時に「元に戻っただけ」に見えた、2026-10-10）、
  /// 次の操作までダイアログ内に残す。
  String? _error;

  Future<void> _toggleSuspend(AppUser user) async {
    final suspend = user.accountStatus != AccountStatus.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _adminDialog(
        ref,
        title: Text(suspend ? 'このアカウントを停止しますか？' : 'このアカウントの停止を解除しますか？'),
        content: Text('@${user.rhingSeed}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            style: suspend ? _destructiveStyle : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(suspend ? '停止する' : '解除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .setAccountSuspended(user.userId, suspend);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${suspend ? '停止' : '解除'}に失敗しました: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal(AppUser user) async {
    final result = await showDialog<({_ProfileViewReason reason, String note})>(
      context: context,
      builder: (context) => _ReasonDialog(seed: user.rhingSeed),
    );
    if (result == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .logAdminProfileView(
            user.userId,
            reason: result.reason.value,
            note: result.note,
          );
      if (mounted) setState(() => _revealed = true);
    } catch (e) {
      if (mounted) setState(() => _error = '記録に失敗したため表示できません: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 停止・解除の結果が一覧のストリーム経由で反映されるよう、最新の状態を見る。
    final live = ref
        .watch(allUsersForAdminProvider)
        .value
        ?.where((u) => u.userId == widget.userId)
        .firstOrNull;
    final user = live ?? widget.initial;
    final isSuspended = user.accountStatus == AccountStatus.suspended;
    final textTheme = Theme.of(context).textTheme;

    final rows = <(String, String)>[
      ('userId', user.userId),
      ('作成', _formatTimestamp(user.createdAt?.toDate())),
      ('最終ログイン', _formatTimestamp(user.lastLoginAt?.toDate())),
      if (user.autoSuspendedUntil != null)
        ('自動停止の期限', _formatTimestamp(user.autoSuspendedUntil!.toDate())),
    ];

    final title = Row(
      children: [
        GeneratedAvatar(seed: user.userId, label: user.rhingSeed),
        const SizedBox(width: 12),
        Expanded(child: Text('@${user.rhingSeed}')),
        _StatusBadge(user: user),
      ],
    );
    final content = SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('$label: $value', style: textTheme.bodyMedium),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (_revealed) ...[
              const SizedBox(height: 16),
              // 住人が作ったカードと同じ基準サイズ
              // （幅480・高さ600）で描き、ダイアログの幅に合わせて縮小する。
              // `ProfileCardView`の中身（アイコン・文字・余白）は固定サイズの
              // ため、小さい幅でそのまま描くとアイコンと文字だけが大きく見え、
              // 住人が作ったカードと比率が変わってしまう（2026-10-10）。
              AspectRatio(
                aspectRatio: kAdminProfileCardWidth / kAdminProfileCardHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: ProfileCardView(
                    width: kAdminProfileCardWidth,
                    height: kAdminProfileCardHeight,
                    icon: user.effectiveIcon,
                    background: user.effectiveBackgroundImage,
                    backgroundFocal: user.activeProfileCard?.backgroundFocal,
                    iconFocal: user.activeProfileCard?.iconFocal,
                    nickname: (user.effectiveNickname?.text.isNotEmpty ?? false)
                        ? user.effectiveNickname!.text
                        : '@${user.rhingSeed}',
                    statusMessage: user.effectiveStatusMessage?.text,
                    // 住人が作ったカードと同じく、SNSのURLもカードの中（左下）に出す。
                    snsLinks: user.effectiveSnsLinks,
                    fontFamily: user.effectiveFontDesign?.fontFamily,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final actions = [
      if (!_revealed)
        TextButton(
          onPressed: _busy ? null : () => _reveal(user),
          child: const Text('プロフィールを確認'),
        ),
      if (user.accountStatus != AccountStatus.pendingDeletion)
        OutlinedButton(
          onPressed: _busy ? null : () => _toggleSuspend(user),
          child: Text(isSuspended ? '停止を解除' : '停止'),
        ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('閉じる'),
      ),
    ];
    return _adminDialog(ref, title: title, content: content, actions: actions);
  }
}

/// 「プロフィールを確認」の理由の選択。記録されることを明示してから、理由が
/// 選ばれた時だけ結果を返す。
class _ReasonDialog extends ConsumerStatefulWidget {
  const _ReasonDialog({required this.seed});

  final String seed;

  @override
  ConsumerState<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends ConsumerState<_ReasonDialog> {
  _ProfileViewReason? _reason;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _adminDialog(
      ref,
      title: Text('@${widget.seed}のプロフィールを確認'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '住人が設定した個人のカードを表示します。必要な場合だけ確認してください。'
                'この操作は、理由とともに記録されます。',
              ),
              const SizedBox(height: 8),
              RadioGroup<_ProfileViewReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final r in _ProfileViewReason.values)
                      RadioListTile<_ProfileViewReason>(
                        value: r,
                        title: Text(r.label),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _noteController,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '補足（任意）'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop((reason: _reason!, note: _noteController.text.trim())),
          child: const Text('記録して表示'),
        ),
      ],
    );
  }
}
