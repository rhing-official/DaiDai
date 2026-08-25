import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, MultiFactorInfo;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/chat_layout_style.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../models/message_time_format.dart';
import '../../models/send_key_mode.dart';
import '../../models/sticker_send_mode.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/draft_sync_enabled_provider.dart';
import '../../providers/gekiga_background_color_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/sticker_send_mode_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../router/app_router.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/dessin/dessin_option_tile.dart';
import '../../theme/motion.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/color_hex.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/qr_scan_screen.dart';
import '../../widgets/swipe_gestures.dart';
import '../auth/two_factor_setup_dialog.dart';
import '../chat/announcement_screen.dart';
import '../chat/group_member_list_screen.dart';
import 'owned_sticker_packs_popup.dart';
import 'settings_accordion_section.dart';

/// 画面幅がこれ以上あれば、左にカテゴリ一覧（サイドバー）、右にそのカテゴリの
/// 内容を1ページにまとめて表示するDiscord設定風の2ペイン表示にする。
/// これ未満の狭い画面では、カテゴリ一覧→内容ページの1段だけドリルダウンする。
const _kSettingsSplitBreakpoint = 760.0;

/// サイドバーの幅。語らい一覧（`talks_tab.dart`）・身だしなみ
/// （`profile_tab.dart`）の各サイドバーと区切り線のx座標を揃えるため、
/// 3画面とも同じ260pxを使う（2026-08-14、240→260→250→260）。
const _kSettingsSidebarWidth = 260.0;

/// 設定タブ。サイドバーの階層は最上位カテゴリ（アカウント／アプリケーション／
/// 入力／通知）の1段だけに留め、それぞれの中身（旧: サブフォルダだった項目）は
/// カテゴリごとに1つの縦スクロールページへ、見出し付きセクションとしてまとめる
/// （Discordのアカウント設定ページの構成を参考にした。2026-07-24変更）。
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  /// 狭い画面のドリルダウンでのみ使う、選択中カテゴリのid。
  /// 広い画面では常に先頭（アカウント）を既定選択として表示する。
  String? _selectedId;

  /// カテゴリタップの共通ハンドラ。「運営」は中身のページ（`_SettingsPage`
  /// 経由の設定行一覧）を持たず、お知らせ画面を直接表示する。広い画面では
  /// 語らいの分割表示と同じく、カテゴリ一覧（サイドバー）を残したまま
  /// 右側の内容ペインへお知らせを表示する（下記build参照）ためselectedId
  /// を切り替えるだけでよいが、狭い画面ではその置き場（サイドバー）自体が
  /// 無いため、通常の語らい同様フルスクリーンでpushする（2026-08-12変更）。
  void _onCategorySelected(_SettingsCategory category) {
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;
    if (category.id == 'support' && !isWide) {
      ref
          .read(goRouterProvider)
          .push('/announcements', extra: widget.currentUser);
      return;
    }
    setState(() => _selectedId = category.id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final categories = _categories(strings, ref, widget.currentUser);
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;

    if (isWide) {
      final selected =
          _findCategoryById(categories, _selectedId) ?? categories.first;
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _kSettingsSidebarWidth,
              child: _CategoryList(
                categories: categories,
                selectedId: selected.id,
                onSelect: _onCategorySelected,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected.id == 'support'
                  ? AnnouncementScreen(currentUser: widget.currentUser)
                  : _SettingsPage(
                      child: Builder(builder: selected.pageBuilder),
                    ),
            ),
          ],
        ),
      );
    }

    final selected = _findCategoryById(categories, _selectedId);
    final selectedIndex = selected == null
        ? -1
        : categories.indexWhere((c) => c.id == selected.id);
    final nextCategory =
        selectedIndex >= 0 && selectedIndex < categories.length - 1
        ? categories[selectedIndex + 1]
        : null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: AnimatedSwitcher(
            duration: popSlideDuration,
            transitionBuilder: (child, animation) =>
                buildPopSlideTransition(animation, child),
            child: selected == null
                ? _CategoryList(
                    key: const ValueKey('settings-categories'),
                    categories: categories,
                    selectedId: null,
                    onSelect: _onCategorySelected,
                  )
                : _NarrowSettingsPage(
                    key: ValueKey(selected.id),
                    category: selected,
                    onBack: () => setState(() => _selectedId = null),
                    onNext: nextCategory == null
                        ? null
                        : () => setState(() => _selectedId = nextCategory.id),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 設定の最上位カテゴリ1つ分。中身は[pageBuilder]が1ページにまとめて描画する
/// （旧`_Node`のようなさらに深い階層は持たない）。
class _SettingsCategory {
  const _SettingsCategory({
    required this.id,
    required this.icon,
    required this.title,
    required this.pageBuilder,
  });

  final String id;
  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;
}

_SettingsCategory? _findCategoryById(
  List<_SettingsCategory> categories,
  String? id,
) {
  if (id == null) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

List<_SettingsCategory> _categories(
  Strings strings,
  WidgetRef ref,
  AppUser currentUser,
) {
  return [
    _SettingsCategory(
      id: 'account',
      icon: Icons.person_outline,
      title: strings.settingsFolderAccount,
      pageBuilder: (context) =>
          _AccountPage(strings: strings, currentUser: currentUser),
    ),
    _SettingsCategory(
      id: 'application',
      icon: Icons.tune,
      title: strings.settingsFolderApplication,
      pageBuilder: (context) => _ApplicationPage(strings: strings),
    ),
    _SettingsCategory(
      id: 'talk',
      icon: Icons.forum_outlined,
      title: strings.settingsFolderTalk,
      pageBuilder: (context) =>
          _TalkPage(strings: strings, currentUser: currentUser),
    ),
    _SettingsCategory(
      id: 'notifications',
      icon: Icons.notifications_outlined,
      title: strings.settingsFolderNotifications,
      pageBuilder: (context) =>
          _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
    _SettingsCategory(
      id: 'support',
      icon: Icons.support_agent_outlined,
      title: strings.settingsFolderSupport,
      // 選択時は_onCategorySelectedがページ遷移せず直接お知らせ画面へ
      // pushするため、このpageBuilderは実際には呼ばれない。
      pageBuilder: (context) => const SizedBox.shrink(),
    ),
  ];
}

/// カテゴリ一覧（サイドバー、または狭い画面での一覧画面）。
class _CategoryList extends ConsumerWidget {
  const _CategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_SettingsCategory> categories;
  final String? selectedId;
  final ValueChanged<_SettingsCategory> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GekigaJointedTileList(
          seeds: [for (final category in categories) category.title.hashCode],
          selectedFlags: [
            for (final category in categories) category.id == selectedId,
          ],
          children: [
            for (final category in categories)
              _FolderTile(
                icon: category.icon,
                title: category.title,
                selected: category.id == selectedId,
                trailingChevron: false,
                onTap: () => onSelect(category),
              ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final category in categories)
          _FolderTile(
            icon: category.icon,
            title: category.title,
            selected: category.id == selectedId,
            trailingChevron: false,
            onTap: () => onSelect(category),
          ),
      ],
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
    this.trailingChevron = true,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final bool trailingChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final trailingWidget = trailingChevron
        ? const Icon(Icons.chevron_right)
        : null;

    if (isGekiga) {
      // 外枠は呼び出し側（`_CategoryList`の`GekigaJointedTileList`）が
      // まとめて描くため、ここでは内容だけを返す（2026-08-04変更）。
      return GekigaTileContent(
        selected: selected,
        leading: Icon(icon),
        title: Text(title),
        trailing: trailingWidget,
        onTap: onTap,
      );
    }

    final foreground = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: colorScheme.surface,
        selectedTileColor: colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        selected: selected,
        selectedColor: colorScheme.onPrimary,
        iconColor: foreground,
        textColor: foreground,
        leading: Icon(icon),
        title: Text(title),
        trailing: trailingWidget,
        onTap: onTap,
      ),
    );
  }
}

/// 広い画面での内容ペイン。タイトルの下に、カテゴリの中身を1ページで表示する。
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 内容ペインが余った横幅いっぱいに広がると、ラベルと値の間の余白ばかりが
    // 目立ってしまう（項目が横に広がりすぎる）ため、読みやすい幅で頭打ちにする。
    // ConstrainedBoxは、親（Expanded）から渡されるtight制約をそのまま
    // enforce()すると自分のmaxWidthが無視される（tightな下限に引き上げられる）
    // ため、先にAlignでtight制約をloose制約に変換してから渡す必要がある。
    // サイドバーで既にカテゴリ名が選択表示されているため、ここでの
    // セクション名の見出しは重複表示になるとして削除した。
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: child,
        ),
      ),
    );
  }
}

/// 狭い画面でのドリルダウン先。戻る行＋カテゴリの中身（1ページ）。
class _NarrowSettingsPage extends StatelessWidget {
  const _NarrowSettingsPage({
    super.key,
    required this.category,
    required this.onBack,
    this.onNext,
  });

  final _SettingsCategory category;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // mainAxisSizeをmin指定にすると、内側のListView（例: _AccountPage）が
    // 無限の高さ制約を受けてクラッシュする。既定（max）のままExpandedで包む。
    // 右スワイプは常に一覧へ戻る（onPreviousを渡さないことでSwipeBackDetector
    // の既定フォールバック=onBackを使う）。戻る導線がスワイプに一本化された
    // ため、以前ここにあった「←＋カテゴリ名」の見出し行は表示しない。
    return SwipeBackDetector(
      onBack: onBack,
      onNext: onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: Builder(builder: category.pageBuilder))],
      ),
    );
  }
}

/// セクションの見出し。劇画スタイル時は黒地白文字のラベルチップにする
/// （2026-07-30、appUiStyleProviderを見るためConsumerWidget化。2026-08-05、
/// 見た目部分は`profile_tab.dart`の蔵・工房の見出しにも使う共通ウィジェット
/// `GekigaSectionHeader`へ切り出し、ここではpaddingのみ担う）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: GekigaSectionHeader(title),
    );
  }
}

/// ラベル＋値（読み取り専用、または「準備中」）の1行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// タップするとその場でアクションを実行する行（例: ログアウト）。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        label,
        style: destructive ? TextStyle(color: colorScheme.error) : null,
      ),
      onTap: onTap,
    );
  }
}

/// 2段階認証（TOTP）の状態表示・登録・解除を1行にまとめたもの
/// （2026-08-09追加）。`_InfoRow`のように現在の状態（有効/無効）を右側に
/// 出しつつ、`_ActionRow`のようにタップで操作できる。
class _TwoFactorRow extends ConsumerStatefulWidget {
  const _TwoFactorRow({required this.strings, required this.rhingId});

  final Strings strings;
  final String rhingId;

  @override
  ConsumerState<_TwoFactorRow> createState() => _TwoFactorRowState();
}

class _TwoFactorRowState extends ConsumerState<_TwoFactorRow> {
  late Future<List<MultiFactorInfo>> _factorsFuture;
  Timer? _errorBannerTimer;

  @override
  void initState() {
    super.initState();
    _factorsFuture = _loadFactors();
  }

  @override
  void dispose() {
    _errorBannerTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _factorsFuture = _loadFactors();
    });
  }

  // asyncでラップすることで、Firebaseが未初期化な環境（ウィジェットテスト等）
  // でauthRepositoryProviderの生成自体が同期的に例外を投げても、initState内で
  // 直接クラッシュせずFutureのエラーとして扱えるようにする（2026-08-09追加）。
  Future<List<MultiFactorInfo>> _loadFactors() async {
    return ref.read(authRepositoryProvider).getEnrolledFactors();
  }

  Future<void> _onTap(List<MultiFactorInfo> factors) async {
    final strings = widget.strings;
    if (factors.isEmpty) {
      final enrolled = await TwoFactorSetupDialog.show(context, widget.rhingId);
      if (enrolled == true && mounted) {
        _refresh();
      }
      return;
    }
    final confirmed = await _confirmDisableTwoFactor(context, strings);
    if (!confirmed || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).unenrollTotp(factors.first);
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      if (_isRequiresRecentLogin(e)) {
        _errorBannerTimer = showAutoDismissBanner(
          context,
          message: strings.twoFactorRequiresRecentLoginError,
          previousTimer: _errorBannerTimer,
          actions: [
            TextButton(
              onPressed: () {
                dismissAutoDismissBanner();
                _reauthenticateAndRetryUnenroll(factors.first, strings);
              },
              child: Text(strings.twoFactorReauthenticateButton),
            ),
          ],
        );
        return;
      }
      _errorBannerTimer = showAutoDismissBanner(
        context,
        message: '$e',
        previousTimer: _errorBannerTimer,
      );
    }
  }

  // Web版のfirebase_authプラグインでは、multiFactor関連の一部エラーが
  // FirebaseAuthException型に正しくマッピングされず素のExceptionとして
  // 飛んでくることがあるため、型チェックに加えてメッセージ文字列でも
  // requires-recent-loginを判定する（2026-08-09、実機で確認した挙動）。
  bool _isRequiresRecentLogin(Object error) {
    if (error is FirebaseAuthException &&
        error.code == 'requires-recent-login') {
      return true;
    }
    return error.toString().contains('requires-recent-login');
  }

  Future<void> _reauthenticateAndRetryUnenroll(
    MultiFactorInfo info,
    Strings strings,
  ) async {
    try {
      await ref.read(authRepositoryProvider).reauthenticate();
      await ref.read(authRepositoryProvider).unenrollTotp(info);
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      _errorBannerTimer = showAutoDismissBanner(
        context,
        message: '$e',
        previousTimer: _errorBannerTimer,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<MultiFactorInfo>>(
      future: _factorsFuture,
      builder: (context, snapshot) {
        final factors = snapshot.data;
        final statusText = factors == null
            ? '…'
            : (factors.isEmpty
                  ? strings.twoFactorDisabledStatus
                  : strings.twoFactorEnabledStatus);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(strings.settingsTwoFactor),
          trailing: Text(
            statusText,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          onTap: factors == null ? null : () => _onTap(factors),
        );
      },
    );
  }
}

/// QRコードによるログイン（ログイン済み端末側、2026-08-09追加）。タップすると
/// `QrScanScreen`でQRコードを読み取り、`daidai:qrlogin:`で始まる文字列であれば
/// 確認ダイアログを経てそのセッションを承認する（未ログイン端末側は
/// `lib/features/auth/qr_login_dialog.dart`のQrLoginDialog）。
class _QrLoginRow extends ConsumerWidget {
  const _QrLoginRow({required this.strings});

  final Strings strings;

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final startScan = await _confirmStartScan(context, strings);
    if (!startScan || !context.mounted) return;

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => QrScanScreen(title: strings.settingsQrLogin),
      ),
    );
    if (scanned == null || !context.mounted) return;

    const prefix = 'daidai:qrlogin:';
    if (!scanned.startsWith(prefix)) {
      showAutoDismissBanner(context, message: strings.qrLoginInvalidQrError);
      return;
    }
    final sessionId = scanned.substring(prefix.length);

    final confirmed = await _confirmApproveQrLogin(context, strings);
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(authRepositoryProvider).approveQrLoginSession(sessionId);
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: strings.qrLoginApproveError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionRow(
      label: strings.settingsQrLogin,
      onTap: () => _scan(context, ref),
    );
  }
}

/// カメラを開く前に「別の端末でQRコードが表示されている」という前提を
/// 説明する（2026-08-10追加）。この説明無しにいきなりカメラが起動すると、
/// 1台の端末だけで試したユーザーには「読み取るべきものが無いのにカメラだけ
/// 起動する」ように見え分かりにくいとの指摘を受けた。
Future<bool> _confirmStartScan(BuildContext context, Strings strings) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.settingsQrLogin),
      content: Text(strings.qrLoginScanInstructionMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.qrLoginScanInstructionButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> _confirmApproveQrLogin(
  BuildContext context,
  Strings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.qrLoginScanConfirmTitle),
      content: Text(strings.qrLoginScanConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.qrLoginScanConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 2段階認証を無効にする前の確認ダイアログ。
Future<bool> _confirmDisableTwoFactor(
  BuildContext context,
  Strings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.twoFactorDisableConfirmTitle),
      content: Text(strings.twoFactorDisableConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.twoFactorDisableConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// アカウントカテゴリの中身。旧: Rhing ID／プロフィール名／セキュリティ／
/// QRコードログイン／ログアウト／アカウント削除の各サブフォルダを、
/// 見出し付きセクションとして1ページにまとめた。
class _AccountPage extends ConsumerWidget {
  const _AccountPage({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionHeader(strings.settingsAccountInfoSection),
        _InfoRow(
          label: strings.settingsRhingIdLabel,
          value: '@${currentUser.rhingId}',
        ),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSecurity),
        _InfoRow(
          label: strings.settingsPassword,
          value: strings.settingsComingSoon,
        ),
        _TwoFactorRow(strings: strings, rhingId: currentUser.rhingId),
        _InfoRow(
          label: strings.settingsPasskey,
          value: strings.settingsComingSoon,
        ),
        _QrLoginRow(strings: strings),
        const Divider(height: 24),
        _SectionHeader(strings.settingsStickersSection),
        _ActionRow(
          label: strings.settingsManageOwnedStickers,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 400,
                  maxHeight: 640,
                ),
                child: OwnedStickerPacksPopup(userId: currentUser.userId),
              ),
            ),
          ),
        ),
        const Divider(height: 24),
        _ActionRow(
          label: strings.settingsLogout,
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
        _ActionRow(
          label: strings.settingsDeleteAccount,
          destructive: true,
          onTap: () async {
            if (!await _ensureNoOwnedGroups(context, ref, currentUser)) {
              return;
            }
            if (!context.mounted) return;
            final choice = await _showDeleteAccountDialog(context, strings);
            if (choice == null || !context.mounted) return;
            switch (choice) {
              case _DeleteAccountChoice.grace:
                await ref
                    .read(userRepositoryProvider)
                    .requestAccountDeletion(currentUser.userId);
              case _DeleteAccountChoice.immediate:
                await ref
                    .read(userRepositoryProvider)
                    .deleteAccountImmediately();
            }
            if (!context.mounted) return;
            await ref.read(authRepositoryProvider).signOut();
          },
        ),
      ],
    );
  }
}

/// 長を務める広場が1件でも残っている間はアカウントを削除させない
/// （2026-08-02追加）。無ければ即座にtrueを返し、あれば[_OwnerGroupsGuardDialog]
/// を開いて全て譲渡し終えるまで先へ進ませない。通常削除・即時削除どちらの
/// 入り口からも共通で呼ぶ。
Future<bool> _ensureNoOwnedGroups(
  BuildContext context,
  WidgetRef ref,
  AppUser currentUser,
) async {
  final groups = await ref
      .read(groupRepositoryProvider)
      .watchGroups(currentUser.userId)
      .first;
  final hasOwnedGroups = groups.any((g) => g.ownerId == currentUser.userId);
  if (!hasOwnedGroups) return true;
  if (!context.mounted) return false;
  return _OwnerGroupsGuardDialog.show(context, currentUser);
}

final _groupListProvider = StreamProvider.family<List<Group>, String>(
  (ref, userId) => ref.watch(groupRepositoryProvider).watchGroups(userId),
);

/// 長を務める広場の一覧・譲渡導線を出すダイアログ（2026-08-02追加）。
/// 各広場の「譲渡」から`GroupMemberListPopup`（メンバー一覧タップ→
/// プロフィールカードの「長を譲渡」ボタン、既存の譲渡導線と同じ）を開く。
/// 一覧はライブ購読のため、譲渡が完了すると自動的にその広場が消え、
/// 全て消えると「続ける」が押せるようになる。
class _OwnerGroupsGuardDialog extends ConsumerWidget {
  const _OwnerGroupsGuardDialog({required this.currentUser});

  final AppUser currentUser;

  /// trueが返れば、削除操作の続き（確認ダイアログ）へ進んでよいという合図。
  static Future<bool> show(BuildContext context, AppUser currentUser) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => _OwnerGroupsGuardDialog(currentUser: currentUser),
    );
    return proceed ?? false;
  }

  Future<void> _openTransfer(BuildContext context, WidgetRef ref, Group group) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 640),
          child: StreamBuilder<List<GroupRole>>(
            stream: ref.read(groupRepositoryProvider).watchRoles(group.groupId),
            builder: (context, snapshot) {
              final roles = snapshot.data ?? const <GroupRole>[];
              return GroupMemberListPopup(
                currentUser: currentUser,
                group: group,
                roles: roles,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final groups = ref.watch(_groupListProvider(currentUser.userId)).value;
    final ownedGroups = groups
        ?.where((g) => g.ownerId == currentUser.userId)
        .toList();

    return AlertDialog(
      title: Text(strings.accountDeleteOwnerGuardTitle),
      content: SizedBox(
        width: 360,
        child: ownedGroups == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ownedGroups.isEmpty
                        ? strings.accountDeleteOwnerGuardCleared
                        : strings.accountDeleteOwnerGuardMessage,
                  ),
                  const SizedBox(height: 8),
                  for (final group in ownedGroups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(group.name),
                      trailing: FilledButton(
                        onPressed: () => _openTransfer(context, ref, group),
                        child: Text(strings.groupTransferOwnershipMenuItem),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: (ownedGroups != null && ownedGroups.isEmpty)
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(strings.accountDeleteOwnerGuardContinue),
        ),
      ],
    );
  }
}

enum _DeleteAccountChoice { grace, immediate }

/// アカウント削除ボタンから開く選択ポップアップ（2026-08-11、それまでの
/// 「通常削除」「即時削除」2つの操作行＋各々の`AlertDialog`確認という
/// 2段階UIを、1つの選択ポップアップに統合）。「30日後に削除」「今すぐ削除」
/// （取り消せない旨をカード内に明記）「やめる」を縦に並べたカード形式で、
/// タップした時点でその場の1操作として確定する（従来のような2段階目の
/// 確認ダイアログは挟まない）。
Future<_DeleteAccountChoice?> _showDeleteAccountDialog(
  BuildContext context,
  Strings strings,
) {
  return showDialog<_DeleteAccountChoice>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.settingsDeleteAccountConfirmTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _DeleteAccountOptionCard(
                title: strings.settingsDeleteAccountGraceOption,
                subtitle: strings.settingsDeleteAccountGraceOptionSubtitle,
                onTap: () =>
                    Navigator.of(context).pop(_DeleteAccountChoice.grace),
              ),
              const SizedBox(height: 12),
              _DeleteAccountOptionCard(
                title: strings.settingsDeleteAccountImmediate,
                subtitle: strings.settingsDeleteAccountImmediateOptionSubtitle,
                destructive: true,
                onTap: () =>
                    Navigator.of(context).pop(_DeleteAccountChoice.immediate),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.settingsDeleteAccountCancelButton),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DeleteAccountOptionCard extends StatelessWidget {
  const _DeleteAccountOptionCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final String title;
  final String subtitle;
  final void Function() onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = destructive ? colorScheme.error : colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: destructive
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: destructive
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// アプリケーションカテゴリの中身。旧: 色／UI／文字／言語の各サブフォルダを
/// 1ページにまとめた。
class _ApplicationPage extends StatelessWidget {
  const _ApplicationPage({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _DesignFolder(strings: strings),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSubUI),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsUIDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        _UiStyleFolder(strings: strings),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSubTypography),
        _InfoRow(
          label: strings.settingsFontDesign,
          value: strings.settingsComingSoon,
        ),
        const Divider(height: 24),
        _LanguageFolder(strings: strings),
        const Divider(height: 24),
        _TimeFormatFolder(strings: strings),
      ],
    );
  }
}

class _DesignFolder extends ConsumerStatefulWidget {
  const _DesignFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<_DesignFolder> createState() => _DesignFolderState();
}

/// アクセントカラーのプリセット（8桁hex＝RRGGBBAA）。
const _kAccentColorPresets = ['F08300CC', '3D2EE0CC', '88B04Bdd'];

/// 劇画UIの背景色のプリセット（6桁hex＝RRGGBB、不透明）。ColorSchemeの
/// 種ではなく単色塗りつぶしの背景色として使うため、フラットUI側のような
/// 透過は付けない。先頭要素は`kDefaultGekigaBackgroundColor`
/// （`GekigaColors.background`）と同じ値にすること。
const _kGekigaBackgroundColorPresets = ['C1272D', 'F08300', '3D2EE0', '88B04B'];

class _DesignFolderState extends ConsumerState<_DesignFolder> {
  late final TextEditingController _hexController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: ref.read(accentColorProvider).toHexString().replaceFirst('#', ''),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHexInput() {
    final color = tryParseHexColor(_hexController.text);
    if (color == null) {
      setState(() => _errorText = '「#RRGGBB」の形式で入力してください');
      return;
    }
    setState(() => _errorText = null);
    final isGekiga = ref.read(appUiStyleProvider) == AppUiStyle.gekiga;
    if (isGekiga) {
      ref.read(gekigaBackgroundColorProvider.notifier).setColor(color);
    } else {
      ref.read(accentColorProvider.notifier).setColor(color);
    }
  }

  void _applyPreset(String hex) {
    final color = tryParseHexColor(hex);
    if (color == null) return;
    setState(() {
      _errorText = null;
      _hexController.text = hex.toUpperCase();
    });
    final isGekiga = ref.read(appUiStyleProvider) == AppUiStyle.gekiga;
    if (isGekiga) {
      ref.read(gekigaBackgroundColorProvider.notifier).setColor(color);
    } else {
      ref.read(accentColorProvider.notifier).setColor(color);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 同じ入力欄・プリセット一覧をフラットUIの`accentColorProvider`と
    // 劇画UIの`gekigaBackgroundColorProvider`で使い回しているため、
    // `_UiStyleFolder`（同じ`_ApplicationPage`内の兄弟）でスタイルを
    // 切り替えた瞬間に、表示中の値を新しく有効になった側のプロバイダの
    // 現在値へリセットする。build中に`_hexController`を直接書き換えると
    // GekigaTextField/TextFieldという別ウィジェット間の切り替え時に
    // タイミング次第で不安定になるため、`ref.listen`のコールバック内で
    // 安全にsetStateする。
    ref.listen<AppUiStyle>(appUiStyleProvider, (previous, next) {
      if (previous == next) return;
      final color = next == AppUiStyle.gekiga
          ? ref.read(gekigaBackgroundColorProvider)
          : ref.read(accentColorProvider);
      setState(() {
        _errorText = null;
        _hexController.text = color.toHexString().replaceFirst('#', '');
      });
    });

    final accentColor = ref.watch(accentColorProvider);
    final gekigaBackgroundColor = ref.watch(gekigaBackgroundColorProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final activeColor = isGekiga ? gekigaBackgroundColor : accentColor;
    final colorPresets = isGekiga
        ? _kGekigaBackgroundColorPresets
        : _kAccentColorPresets;

    void selectThemeMode(ThemeMode mode) =>
        ref.read(appThemeModeProvider.notifier).setMode(mode);

    final appearanceOptions = [
      (mode: ThemeMode.light, label: widget.strings.settingsAppearanceLight),
      (mode: ThemeMode.dark, label: widget.strings.settingsAppearanceDark),
      (mode: ThemeMode.system, label: widget.strings.settingsAppearanceSystem),
    ];

    final appearanceControl = isGekiga
        ? GekigaJointedTileList(
            seeds: [
              for (final option in appearanceOptions) option.mode.hashCode,
            ],
            selectedFlags: [
              for (final option in appearanceOptions) themeMode == option.mode,
            ],
            children: [
              for (final option in appearanceOptions)
                GekigaTileContent(
                  selected: themeMode == option.mode,
                  leading: Icon(
                    themeMode == option.mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option.label),
                  onTap: () => selectThemeMode(option.mode),
                ),
            ],
          )
        : RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) {
              if (value != null) selectThemeMode(value);
            },
            child: Column(
              children: [
                for (final option in appearanceOptions)
                  RadioListTile<ThemeMode>(
                    value: option.mode,
                    title: Text(option.label),
                  ),
              ],
            ),
          );

    final accentColorField = isGekiga
        ? GekigaTextField(
            controller: _hexController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(8),
            ],
            prefixText: '#',
            hintText: 'F08300',
            errorText: _errorText,
            suffixIcon: IconButton(
              icon: const Icon(Icons.check, color: GekigaColors.onPanel),
              onPressed: _applyHexInput,
            ),
            onSubmitted: (_) => _applyHexInput(),
          )
        : TextField(
            controller: _hexController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: InputDecoration(
              labelText: widget.strings.settingsColorCode,
              prefixText: '#',
              hintText: 'F08300',
              errorText: _errorText,
              counterText: '',
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: _applyHexInput,
              ),
            ),
            onSubmitted: (_) => _applyHexInput(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            widget.strings.settingsAppearance,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // 劇画UI選択中は外観（ライト/ダーク/端末に合わせる）を変更不可にする
        // （グレーアウト＋操作無効化）。GekigaThemeはthemeModeに関わらず
        // 常に同じ見た目を返す設計のため、この設定を変えても効果が無い
        // （2026-08-04追加、アクセントカラー欄と同じロックパターンを適用）。
        if (isGekiga)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              widget.strings.settingsAppearanceGekigaLockedHint,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        Opacity(
          opacity: isGekiga ? 0.4 : 1.0,
          child: IgnorePointer(
            ignoring: isGekiga,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: appearanceControl,
            ),
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            widget.strings.settingsAccentColor,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // 劇画UI選択中は「背景色」の意味で使う（フラットUIのようにColorScheme
        // 全体の種にはせず、背景のみを変更する。黒/白基調の他パーツは
        // 引き続き固定）。2026-08-05変更、以前はこの欄自体を劇画UI選択中は
        // 変更不可にしていた。
        if (isGekiga)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              widget.strings.settingsAccentColorGekigaHint,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: accentColorField),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.strings.settingsColorPresets,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final hex in colorPresets)
                        _PresetColorSwatch(
                          hex: hex,
                          selected: tryParseHexColor(hex) == activeColor,
                          onTap: () => _applyPreset(hex),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// アクセントカラーのプリセット1つ分の円形スウォッチ。タップで即適用する。
class _PresetColorSwatch extends StatelessWidget {
  const _PresetColorSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = tryParseHexColor(hex)!;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black12,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

/// 表示言語（日本語／English）をここで切り替える。以前はDaiDai独自用語の
/// 言い換えスタイル（世界観重視／利便性重視）もこの直下で切り替えられたが、
/// 「言語・用語設定によってブロックの大きさが変わるため、全てに対応するのが
/// 困難になった」ため2026-08-13に廃止し、世界観重視の用語へ一本化した
/// （[Vocabulary]参照）。
class _LanguageFolder extends ConsumerWidget {
  const _LanguageFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(appLocaleProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void selectLocale(AppLocale locale) =>
        ref.read(appLocaleProvider.notifier).setLocale(locale);

    final localeControl = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final locale in AppLocale.values) locale.hashCode],
            selectedFlags: [
              for (final locale in AppLocale.values) currentLocale == locale,
            ],
            children: [
              for (final locale in AppLocale.values)
                GekigaTileContent(
                  selected: currentLocale == locale,
                  leading: Icon(
                    currentLocale == locale
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(locale.label),
                  onTap: () => selectLocale(locale),
                ),
            ],
          )
        : RadioGroup<AppLocale>(
            groupValue: currentLocale,
            onChanged: (value) {
              if (value != null) selectLocale(value);
            },
            child: Column(
              children: [
                for (final locale in AppLocale.values)
                  RadioListTile<AppLocale>(
                    value: locale,
                    title: Text(locale.label),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.settingsDisplayLanguage,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: localeControl,
        ),
      ],
    );
  }
}

/// 語らいのメッセージ表示スタイルの切り替え。この設定は自分の端末での
/// 表示のみに影響し、相手の語らいの見え方には影響しない
/// （[ChatLayoutStyle]のコメント参照）。
/// UIスタイル（見た目）の切り替え（2026-07-29追加）。現時点では
/// メッセージ画面（`ChatScreen`）のみがこの値を見て見た目を変える。
class _UiStyleFolder extends ConsumerWidget {
  const _UiStyleFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final isGekiga = style == AppUiStyle.gekiga;

    void select(AppUiStyle value) =>
        ref.read(appUiStyleProvider.notifier).setStyle(value);

    // 劇画スタイル選択中は、この選択肢自体もギザギザ枠（選択中=白地黒字）
    // で表示する。選んだ瞬間に見た目が切り替わるので選択結果がそのまま
    // プレビューになる（2026-08-03、選択肢の見た目統一のため追加）。
    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [
          AppUiStyle.flat.hashCode,
          AppUiStyle.gekiga.hashCode,
          AppUiStyle.dessin.hashCode,
        ],
        selectedFlags: [
          style == AppUiStyle.flat,
          style == AppUiStyle.gekiga,
          style == AppUiStyle.dessin,
        ],
        children: [
          GekigaTileContent(
            selected: style == AppUiStyle.flat,
            leading: Icon(
              style == AppUiStyle.flat
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(strings.settingsUiStyleFlatLabel),
            subtitle: Text(strings.settingsUiStyleFlatDescription),
            onTap: () => select(AppUiStyle.flat),
          ),
          GekigaTileContent(
            selected: style == AppUiStyle.gekiga,
            leading: Icon(
              style == AppUiStyle.gekiga
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(strings.settingsUiStyleGekigaLabel),
            subtitle: Text(strings.settingsUiStyleGekigaDescription),
            onTap: () => select(AppUiStyle.gekiga),
          ),
          GekigaTileContent(
            selected: style == AppUiStyle.dessin,
            leading: Icon(
              style == AppUiStyle.dessin
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(strings.settingsUiStyleDessinLabel),
            subtitle: Text(strings.settingsUiStyleDessinDescription),
            onTap: () => select(AppUiStyle.dessin),
          ),
        ],
      );
    }

    // デッサンスタイル選択中は、この選択肢自体も紙質感の手描き枠
    // （選択中=紙の陰影地）で表示する（劇画スタイルと同じ「選択結果が
    // そのままプレビューになる」方針）。
    if (style == AppUiStyle.dessin) {
      return Column(
        children: [
          DessinOptionTile(
            selected: style == AppUiStyle.flat,
            title: strings.settingsUiStyleFlatLabel,
            subtitle: strings.settingsUiStyleFlatDescription,
            seed: AppUiStyle.flat.hashCode,
            onTap: () => select(AppUiStyle.flat),
          ),
          const SizedBox(height: 8),
          DessinOptionTile(
            selected: style == AppUiStyle.gekiga,
            title: strings.settingsUiStyleGekigaLabel,
            subtitle: strings.settingsUiStyleGekigaDescription,
            seed: AppUiStyle.gekiga.hashCode,
            onTap: () => select(AppUiStyle.gekiga),
          ),
          const SizedBox(height: 8),
          DessinOptionTile(
            selected: style == AppUiStyle.dessin,
            title: strings.settingsUiStyleDessinLabel,
            subtitle: strings.settingsUiStyleDessinDescription,
            seed: AppUiStyle.dessin.hashCode,
            onTap: () => select(AppUiStyle.dessin),
          ),
        ],
      );
    }

    return RadioGroup<AppUiStyle>(
      groupValue: style,
      onChanged: (value) {
        if (value != null) select(value);
      },
      child: Column(
        children: [
          RadioListTile<AppUiStyle>(
            value: AppUiStyle.flat,
            title: Text(strings.settingsUiStyleFlatLabel),
            subtitle: Text(strings.settingsUiStyleFlatDescription),
          ),
          RadioListTile<AppUiStyle>(
            value: AppUiStyle.gekiga,
            title: Text(strings.settingsUiStyleGekigaLabel),
            subtitle: Text(strings.settingsUiStyleGekigaDescription),
          ),
          RadioListTile<AppUiStyle>(
            value: AppUiStyle.dessin,
            title: Text(strings.settingsUiStyleDessinLabel),
            subtitle: Text(strings.settingsUiStyleDessinDescription),
          ),
        ],
      ),
    );
  }
}

class _ChatLayoutFolder extends ConsumerWidget {
  const _ChatLayoutFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(chatLayoutStyleProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(ChatLayoutStyle value) =>
        ref.read(chatLayoutStyleProvider.notifier).setStyle(value);

    final options = [
      (
        value: ChatLayoutStyle.sideBySide,
        title: strings.settingsChatLayoutSideBySide,
        subtitle: strings.settingsChatLayoutSideBySideDescription,
      ),
      (
        value: ChatLayoutStyle.allLeft,
        title: strings.settingsChatLayoutAllLeft,
        subtitle: strings.settingsChatLayoutAllLeftDescription,
      ),
    ];

    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final option in options) option.value.hashCode],
            selectedFlags: [
              for (final option in options) style == option.value,
            ],
            children: [
              for (final option in options)
                GekigaTileContent(
                  selected: style == option.value,
                  leading: Icon(
                    style == option.value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  onTap: () => select(option.value),
                ),
            ],
          )
        : RadioGroup<ChatLayoutStyle>(
            groupValue: style,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<ChatLayoutStyle>(
                    value: option.value,
                    title: Text(option.title),
                    subtitle: Text(option.subtitle),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsChatLayoutTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        control,
      ],
    );
  }
}

/// メッセージの送信時刻表示形式（24時間表記／12時間表記）の切り替え。
class _TimeFormatFolder extends ConsumerWidget {
  const _TimeFormatFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFormat = ref.watch(messageTimeFormatProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(MessageTimeFormat value) =>
        ref.read(messageTimeFormatProvider.notifier).setFormat(value);

    String label(MessageTimeFormat format) => format == MessageTimeFormat.h24
        ? strings.settingsTimeFormat24h
        : strings.settingsTimeFormat12h;

    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [
              for (final format in MessageTimeFormat.values) format.hashCode,
            ],
            selectedFlags: [
              for (final format in MessageTimeFormat.values)
                currentFormat == format,
            ],
            children: [
              for (final format in MessageTimeFormat.values)
                GekigaTileContent(
                  selected: currentFormat == format,
                  leading: Icon(
                    currentFormat == format
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(label(format)),
                  onTap: () => select(format),
                ),
            ],
          )
        : RadioGroup<MessageTimeFormat>(
            groupValue: currentFormat,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final format in MessageTimeFormat.values)
                  RadioListTile<MessageTimeFormat>(
                    value: format,
                    title: Text(label(format)),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.settingsTimeFormat,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: control,
        ),
      ],
    );
  }
}

/// 語らいカテゴリの中身。ブロックしたユーザーの一覧・解除、プロフィール
/// カードの割り当てに加え、2026-07-30にメッセージの表示・送信キー設定を
/// （それぞれアプリケーション・入力カテゴリから）ここへ統合した。
/// 送信キー設定はこの統合により旧「入力」カテゴリが空になったため廃止した。
class _TalkPage extends StatelessWidget {
  const _TalkPage({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionHeader(strings.settingsBlockedUsersTitle),
        _BlockedUsersFolder(strings: strings, currentUser: currentUser),
        const Divider(height: 24),
        _ChatLayoutFolder(strings: strings),
        const Divider(height: 24),
        _SendKeyFolder(strings: strings),
        const Divider(height: 24),
        SettingsAccordionSection(
          title: strings.settingsAdvancedSectionTitle,
          children: [
            _StickerSendModeFolder(strings: strings),
            const Divider(height: 24),
            _DraftSyncFolder(strings: strings),
          ],
        ),
      ],
    );
  }
}

/// ブロックしたユーザーの一覧＋解除ボタン。一対のハンバーガーメニューから
/// ブロックした相手（`users/{userId}/blockedUsers`）をここにまとめて表示する。
class _BlockedUsersFolder extends ConsumerWidget {
  const _BlockedUsersFolder({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String targetUserId,
  ) async {
    try {
      await ref
          .read(blockRepositoryProvider)
          .unblock(userId: currentUser.userId, targetUserId: targetUserId);
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: 'エラーが発生しました: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedIdsAsync = ref.watch(
      blockedUserIdsProvider(currentUser.userId),
    );

    return blockedIdsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('エラーが発生しました: $e'),
      ),
      data: (blockedIds) {
        if (blockedIds.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              strings.settingsBlockedUsersEmpty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return FutureBuilder<List<AppUser>>(
          future: ref
              .read(userRepositoryProvider)
              .getUsersByIds(blockedIds.toList()),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final blockedUsers = [...snapshot.data!]
              ..sort((a, b) => a.rhingId.compareTo(b.rhingId));
            return Column(
              children: [
                for (final user in blockedUsers)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: CircleAvatar(
                      backgroundImage: user.effectiveIcon?.url != null
                          ? NetworkImage(user.effectiveIcon!.url)
                          : null,
                      child: user.effectiveIcon?.url == null
                          ? Text(
                              user.rhingId.isNotEmpty
                                  ? user.rhingId[0].toUpperCase()
                                  : '?',
                            )
                          : null,
                    ),
                    title: Text('@${user.rhingId}'),
                    trailing: TextButton(
                      onPressed: () => _unblock(context, ref, user.userId),
                      child: Text(strings.settingsBlockedUsersUnblock),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SendKeyFolder extends ConsumerWidget {
  const _SendKeyFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(sendKeyModeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(SendKeyMode value) =>
        ref.read(sendKeyModeProvider.notifier).setMode(value);

    final options = [
      (
        value: SendKeyMode.enterToSend,
        title: strings.settingsSendKeyEnterToSend,
        subtitle: strings.settingsSendKeySilentEnterToSend,
      ),
      (
        value: SendKeyMode.ctrlEnterToSend,
        title: strings.settingsSendKeyCtrlEnterToSend,
        subtitle: strings.settingsSendKeySilentCtrlEnterToSend,
      ),
    ];

    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final option in options) option.value.hashCode],
            selectedFlags: [for (final option in options) mode == option.value],
            children: [
              for (final option in options)
                GekigaTileContent(
                  selected: mode == option.value,
                  leading: Icon(
                    mode == option.value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  onTap: () => select(option.value),
                ),
            ],
          )
        : RadioGroup<SendKeyMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<SendKeyMode>(
                    value: option.value,
                    title: Text(option.title),
                    subtitle: Text(option.subtitle),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            strings.settingsSendKeyTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        control,
      ],
    );
  }
}

/// ペタピタ（スタンプ）の送信方式（LINE型2タップ確認／Discord型1タップ即送信）
/// の選択。`_SendKeyFolder`と同じ2択ラジオ構成を踏襲する（2026-08-13追加）。
class _StickerSendModeFolder extends ConsumerWidget {
  const _StickerSendModeFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(stickerSendModeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(StickerSendMode value) =>
        ref.read(stickerSendModeProvider.notifier).setMode(value);

    final options = [
      (
        value: StickerSendMode.line,
        title: strings.settingsStickerSendModeLine,
        subtitle: strings.settingsStickerSendModeLineSubtitle,
      ),
      (
        value: StickerSendMode.discord,
        title: strings.settingsStickerSendModeDiscord,
        subtitle: strings.settingsStickerSendModeDiscordSubtitle,
      ),
    ];

    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final option in options) option.value.hashCode],
            selectedFlags: [for (final option in options) mode == option.value],
            children: [
              for (final option in options)
                GekigaTileContent(
                  selected: mode == option.value,
                  leading: Icon(
                    mode == option.value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  onTap: () => select(option.value),
                ),
            ],
          )
        : RadioGroup<StickerSendMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<StickerSendMode>(
                    value: option.value,
                    title: Text(option.title),
                    subtitle: Text(option.subtitle),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            strings.settingsStickerSendModeTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        control,
      ],
    );
  }
}

/// メッセージ入力欄の下書きを複数端末で同期するかのオン/オフ
/// （2026-08-13追加、標準オン）。
class _DraftSyncFolder extends ConsumerWidget {
  const _DraftSyncFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(draftSyncEnabledProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void setEnabled(bool value) =>
        ref.read(draftSyncEnabledProvider.notifier).setEnabled(value);

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: const [0],
        selectedFlags: [enabled],
        children: [
          GekigaTileContent(
            selected: enabled,
            title: Text(strings.settingsDraftSyncTitle),
            subtitle: Text(strings.settingsDraftSyncSubtitle),
            trailing: Switch(value: enabled, onChanged: setEnabled),
            onTap: () => setEnabled(!enabled),
          ),
        ],
      );
    }
    return SwitchListTile(
      value: enabled,
      title: Text(strings.settingsDraftSyncTitle),
      subtitle: Text(strings.settingsDraftSyncSubtitle),
      onChanged: setEnabled,
    );
  }
}

class _ComingSoonFolder extends StatelessWidget {
  const _ComingSoonFolder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
