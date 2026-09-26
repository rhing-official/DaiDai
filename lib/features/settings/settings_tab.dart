import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, MultiFactorInfo;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/font_design.dart';
import '../../models/app_user.dart';
import '../../models/chat_layout_style.dart';
import '../../models/custom_sound_upload.dart';
import '../../models/talks_list_layout_style.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../models/message_time_format.dart';
import '../../models/send_key_mode.dart';
import '../../models/sound_preset.dart';
import '../../models/sticker_send_mode.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/calling_sound_provider.dart';
import '../../providers/custom_accent_colors_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/font_design_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/talks_list_layout_style_provider.dart';
import '../../providers/draft_sync_enabled_provider.dart';
import '../../providers/gekiga_background_color_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/removed_default_color_presets_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/notification_sound_provider.dart';
import '../../providers/ringtone_sound_provider.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/sticker_send_mode_provider.dart';
import '../../providers/text_color_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../services/google_calendar_auth_service.dart';
import '../../services/google_calendar_link_coordinator.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/glass/glass_colors.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/color_hex.dart';
import '../../utils/platform_info.dart';
import '../../utils/sound_upload.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/interactive_swipe_back.dart';
import '../../widgets/qr_scan_screen.dart';
import '../../widgets/slide_drilldown.dart';
import '../auth/passcode_setup_dialog.dart';
import '../auth/two_factor_setup_dialog.dart';
import '../chat/announcement_screen.dart';
import '../chat/group_member_list_screen.dart';
import 'owned_sticker_packs_popup.dart';
import 'passkey_management_dialog.dart';
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

  /// 運営カテゴリの中からさらに1段階下の「アプリについて」を表示中か
  /// （2026-09-15追加）。以前は`_AboutPage`を独立した`MaterialPageRoute`で
  /// pushしていたため、サイドバー・区切り線ごと覆い隠し、スワイプで戻る
  /// 操作も効かなかった。カテゴリ一覧⇄カテゴリの中身と同じ
  /// `SlideDrilldown`の仕組みをもう1段だけ使い回すことで両方を解消する
  /// （`build`参照。専用の入れ子`SlideDrilldown`を使わないのは、
  /// `InteractiveSwipeBackTransition`の水平ドラッグ`GestureDetector`を
  /// 親子で二重に重ねるとジェスチャーアリーナで競合しかねないため）。
  bool _showAbout = false;

  /// 「アプリについて」の中からさらに1段階下の「オープンソースライセンス」を
  /// 表示中か（2026-09-15追加）。以前は`showLicensePage`（Flutter SDK標準）
  /// が独立した`MaterialPageRoute`でpushしていたため、サイドバー・区切り線
  /// ごと覆い隠し、スワイプで戻る操作も効かなかった。`_showAbout`と同じ
  /// 仕組みをもう1段だけ使い回すことで両方を解消する（`build`参照）。
  bool _showLicenses = false;

  /// 運営カテゴリの中からさらに1段階下の「お知らせ」を表示中か
  /// （2026-09-15追加）。以前はgo_routerの`/announcements`ルートへ
  /// `push`していたため、サイドバー・区切り線ごと覆い隠していた
  /// （スワイプで戻る操作自体は`slideDetailPage`側で既に機能していたが、
  /// サイドバーが消える点は`_showAbout`と同じ問題を抱えていた）。
  bool _showAnnouncements = false;

  /// カテゴリタップの共通ハンドラ。広い画面はサイドバーが常設のため、
  /// 「アプリについて」表示中でも別カテゴリをクリックできてしまう——
  /// その場合は`_showAbout`等も一緒にリセットする（2026-09-15追加）。
  void _onCategorySelected(_SettingsCategory category) {
    setState(() {
      _selectedId = category.id;
      _showAbout = false;
      _showLicenses = false;
      _showAnnouncements = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final categories = _categories(
      strings,
      ref,
      widget.currentUser,
      () => setState(() => _showAbout = true),
      () => setState(() => _showAnnouncements = true),
    );
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;

    if (isWide) {
      final selected =
          _findCategoryById(categories, _selectedId) ?? categories.first;

      // サポート→アプリについて→オープンソースライセンス／お知らせという
      // 下位階層は、下の狭い画面向け分岐と同じ`master`/`detail`を組み立てて
      // `SlideDrilldown`で包む（2026-09-18追加）。以前はここで対象の
      // ウィジェットへ直接差し替えるだけだったため、サイドバーは常に
      // 見えたままだったものの、タブレット等サイドバー常設幅の端末では
      // スワイプで戻る手段が無かった（スマホ幅だけスワイプできる食い違い
      // があった）。サイドバー・区切り線はこの分岐の外にあるため、
      // 下位階層表示中も常に見えたままになる点は変わらない。
      Widget? wideMaster;
      Widget? wideDetail;
      Object? wideDetailKey;
      VoidCallback? wideOnBack;
      if (_showLicenses) {
        wideMaster = _AboutPageContent(
          strings: strings,
          onOpenLicenses: () => setState(() => _showLicenses = true),
        );
        wideDetail = const _LicensePageContent();
        wideDetailKey = 'licenses';
        wideOnBack = () => setState(() => _showLicenses = false);
      } else if (_showAbout) {
        wideMaster = Builder(
          builder: (context) => _SupportPage(
            strings: strings,
            currentUser: widget.currentUser,
            onOpenAbout: () => setState(() => _showAbout = true),
            onOpenAnnouncements: () =>
                setState(() => _showAnnouncements = true),
          ),
        );
        wideDetail = _AboutPageContent(
          strings: strings,
          onOpenLicenses: () => setState(() => _showLicenses = true),
        );
        wideDetailKey = 'about';
        wideOnBack = () => setState(() => _showAbout = false);
      } else if (_showAnnouncements) {
        wideMaster = Builder(
          builder: (context) => _SupportPage(
            strings: strings,
            currentUser: widget.currentUser,
            onOpenAbout: () => setState(() => _showAbout = true),
            onOpenAnnouncements: () =>
                setState(() => _showAnnouncements = true),
          ),
        );
        wideDetail = AnnouncementScreen(currentUser: widget.currentUser);
        wideDetailKey = 'announcements';
        wideOnBack = () => setState(() => _showAnnouncements = false);
      }

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
              child: _SettingsPage(
                // オープンソースライセンス画面だけは頭打ちを外し、Flutter
                // 標準の`LicensePage`が内蔵する840px以上での左右並列表示
                // （パッケージ一覧⇄ライセンス本文）が働く余地を残す
                // （2026-09-18追加、詳細は`_LicensePageContent`参照）。
                maxWidth: _showLicenses ? double.infinity : 640,
                child: wideMaster == null
                    ? Builder(builder: selected.pageBuilder)
                    : SlideDrilldown(
                        master: wideMaster,
                        detail: wideDetail,
                        detailKey: wideDetailKey,
                        onBack: wideOnBack!,
                      ),
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

    final Widget master;
    final Widget? detail;
    final Object? detailKey;
    final VoidCallback onBack;
    final VoidCallback? onNext;
    if (_showLicenses) {
      // 「オープンソースライセンス」からスワイプで戻ると、「アプリに
      // ついて」自身が現れるようにする（2026-09-15追加）。
      master = _AboutPageContent(
        strings: strings,
        onOpenLicenses: () => setState(() => _showLicenses = true),
      );
      detail = const _LicensePageContent();
      detailKey = 'licenses';
      onBack = () => setState(() => _showLicenses = false);
      onNext = null;
    } else if (_showAbout) {
      // 「アプリについて」からスワイプで戻ると、トップのカテゴリ一覧
      // ではなく運営自身の一覧が現れるようにする（2026-09-15追加）。
      master = Builder(
        builder: (context) => _SupportPage(
          strings: strings,
          currentUser: widget.currentUser,
          onOpenAbout: () => setState(() => _showAbout = true),
          onOpenAnnouncements: () => setState(() => _showAnnouncements = true),
        ),
      );
      detail = _AboutPageContent(
        strings: strings,
        onOpenLicenses: () => setState(() => _showLicenses = true),
      );
      detailKey = 'about';
      onBack = () => setState(() => _showAbout = false);
      onNext = null;
    } else if (_showAnnouncements) {
      // 「お知らせ」からスワイプで戻ると、運営自身の一覧が現れるように
      // する（2026-09-15追加。以前はgo_routerの別ルートに積んでいた）。
      master = Builder(
        builder: (context) => _SupportPage(
          strings: strings,
          currentUser: widget.currentUser,
          onOpenAbout: () => setState(() => _showAbout = true),
          onOpenAnnouncements: () => setState(() => _showAnnouncements = true),
        ),
      );
      detail = AnnouncementScreen(currentUser: widget.currentUser);
      detailKey = 'announcements';
      onBack = () => setState(() => _showAnnouncements = false);
      onNext = null;
    } else {
      master = _CategoryList(
        key: const ValueKey('settings-categories'),
        categories: categories,
        selectedId: null,
        onSelect: _onCategorySelected,
        large: true,
      );
      detail = selected == null
          ? null
          : _NarrowSettingsPage(category: selected);
      detailKey = selected?.id;
      onBack = () => setState(() => _selectedId = null);
      onNext = nextCategory == null
          ? null
          : () => setState(() => _selectedId = nextCategory.id);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: SlideDrilldown(
            master: master,
            detail: detail,
            detailKey: detailKey,
            onBack: onBack,
            onNext: onNext,
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
  VoidCallback onOpenAbout,
  VoidCallback onOpenAnnouncements,
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
          _NotificationsPage(strings: strings, currentUser: currentUser),
    ),
    _SettingsCategory(
      id: 'support',
      icon: Icons.support_agent_outlined,
      title: strings.settingsFolderSupport,
      pageBuilder: (context) => _SupportPage(
        strings: strings,
        currentUser: currentUser,
        onOpenAbout: onOpenAbout,
        onOpenAnnouncements: onOpenAnnouncements,
      ),
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
    this.large = false,
  });

  final List<_SettingsCategory> categories;
  final String? selectedId;
  final ValueChanged<_SettingsCategory> onSelect;

  /// 狭い画面（モバイル）でこの一覧が画面全体を占めるときに、行を大きく
  /// 見やすくするか（2026-08-27追加、劇画UIのみ対象）。広い画面の
  /// サイドバー表示時は`false`のまま従来通りのサイズを保つ。
  final bool large;

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
                large: large,
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
    this.large = false,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final bool trailingChevron;
  final VoidCallback onTap;

  /// 狭い画面でこの一覧が画面全体を占めるときに行を大きくするか
  /// （2026-08-27追加、劇画UIのみ対象。[_CategoryList.large]参照）。
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final trailingWidget = trailingChevron
        ? const Icon(Icons.chevron_right)
        : null;

    if (isGlass) {
      // 選択・非選択で文字色は変えない（背景の塗りだけで選択状態を表す、
      // 2026-08-29変更）。
      final foreground = colorScheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(12),
          accentColorOverride: selected ? colorScheme.primary : null,
          child: Material(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.45)
                : Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              selected: selected,
              selectedColor: foreground,
              iconColor: foreground,
              textColor: foreground,
              leading: Icon(icon),
              title: Text(title),
              trailing: trailingWidget,
              onTap: onTap,
            ),
          ),
        ),
      );
    }

    if (isGekiga) {
      // 外枠は呼び出し側（`_CategoryList`の`GekigaJointedTileList`）が
      // まとめて描くため、ここでは内容だけを返す（2026-08-04変更）。
      return GekigaTileContent(
        selected: selected,
        leading: Icon(icon, size: large ? 32 : null),
        title: Text(title),
        trailing: trailingWidget,
        contentPadding: large
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 26)
            : null,
        titleFontSize: large ? 20 : null,
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
  const _SettingsPage({required this.child, this.maxWidth = 640});

  final Widget child;

  /// 内容ペインの頭打ち幅。既定は640（下記コメント参照）。オープンソース
  /// ライセンス画面はFlutter標準の`LicensePage`が内蔵する840px以上での
  /// 左右並列表示（パッケージ一覧⇄ライセンス本文）を働かせたいため、
  /// `double.infinity`を渡して頭打ちを外す（2026-09-18追加）。
  final double maxWidth;

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
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: child,
        ),
      ),
    );
  }
}

/// 狭い画面でのドリルダウン先。カテゴリの中身（1ページ）のみを持つ。
/// 戻る／次へのスワイプ処理は`SlideDrilldown`側が担う
/// （2026-09-12、`SwipeBackDetector`直接ラップから移行）。
class _NarrowSettingsPage extends StatelessWidget {
  const _NarrowSettingsPage({required this.category});

  final _SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    // mainAxisSizeをmin指定にすると、内側のListView（例: _AccountPage）が
    // 無限の高さ制約を受けてクラッシュする。既定（max）のままExpandedで包む。
    // 戻る導線がスワイプに一本化されたため、以前ここにあった
    // 「←＋カテゴリ名」の見出し行は表示しない。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: Builder(builder: category.pageBuilder))],
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: destructive ? DestructiveLabel(label) : Text(label),
      onTap: onTap,
    );
  }
}

/// 2段階認証（TOTP）の状態表示・登録・解除を1行にまとめたもの
/// （2026-08-09追加）。`_InfoRow`のように現在の状態（有効/無効）を右側に
/// 出しつつ、`_ActionRow`のようにタップで操作できる。
class _TwoFactorRow extends ConsumerStatefulWidget {
  const _TwoFactorRow({required this.strings, required this.rhingSeed});

  final Strings strings;
  final String rhingSeed;

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
      final enrolled = await TwoFactorSetupDialog.show(
        context,
        widget.rhingSeed,
      );
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
      slideBackRoute<String>(
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
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.settingsQrLogin);
      final content = Text(strings.qrLoginScanInstructionMessage);
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.qrLoginScanInstructionButton),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}

/// アクセントカラーのプリセットを削除する前の確認ダイアログ
/// （`_AccentColorFolderState`の「プリセット」長押し、2026-08-29追加。
/// 2026-09-15、固定プリセット・ユーザー登録色の両方を統合した「プリセット」
/// 1セクションの削除確認に使うよう拡張し`_confirmDeleteCustomColor`から
/// 改名）。
Future<bool> _confirmDeletePresetColor(
  BuildContext context,
  Strings strings,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.settingsCustomColorDeleteConfirmTitle);
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.settingsCustomColorDeleteConfirmButton),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, actions: actions)
          : AlertDialog(title: title, actions: actions);
    },
  );
  return confirmed ?? false;
}

Future<bool> _confirmApproveQrLogin(
  BuildContext context,
  Strings strings,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.qrLoginScanConfirmTitle);
      final content = Text(strings.qrLoginScanConfirmMessage);
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.qrLoginScanConfirmButton),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}

/// 2段階認証を無効にする前の確認ダイアログ。
Future<bool> _confirmDisableTwoFactor(
  BuildContext context,
  Strings strings,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.twoFactorDisableConfirmTitle);
      final content = Text(strings.twoFactorDisableConfirmMessage);
      final actions = [
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
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}

/// Googleカレンダー連携の状態表示・切り替え行（2026-09-01追加）。初回確認は
/// `_CalendarButton`（`chat_panes.dart`、カレンダー機能を初めて開いたとき）が
/// 主導線で、ここは後からいつでも許可/停止を切り替えるための副導線
/// （ユーザー確定仕様）。
class _GoogleCalendarSyncRow extends ConsumerWidget {
  const _GoogleCalendarSyncRow({
    required this.strings,
    required this.currentUser,
  });

  final Strings strings;
  final AppUser currentUser;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      final calendarId = await GoogleCalendarLinkCoordinator().connect();
      if (calendarId == null) return;
      await ref
          .read(userRepositoryProvider)
          .setGoogleCalendarSyncEnabled(
            currentUser.userId,
            true,
            calendarId: calendarId,
          );
    } on GoogleCalendarNotConfiguredException {
      if (!context.mounted) return;
      showAutoDismissBanner(
        context,
        message: strings.calendarSyncSetupIncompleteError,
      );
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: '$e');
    }
  }

  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref,
    String? calendarId,
  ) async {
    final confirmed = await _confirmDisconnectGoogleCalendarSync(
      context,
      strings,
    );
    if (!confirmed || !context.mounted) return;
    await GoogleCalendarLinkCoordinator().disconnect(calendarId);
    await ref
        .read(userRepositoryProvider)
        .setGoogleCalendarSyncEnabled(currentUser.userId, false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `currentUser`はログイン時の一度きりのスナップショットで、Firestore
    // 書き込み後も自動更新されない（`chat_panes.dart`の`_CalendarButton`と
    // 同じ既知の制約）。トグルは押した直後に見た目が反映されないと壊れて
    // 見えるため、`watchedUserProvider`で最新値を購読する。
    final liveUser = ref.watch(watchedUserProvider(currentUser.userId));
    final enabled =
        liveUser.asData?.value?.googleCalendarSyncEnabled ??
        currentUser.googleCalendarSyncEnabled ??
        false;
    final calendarId =
        liveUser.asData?.value?.googleCalendarId ??
        currentUser.googleCalendarId;
    // `enabled`のみで判定すると、旧スコープ時代に連携済みだったが専用
    // カレンダー未作成の「壊れた」状態（`chat_panes.dart`の`_CalendarButton.
    // _googleCalendarId`ドキュメントコメント参照）でもON表示のままになり、
    // 実際には同期が一切機能していないことに気づけない。calendarIdの有無も
    // 合わせて判定することで、壊れた状態ではOFF表示にし、ユーザーがONへ
    // 切り替える操作（`setEnabled(true)`）がそのまま再連携の自己修復導線に
    // なるようにする（2026-09-23追加）。
    final showConnected = enabled && calendarId != null;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final title = Text(
      showConnected
          ? strings.settingsGoogleCalendarSyncConnectedLabel
          : strings.settingsGoogleCalendarSyncDisconnectedLabel,
    );

    void setEnabled(bool value) =>
        value ? _connect(context, ref) : _disconnect(context, ref, calendarId);

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: const [0],
        selectedFlags: const [false],
        children: [
          GekigaTileContent(
            selected: false,
            title: title,
            trailing: Switch(
              value: showConnected,
              onChanged: setEnabled,
              activeThumbColor: GekigaColors.panel,
              activeTrackColor: GekigaColors.onPanel,
              inactiveThumbColor: GekigaColors.onPanel,
              inactiveTrackColor: GekigaColors.panel,
              trackOutlineColor: WidgetStatePropertyAll(GekigaColors.onPanel),
            ),
            onTap: () => setEnabled(!showConnected),
          ),
        ],
      );
    }
    return SwitchListTile(
      value: showConnected,
      title: title,
      onChanged: setEnabled,
    );
  }
}

/// Googleカレンダー連携を解除する前の確認ダイアログ（[_confirmDisableTwoFactor]
/// と同じGlass対応パターン）。
Future<bool> _confirmDisconnectGoogleCalendarSync(
  BuildContext context,
  Strings strings,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(
        strings.settingsGoogleCalendarSyncDisconnectConfirmTitle,
      );
      final content = Text(
        strings.settingsGoogleCalendarSyncDisconnectConfirmMessage,
      );
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.settingsGoogleCalendarSyncDisconnectAction),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}

/// 運営（サポート）カテゴリの中身。以前は「サポート」タップで直接
/// お知らせ画面へ遷移していたが、バージョン情報・規約類の参照ページ
/// （アプリについて）を置く場所として他カテゴリと同じ一覧構成に
/// 変更した（2026-09-14追加）。
class _SupportPage extends ConsumerWidget {
  const _SupportPage({
    required this.strings,
    required this.currentUser,
    required this.onOpenAbout,
    required this.onOpenAnnouncements,
  });

  final Strings strings;
  final AppUser currentUser;

  /// 「アプリについて」タップ時の処理（2026-09-15追加）。以前はここで
  /// `Navigator.push`していたが、サイドバー・区切り線を覆い隠しスワイプ
  /// 戻るも効かない問題があったため、`_SettingsTabState`側の状態
  /// （`_showAbout`）を切り替えるだけにし、実際の表示はそちら側の
  /// `SlideDrilldown`/`_SettingsPage`に任せる。
  final VoidCallback onOpenAbout;

  /// 「お知らせ」タップ時の処理（2026-09-15追加）。以前はここで
  /// go_routerの`/announcements`ルートへ`push`していたが、サイドバー・
  /// 区切り線を覆い隠す問題があったため（スワイプ戻る自体はgo_router側の
  /// `slideDetailPage`で既に機能していた）、`onOpenAbout`と同じく
  /// `_SettingsTabState`側の状態（`_showAnnouncements`）を切り替える
  /// だけにする。
  final VoidCallback onOpenAnnouncements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _ActionRow(
          label: strings.settingsAnnouncements,
          onTap: onOpenAnnouncements,
        ),
        _ActionRow(label: strings.settingsAboutApp, onTap: onOpenAbout),
      ],
    );
  }
}

const _termsUrl = 'https://rhing.jp/legal/terms';
const _privacyPolicyUrl = 'https://rhing.jp/legal/privacy';
const _disclaimerUrl = 'https://rhing.jp/legal/disclaimer';

Future<void> _openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// アプリについて（バージョン・利用規約・プライバシーポリシー・
/// 免責事項・オープンソースライセンス）。規約・プライバシーポリシー・
/// 免責事項の本文はHomePage-Rhing側（`_termsUrl`等）に既に用意されている
/// ため複製せず、外部リンクとして扱う（2026-09-14追加）。以前は独自の
/// `Scaffold`＋`AppBar`を持つ`_AboutPage`として`Navigator.push`していたが、
/// サイドバー・区切り線を覆い隠しスワイプ戻るも効かなかったため、
/// 中身だけを持つこのウィジェットに置き換え、`_SettingsTabState`が
/// 他カテゴリの中身と同じ`_SettingsPage`/`SlideDrilldown`のdetailスロットに
/// 埋め込む（2026-09-15変更）。
class _AboutPageContent extends StatefulWidget {
  const _AboutPageContent({
    required this.strings,
    required this.onOpenLicenses,
  });

  final Strings strings;

  /// 「オープンソースライセンス」タップ時の処理（2026-09-15追加）。以前は
  /// ここでFlutter SDK標準の`showLicensePage`を呼び、独立した
  /// `MaterialPageRoute`でpushしていたが、サイドバー・区切り線を覆い隠し
  /// スワイプ戻るも効かない問題があったため、`onOpenAbout`と同じく
  /// `_SettingsTabState`側の状態（`_showLicenses`）を切り替えるだけにする。
  final VoidCallback onOpenLicenses;

  @override
  State<_AboutPageContent> createState() => _AboutPageContentState();
}

class _AboutPageContentState extends State<_AboutPageContent> {
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _InfoRow(
              label: strings.settingsAppVersion,
              value: info == null
                  ? ''
                  : '${info.version} (${info.buildNumber})',
            ),
            const Divider(height: 24),
            _ActionRow(
              label: strings.settingsTermsOfService,
              onTap: () => _openExternalUrl(_termsUrl),
            ),
            _ActionRow(
              label: strings.settingsPrivacyPolicy,
              onTap: () => _openExternalUrl(_privacyPolicyUrl),
            ),
            _ActionRow(
              label: strings.settingsDisclaimer,
              onTap: () => _openExternalUrl(_disclaimerUrl),
            ),
            const Divider(height: 24),
            _ActionRow(
              label: strings.settingsOpenSourceLicenses,
              onTap: widget.onOpenLicenses,
            ),
          ],
        );
      },
    );
  }
}

/// オープンソースライセンス一覧（2026-09-15変更）。以前は`showLicensePage`が
/// アプリ全体のNavigatorへフルスクリーンでpushしていたため、サイドバー・
/// 区切り線ごと覆い隠し、スワイプで戻る操作も効かなかった。`LicensePage`
/// 自体はFlutter標準のものをそのまま使いつつ、専用のローカル`Navigator`で
/// 包むことでパッケージ詳細へのpushをこのdetailスロット内に閉じ込め、
/// 外側（「アプリについて」への復帰）は`_SettingsTabState._showLicenses`の
/// トグル＋既存の`SlideDrilldown`/`InteractiveSwipeBackTransition`に任せる。
class _LicensePageContent extends StatefulWidget {
  const _LicensePageContent();

  @override
  State<_LicensePageContent> createState() => _LicensePageContentState();
}

class _LicensePageContentState extends State<_LicensePageContent> {
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const SizedBox.shrink();
        }
        return Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (context) => LicensePage(
              applicationName: 'DaiDai',
              applicationVersion: info.version,
            ),
          ),
        );
      },
    );
  }
}

/// アカウントカテゴリの中身。旧: Rhing Seed／プロフィール名／セキュリティ／
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
          label: strings.settingsRhingSeedLabel,
          value: '@${currentUser.rhingSeed}',
        ),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSecurity),
        _TwoFactorRow(strings: strings, rhingSeed: currentUser.rhingSeed),
        _ActionRow(
          label: strings.settingsPasskey,
          onTap: () => PasskeyManagementDialog.show(context),
        ),
        _QrLoginRow(strings: strings),
        const Divider(height: 24),
        _SectionHeader(strings.settingsGoogleCalendarSyncSectionTitle),
        _GoogleCalendarSyncRow(strings: strings, currentUser: currentUser),
        const Divider(height: 24),
        _SectionHeader(strings.settingsStickersSection),
        _ActionRow(
          label: strings.settingsManageOwnedStickers,
          onTap: () {
            final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
            final content = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
              child: OwnedStickerPacksPopup(userId: currentUser.userId),
            );
            showDialog<void>(
              context: context,
              // ガラスUIでは素の`Dialog`だと背景・`Card`とも透明になり
              // ダイアログの輪郭自体が見えなくなっていた（2026-09-14修正、
              // 中のカードがポップアップと同色で視認性を欠くという報告の
              // 調査で判明。`GlassAlertDialog`と同じ「透明なDialog＋
              // GlassSurfaceで縁取り」パターンを踏襲）。
              builder: (_) => isGlass
                  ? Dialog(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      child: GlassSurface(
                        variant: GlassVariant.floating,
                        borderRadius: BorderRadius.circular(24),
                        child: content,
                      ),
                    )
                  : Dialog(child: content),
            );
          },
        ),
        const Divider(height: 24),
        _ActionRow(
          label: strings.settingsLogout,
          onTap: () async {
            await ref
                .read(pushNotificationRepositoryProvider)
                .unregisterCurrentToken(currentUser.userId);
            await ref.read(authRepositoryProvider).signOut();
          },
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
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    final title = Text(strings.accountDeleteOwnerGuardTitle);
    final content = SizedBox(
      width: 360,
      child: ownedGroups == null
          ? const SizedBox.shrink()
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
    );
    final actions = [
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
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
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
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
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
              destructive
                  ? DestructiveLabel(title, style: titleStyle)
                  : Text(
                      title,
                      style: titleStyle?.copyWith(color: colorScheme.onSurface),
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
class _ApplicationPage extends ConsumerWidget {
  const _ApplicationPage({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「フォントカラー」（旧・文字色）は劇画スタイル選択中は対象外
    // （固定モノクロ配色のため、`_TextColorFolder`参照）。以前は
    // `_DesignFolder`内に埋め込まれていたが、2026-09-15にUIスタイルと
    // フォントデザインの間へ独立させた。
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _AppearanceFolder(strings: strings),
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
        _AccentColorFolder(strings: strings),
        const Divider(height: 24),
        if (!isGekiga) ...[const _TextColorFolder(), const Divider(height: 24)],
        _SectionHeader(strings.settingsFontDesign),
        _FontDesignFolder(strings: strings),
        const Divider(height: 24),
        _LanguageFolder(strings: strings),
        const Divider(height: 24),
        _TimeFormatFolder(strings: strings),
        const Divider(height: 24),
        _PasscodeLockFolder(strings: strings),
      ],
    );
  }
}

/// 外観（ライト/ダーク/端末に合わせる）の選択（2026-09-15、`_DesignFolder`
/// から分離。以前はアクセントカラーと同じウィジェット内にまとめていたが、
/// 設定画面の項目順を「外観→UI→アクセントカラー→…」に揃えるため、
/// UIスタイル選択（`_UiStyleFolder`）を挟んで別ウィジェットにした）。
class _AppearanceFolder extends ConsumerWidget {
  const _AppearanceFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final appearanceLocked = isGekiga;

    void selectThemeMode(ThemeMode mode) =>
        ref.read(appThemeModeProvider.notifier).setMode(mode);

    final appearanceOptions = [
      (mode: ThemeMode.light, label: strings.settingsAppearanceLight),
      (mode: ThemeMode.dark, label: strings.settingsAppearanceDark),
      (mode: ThemeMode.system, label: strings.settingsAppearanceSystem),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.settingsAppearance,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // 劇画UI選択中は外観（ライト/ダーク/端末に合わせる）を変更不可にする
        // （グレーアウト＋操作無効化）。themeModeに関わらず常に同じ見た目を
        // 返す設計のため、この設定を変えても効果が無い（2026-08-04追加）。
        if (appearanceLocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              strings.settingsAppearanceGekigaLockedHint,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        Opacity(
          opacity: appearanceLocked ? 0.4 : 1.0,
          child: IgnorePointer(
            ignoring: appearanceLocked,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: appearanceControl,
            ),
          ),
        ),
      ],
    );
  }
}

/// アクセントカラー（フラットUI/ガラスUI）・劇画UIの背景色の選択
/// （2026-09-15、`_DesignFolder`から分離。上記[_AppearanceFolder]参照）。
class _AccentColorFolder extends ConsumerStatefulWidget {
  const _AccentColorFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<_AccentColorFolder> createState() => _AccentColorFolderState();
}

/// アクセントカラーのプリセット（8桁hex＝RRGGBBAA）。フラット/ガラス/劇画の
/// 3スタイル共通の1リスト（2026-09-15、以前はフラット/ガラス用の
/// `_kAccentColorPresets`と劇画用の`_kGekigaBackgroundColorPresets`に
/// 分かれていたが、中身は同じRGB5色だったため統合した）。劇画UIの背景色は
/// 常に不透明として扱う（`GekigaBackgroundColorNotifier.setColor`参照）ため、
/// 末尾のアルファは劇画側では単に無視される。ユーザーが長押しで削除した
/// 要素は`removedDefaultColorPresetsProvider`側の集合で管理し、この
/// リスト自体からは取り除かない（削除は表示フィルタで実現し、復活手段は
/// 設けない）。
const _kDefaultColorPresets = [
  'F08300CC',
  '3D2EE0CC',
  '88B04BCC',
  'C1272DCC',
  'F08567CC',
];

class _AccentColorFolderState extends ConsumerState<_AccentColorFolder> {
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
      // 劇画UIの背景色は`GekigaBackgroundColorNotifier.setColor`内で常に
      // 不透明化されて保存されるが、入力欄のテキスト自体は書き換えない
      // （2026-09-15変更）。よって確定直後は入力した8桁表示のまま残るが、
      // これは画面を開いている間（このセッション限り）でよく、設定画面を
      // 再訪したりUIスタイルを切り替えて戻った場合は上の`ref.listen`/
      // `initState`が実際に保存された6桁の値へ再読込する。
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

  /// 現在有効な色を「プリセット」へ登録する（フラット/ガラス/劇画共通、
  /// 2026-09-15追加。以前はフラット/ガラスの入力欄のみに直書きしていた）。
  Future<void> _registerCustomColor(BuildContext context) async {
    final isGekiga = ref.read(appUiStyleProvider) == AppUiStyle.gekiga;
    final activeColor = isGekiga
        ? ref.read(gekigaBackgroundColorProvider)
        : ref.read(accentColorProvider);
    final customColors = ref.read(customAccentColorsProvider);
    final removedDefaultHex = ref.read(removedDefaultColorPresetsProvider);
    final defaultColors = [
      for (final hex in _kDefaultColorPresets)
        if (!removedDefaultHex.contains(hex)) tryParseHexColor(hex)!,
    ];
    // 劇画UIは背景色を常に不透明として扱うため、アルファ差だけの重複は
    // 同一色とみなして弾く（同じ見た目の色が2つのスウォッチとして並ぶのを
    // 防ぐ）。フラット/ガラスは従来通りアルファ込みの完全一致で比較する。
    bool sameColor(Color a, Color b) =>
        isGekiga ? a.withAlpha(0xFF) == b.withAlpha(0xFF) : a == b;
    final alreadyShown =
        defaultColors.any((c) => sameColor(c, activeColor)) ||
        customColors.any((c) => sameColor(c, activeColor));
    if (alreadyShown) return;
    final added = await ref
        .read(customAccentColorsProvider.notifier)
        .addColor(activeColor);
    if (!added && context.mounted) {
      showAutoDismissBanner(
        context,
        message: widget.strings.settingsCustomColorLimitReachedTemplate(
          kMaxCustomAccentColors,
        ),
      );
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
    final customColors = ref.watch(customAccentColorsProvider);
    final gekigaBackgroundColor = ref.watch(gekigaBackgroundColorProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final activeColor = isGekiga ? gekigaBackgroundColor : accentColor;
    final removedDefaultHex = ref.watch(removedDefaultColorPresetsProvider);

    // 劇画UIは背景色を常に不透明として扱うため、選択中判定・登録時の重複
    // チェックはアルファを無視して比較する（そうしないと透明度付きの固定
    // プリセットが劇画側で永遠に「選択中」にならない）。フラット/ガラスは
    // 従来通りアルファ込みの完全一致で比較する。
    bool sameColor(Color a, Color b) =>
        isGekiga ? a.withAlpha(0xFF) == b.withAlpha(0xFF) : a == b;

    // 固定プリセット（削除されていないもの）とユーザー登録色を1つの
    // 「プリセット」一覧にまとめる（2026-09-15、以前は「プリセット」
    // 「登録した色」の2セクションに分かれ、劇画UIでは後者を非表示にして
    // いた）。出自を`isDefault`で区別し、長押し削除時にどちらのプロバイダを
    // 更新するか振り分ける。
    final presetEntries = [
      for (final hex in _kDefaultColorPresets)
        if (!removedDefaultHex.contains(hex))
          (hex: hex, isDefault: true, color: tryParseHexColor(hex)!),
      for (final color in customColors)
        (
          hex: color.toHexString().replaceFirst('#', ''),
          isDefault: false,
          color: color,
        ),
    ];

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
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: GekigaColors.onPanel),
                  onPressed: _applyHexInput,
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: GekigaColors.onPanel),
                  tooltip: '',
                  onPressed: () => _registerCustomColor(context),
                ),
              ],
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
              // フラットUIでもこの欄だけガラスUIと同じ見た目
              // （半透明の塗り＋アクセントカラーの縁取り）にする
              // （2026-09-14変更、ユーザー要望）。塗り色は
              // `colorScheme.surfaceContainerHighest`だとフラット/
              // ガラスでアクセントカラーの色味有無が異なり見た目が
              // ズレていたため、`GlassColors`の固定値を直接参照して
              // UIスタイルに関係なく常に同じ色にする（2026-09-15修正）。
              filled: true,
              fillColor:
                  (Theme.of(context).brightness == Brightness.dark
                          ? GlassColors.darkSurfaceBase
                          : GlassColors.lightSurfaceBase)
                      .withValues(alpha: 0.65),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: activeColor.withValues(alpha: 0.3),
                ),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _applyHexInput,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '',
                    onPressed: () => _registerCustomColor(context),
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _applyHexInput(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                      for (final entry in presetEntries)
                        _PresetColorSwatch(
                          hex: entry.hex,
                          selected: sameColor(entry.color, activeColor),
                          onTap: () => _applyPreset(entry.hex),
                          onLongPress: () async {
                            final confirmed = await _confirmDeletePresetColor(
                              context,
                              widget.strings,
                            );
                            if (!confirmed) return;
                            if (entry.isDefault) {
                              await ref
                                  .read(
                                    removedDefaultColorPresetsProvider.notifier,
                                  )
                                  .markRemoved(entry.hex);
                            } else {
                              await ref
                                  .read(customAccentColorsProvider.notifier)
                                  .removeColor(entry.color);
                            }
                          },
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

/// フォントカラー（旧称: 文字色、`colorScheme.onSurface`相当）をライト/
/// ダークそれぞれカラーコードで指定する設定（2026-09-14追加）。アクセント
/// カラーと違い背景とのコントラストが直接可読性に関わるため、
/// `accentColorProvider`のようなライト/ダーク共通の1色ではなく、
/// `textColorLightProvider`/`textColorDarkProvider`の2つを別々に持つ
/// （ユーザー確認済み）。設定画面上は「UIスタイル」と「フォントデザイン」の
/// 間に独立したセクションとして表示する（`_ApplicationPage`参照、
/// 以前は`_DesignFolder`内に埋め込まれていた）。
class _TextColorFolder extends ConsumerStatefulWidget {
  const _TextColorFolder();

  @override
  ConsumerState<_TextColorFolder> createState() => _TextColorFolderState();
}

class _TextColorFolderState extends ConsumerState<_TextColorFolder> {
  late final TextEditingController _lightController;
  late final TextEditingController _darkController;
  String? _lightErrorText;
  String? _darkErrorText;

  @override
  void initState() {
    super.initState();
    _lightController = TextEditingController(
      text: ref
          .read(textColorLightProvider)
          .toHexString()
          .replaceFirst('#', ''),
    );
    _darkController = TextEditingController(
      text: ref.read(textColorDarkProvider).toHexString().replaceFirst('#', ''),
    );
  }

  @override
  void dispose() {
    _lightController.dispose();
    _darkController.dispose();
    super.dispose();
  }

  void _applyLight() {
    final color = tryParseHexColor(_lightController.text);
    if (color == null) {
      setState(() => _lightErrorText = '「#RRGGBB」の形式で入力してください');
      return;
    }
    setState(() => _lightErrorText = null);
    ref.read(textColorLightProvider.notifier).setColor(color);
  }

  void _applyDark() {
    final color = tryParseHexColor(_darkController.text);
    if (color == null) {
      setState(() => _darkErrorText = '「#RRGGBB」の形式で入力してください');
      return;
    }
    setState(() => _darkErrorText = null);
    ref.read(textColorDarkProvider.notifier).setColor(color);
  }

  void _resetLight() {
    setState(() {
      _lightErrorText = null;
      _lightController.text = kDefaultTextColorLight.toHexString().replaceFirst(
        '#',
        '',
      );
    });
    ref.read(textColorLightProvider.notifier).setColor(kDefaultTextColorLight);
  }

  void _resetDark() {
    setState(() {
      _darkErrorText = null;
      _darkController.text = kDefaultTextColorDark.toHexString().replaceFirst(
        '#',
        '',
      );
    });
    ref.read(textColorDarkProvider.notifier).setColor(kDefaultTextColorDark);
  }

  Widget _colorRow({
    required Color color,
    required String label,
    required TextEditingController controller,
    required String? errorText,
    required VoidCallback onApply,
    required VoidCallback onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                labelText: label,
                prefixText: '#',
                hintText: '1C1C1E',
                errorText: errorText,
                counterText: '',
                // アクセントカラーの入力欄と同じ、ガラスUI風の見た目に揃える
                // （2026-09-14変更、`_DesignFolderState`のアクセントカラー欄参照）。
                // 塗り色は`GlassColors`の固定値を直接参照し、フラット/ガラスで
                // 常に同じ色になるようにする（2026-09-15修正、理由は
                // アクセントカラー欄側のコメント参照）。
                filled: true,
                fillColor:
                    (Theme.of(context).brightness == Brightness.dark
                            ? GlassColors.darkSurfaceBase
                            : GlassColors.lightSurfaceBase)
                        .withValues(alpha: 0.65),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: onApply,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '',
                      onPressed: onReset,
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => onApply(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final textColorLight = ref.watch(textColorLightProvider);
    final textColorDark = ref.watch(textColorDarkProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            strings.settingsTextColorTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            strings.settingsTextColorDescription,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
        ),
        const SizedBox(height: 8),
        _colorRow(
          color: textColorLight,
          label: strings.settingsTextColorLightLabel,
          controller: _lightController,
          errorText: _lightErrorText,
          onApply: _applyLight,
          onReset: _resetLight,
        ),
        _colorRow(
          color: textColorDark,
          label: strings.settingsTextColorDarkLabel,
          controller: _darkController,
          errorText: _darkErrorText,
          onApply: _applyDark,
          onReset: _resetDark,
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
    this.onLongPress,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  /// 削除導線用のコールバック。固定プリセット・ユーザー登録色のどちらも
  /// この`_PresetColorSwatch`を共通で使うため、呼び出し元
  /// （[_AccentColorFolderState]）が出自に応じて
  /// `removedDefaultColorPresetsProvider`か`customAccentColorsProvider`の
  /// どちらを更新するか振り分ける（2026-09-15、以前は固定プリセットに対して
  /// nullを渡し削除不可にしていた）。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = tryParseHexColor(hex)!;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
          AppUiStyle.glass.hashCode,
          AppUiStyle.gekiga.hashCode,
        ],
        selectedFlags: [
          style == AppUiStyle.flat,
          style == AppUiStyle.glass,
          style == AppUiStyle.gekiga,
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
            selected: style == AppUiStyle.glass,
            leading: Icon(
              style == AppUiStyle.glass
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(strings.settingsUiStyleGlassLabel),
            subtitle: Text(strings.settingsUiStyleGlassDescription),
            onTap: () => select(AppUiStyle.glass),
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
            value: AppUiStyle.glass,
            title: Text(strings.settingsUiStyleGlassLabel),
            subtitle: Text(strings.settingsUiStyleGlassDescription),
          ),
          RadioListTile<AppUiStyle>(
            value: AppUiStyle.gekiga,
            title: Text(strings.settingsUiStyleGekigaLabel),
            subtitle: Text(strings.settingsUiStyleGekigaDescription),
          ),
        ],
      ),
    );
  }
}

/// フォントデザインの選択（2026-09-06追加、2026-09-07に劇画も対象化、
/// 2026-09-15に「もっと見る」展開式に変更）。他の選択項目
/// （`_LanguageFolder`等）と同じく、劇画スタイル選択中はこの選択肢一覧
/// 自体も劇画の見た目に揃える（選択は即座に反映される）。
class _FontDesignFolder extends ConsumerStatefulWidget {
  const _FontDesignFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<_FontDesignFolder> createState() => _FontDesignFolderState();
}

class _FontDesignFolderState extends ConsumerState<_FontDesignFolder> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final design = ref.watch(fontDesignProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(FontDesign value) =>
        ref.read(fontDesignProvider.notifier).setDesign(value);

    // 2026-09-26: 蔵のフォントデザイン素材選択（`_FontDesignMaterialDialog`）
    // でも同じラベル一覧が必要になったため、`Strings.fontDesignLabel`に
    // 一本化した（以前はここに25分岐のswitchを直書きしていた）。
    String labelFor(FontDesign value) => strings.fontDesignLabel(value);

    final hasMore = FontDesign.values.length > kFontDesignPreviewCount;
    final visibleDesigns = _expanded
        ? FontDesign.values
        : FontDesign.values.take(kFontDesignPreviewCount);
    final remaining = FontDesign.values.length - visibleDesigns.length;

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [
          for (final value in visibleDesigns) value.hashCode,
          if (hasMore) 'fontDesignShowMore'.hashCode,
        ],
        selectedFlags: [
          for (final value in visibleDesigns) design == value,
          if (hasMore) false,
        ],
        children: [
          for (final value in visibleDesigns)
            GekigaTileContent(
              selected: design == value,
              leading: Icon(
                design == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                labelFor(value),
                style: TextStyle(fontFamily: value.fontFamily),
              ),
              subtitle: value.isKiwamiExclusive
                  ? Text(strings.fontDesignKiwamiExclusiveNotice)
                  : null,
              onTap: () => select(value),
            ),
          if (hasMore)
            GekigaTileContent(
              leading: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              title: Text(
                _expanded
                    ? strings.showLess
                    : strings.fontDesignShowMoreTemplate(remaining),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      );
    }

    return RadioGroup<FontDesign>(
      groupValue: design,
      onChanged: (value) {
        if (value != null) select(value);
      },
      child: Column(
        children: [
          for (final value in visibleDesigns)
            RadioListTile<FontDesign>(
              value: value,
              title: Text(
                labelFor(value),
                style: TextStyle(fontFamily: value.fontFamily),
              ),
              subtitle: value.isKiwamiExclusive
                  ? Text(strings.fontDesignKiwamiExclusiveNotice)
                  : null,
            ),
          if (hasMore)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              title: Text(
                _expanded
                    ? strings.showLess
                    : strings.fontDesignShowMoreTemplate(remaining),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
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

/// 語らい一覧レイアウト（現在の実装UI／アイコン＋寄合一覧UI）の切り替え
/// （2026-09-11追加）。コンピューター（`classifyDevice`が
/// `DeviceClass.computer`）で`talks_tab.dart`の`kTalksSplitBreakpoint`以上
/// かつ横長の広い画面（`_isSplit`）の場合はこの設定を無視し、常に固定の
/// 左右分割表示になる（タブレットを横向きにした場合はこの設定が適用される）。
class _TalksListLayoutFolder extends ConsumerWidget {
  const _TalksListLayoutFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(talksListLayoutStyleProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(TalksListLayoutStyle value) =>
        ref.read(talksListLayoutStyleProvider.notifier).setStyle(value);

    final options = [
      (
        value: TalksListLayoutStyle.standard,
        title: strings.settingsTalksListLayoutStandard,
        subtitle: strings.settingsTalksListLayoutStandardDescription,
      ),
      (
        value: TalksListLayoutStyle.iconSplit,
        title: strings.settingsTalksListLayoutIconSplit,
        subtitle: strings.settingsTalksListLayoutIconSplitDescription,
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
        : RadioGroup<TalksListLayoutStyle>(
            groupValue: style,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<TalksListLayoutStyle>(
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
            strings.settingsTalksListLayoutTitle,
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

/// アプリ起動時のパスコードロック（2026-09-11追加）。パスコード・生体認証
/// 設定は端末ローカルのみで完結し、Firestoreへは同期しない
/// （`PasscodeRepository`参照）。読み込み中（`flutter_secure_storage`からの
/// 非同期読み出し）はローディング表示にする。
class _PasscodeLockFolder extends ConsumerStatefulWidget {
  const _PasscodeLockFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<_PasscodeLockFolder> createState() =>
      _PasscodeLockFolderState();
}

class _PasscodeLockFolderState extends ConsumerState<_PasscodeLockFolder> {
  bool _loading = true;
  bool _passcodeEnabled = false;
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(passcodeRepositoryProvider);
    final isSet = await repository.isPasscodeSet();
    final biometricEnabled = await repository.isBiometricEnabled();
    final canUseBiometrics = await repository.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _passcodeEnabled = isSet;
      _biometricEnabled = biometricEnabled;
      _canUseBiometrics = canUseBiometrics;
      _loading = false;
    });
  }

  Future<void> _onPasscodeToggle(bool enable) async {
    final repository = ref.read(passcodeRepositoryProvider);
    if (enable) {
      final code = await PasscodeSetupDialog.show(context);
      if (code == null || !mounted) return;
      await repository.setPasscode(code);
      final canUseBiometrics = await repository.canUseBiometrics();
      if (!mounted) return;
      setState(() {
        _passcodeEnabled = true;
        _canUseBiometrics = canUseBiometrics;
      });
      return;
    }
    // 他人が勝手に無効化できないよう、OFFにする前に現在のパスコードで
    // 本人確認する（`PasscodeVerifyDialog`参照）。
    final verified = await PasscodeVerifyDialog.show(context);
    if (!verified || !mounted) return;
    await repository.clearPasscode();
    if (!mounted) return;
    setState(() {
      _passcodeEnabled = false;
      _biometricEnabled = false;
    });
  }

  Future<void> _onChangePasscode() async {
    final verified = await PasscodeVerifyDialog.show(context);
    if (!verified || !mounted) return;
    final code = await PasscodeSetupDialog.show(context);
    if (code == null || !mounted) return;
    await ref.read(passcodeRepositoryProvider).setPasscode(code);
  }

  Future<void> _onBiometricToggle(bool enable) async {
    await ref.read(passcodeRepositoryProvider).setBiometricEnabled(enable);
    if (!mounted) return;
    setState(() => _biometricEnabled = enable);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.settingsPasscodeLockToggleLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsPasscodeLockDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (_loading)
          const SizedBox.shrink()
        else ...[
          SwitchListTile(
            title: Text(strings.settingsPasscodeLockToggleLabel),
            value: _passcodeEnabled,
            onChanged: _onPasscodeToggle,
          ),
          if (_passcodeEnabled) ...[
            ListTile(
              title: Text(strings.settingsPasscodeChangeButton),
              onTap: _onChangePasscode,
            ),
            if (_canUseBiometrics)
              SwitchListTile(
                title: Text(strings.settingsPasscodeBiometricToggleLabel),
                value: _biometricEnabled,
                onChanged: _onBiometricToggle,
              ),
          ],
        ],
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
        _TalksListLayoutFolder(strings: strings),
        const Divider(height: 24),
        SettingsAccordionSection(
          title: strings.settingsAdvancedSectionTitle,
          children: [
            _SendKeyFolder(strings: strings),
            const Divider(height: 24),
            _StickerSendModeFolder(strings: strings),
            const Divider(height: 24),
            _DraftSyncFolder(strings: strings),
          ],
        ),
      ],
    );
  }
}

/// [_BlockedUsersFolder]が展開前に表示する件数（2026-09-14追加）。これを
/// 超える場合は「もっと見る」バーを出し、タップで全件表示に切り替える。
const kBlockedUsersPreviewCount = 3;

/// ブロックしたユーザーの一覧＋解除ボタン。一対のハンバーガーメニューから
/// ブロックした相手（`users/{userId}/blockedUsers`）をここにまとめて表示する。
class _BlockedUsersFolder extends ConsumerStatefulWidget {
  const _BlockedUsersFolder({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  @override
  ConsumerState<_BlockedUsersFolder> createState() =>
      _BlockedUsersFolderState();
}

class _BlockedUsersFolderState extends ConsumerState<_BlockedUsersFolder> {
  bool _expanded = false;

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String targetUserId,
  ) async {
    try {
      await ref
          .read(blockRepositoryProvider)
          .unblock(
            userId: widget.currentUser.userId,
            targetUserId: targetUserId,
          );
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: 'エラーが発生しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final blockedIdsAsync = ref.watch(
      blockedUserIdsProvider(widget.currentUser.userId),
    );

    return blockedIdsAsync.when(
      loading: () => const SizedBox.shrink(),
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
              return const SizedBox.shrink();
            }
            final blockedUsers = [...snapshot.data!]
              ..sort((a, b) => a.rhingSeed.compareTo(b.rhingSeed));
            final hasMore = blockedUsers.length > kBlockedUsersPreviewCount;
            final visibleUsers = _expanded
                ? blockedUsers
                : blockedUsers.take(kBlockedUsersPreviewCount).toList();
            final remaining = blockedUsers.length - visibleUsers.length;
            return Column(
              children: [
                for (final user in visibleUsers)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: CircleAvatar(
                      backgroundImage: user.effectiveIcon?.url != null
                          ? NetworkImage(user.effectiveIcon!.url)
                          : null,
                      child: user.effectiveIcon?.url == null
                          ? Text(
                              user.rhingSeed.isNotEmpty
                                  ? user.rhingSeed[0].toUpperCase()
                                  : '?',
                            )
                          : null,
                    ),
                    title: Text('@${user.rhingSeed}'),
                    trailing: TextButton(
                      onPressed: () => _unblock(context, ref, user.userId),
                      child: Text(strings.settingsBlockedUsersUnblock),
                    ),
                  ),
                if (hasMore)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    title: Text(
                      _expanded
                          ? strings.showLess
                          : strings.settingsBlockedUsersShowMoreTemplate(
                              remaining,
                            ),
                    ),
                    onTap: () => setState(() => _expanded = !_expanded),
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

/// ぺったん（スタンプ）の送信方式（LINE型2タップ確認／Discord型1タップ即送信）
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
      // ボックス自体の色（背景・文字）はON/OFFに関わらず固定のままにし、
      // スイッチのボール・トラックの色だけを白黒反転させて状態を示す
      // （2026-08-29変更、以前はボックス全体が反転していた）。
      return GekigaJointedTileList(
        seeds: const [0],
        selectedFlags: const [false],
        children: [
          GekigaTileContent(
            selected: false,
            title: Text(strings.settingsDraftSyncTitle),
            subtitle: Text(strings.settingsDraftSyncSubtitle),
            trailing: Switch(
              value: enabled,
              onChanged: setEnabled,
              activeThumbColor: GekigaColors.panel,
              activeTrackColor: GekigaColors.onPanel,
              inactiveThumbColor: GekigaColors.onPanel,
              inactiveTrackColor: GekigaColors.panel,
              trackOutlineColor: WidgetStatePropertyAll(GekigaColors.onPanel),
            ),
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

/// プッシュ通知の許可トグル（2026-08-31実装、2026-09-01トグル化。
/// 対応: Web・Android。`PushNotificationBootstrap`がログイン直後に一度
/// 自動でリクエストするが、ここで明示的にオフにすると次回起動時の自動
/// リクエストもスキップされるようになる（`PushNotificationBootstrap`
/// 参照）。OS/ブラウザ側の許可自体はアプリから取り消せないため、オフに
/// した場合は実際にはこの端末のFCMトークンをFirestoreから削除するだけ）。
class _NotificationsPage extends ConsumerWidget {
  const _NotificationsPage({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final repo = ref.read(pushNotificationRepositoryProvider);
    if (value) {
      final granted = await repo.requestPermissionAndRegister(
        currentUser.userId,
      );
      if (!granted && context.mounted) {
        showAutoDismissBanner(
          context,
          message: strings.settingsNotificationsPermissionDeniedError,
        );
      }
    } else {
      await repo.unregisterCurrentToken(currentUser.userId);
    }
    await ref
        .read(userRepositoryProvider)
        .setPushNotificationsEnabled(currentUser.userId, value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUser = ref.watch(watchedUserProvider(currentUser.userId));
    final enabled =
        liveUser.asData?.value?.pushNotificationsEnabled ??
        currentUser.pushNotificationsEnabled ??
        false;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final title = Text(strings.settingsNotificationsEnableTitle);
    final subtitle = Text(strings.settingsNotificationsEnableSubtitle);

    void setEnabled(bool value) => _setEnabled(context, ref, value);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isGekiga)
          GekigaJointedTileList(
            seeds: const [0],
            selectedFlags: const [false],
            children: [
              GekigaTileContent(
                selected: false,
                title: title,
                subtitle: subtitle,
                trailing: Switch(
                  value: enabled,
                  onChanged: setEnabled,
                  activeThumbColor: GekigaColors.panel,
                  activeTrackColor: GekigaColors.onPanel,
                  inactiveThumbColor: GekigaColors.onPanel,
                  inactiveTrackColor: GekigaColors.panel,
                  trackOutlineColor: WidgetStatePropertyAll(
                    GekigaColors.onPanel,
                  ),
                ),
                onTap: () => setEnabled(!enabled),
              ),
            ],
          )
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: title,
            subtitle: subtitle,
            onChanged: setEnabled,
          ),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSubSound),
        _SectionHeader(strings.settingsSoundRingtoneTitle),
        _SoundSettingsFolder(
          strings: strings,
          category: SoundCategory.ringtone,
          currentValue: ref.watch(ringtoneSoundProvider),
          customSoundUpload: ref.watch(ringtoneCustomSoundProvider),
          userId: currentUser.userId,
        ),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSoundCallingTitle),
        _SoundSettingsFolder(
          strings: strings,
          category: SoundCategory.calling,
          currentValue: ref.watch(callingSoundProvider),
          customSoundUpload: ref.watch(callingCustomSoundProvider),
          userId: currentUser.userId,
        ),
        // 通知音（メッセージ受信音）はOSのプッシュ通知を経由するため、
        // 現状プッシュ通知自体が実装されているAndroidのみ対応（Phase B、
        // 2026-09-06追加）。Web/iOS/Windows/Linux/macOSには表示しない
        // （`sound_preset.dart`のSoundCategory.notificationコメント参照）。
        if (!kIsWeb && Platform.isAndroid) ...[
          const Divider(height: 24),
          _SectionHeader(strings.settingsSoundNotificationTitle),
          _SoundSettingsFolder(
            strings: strings,
            category: SoundCategory.notification,
            currentValue: ref.watch(notificationSoundProvider),
            customSoundUpload: ref.watch(notificationCustomSoundProvider),
            userId: currentUser.userId,
          ),
        ],
      ],
    );
  }
}

/// 着信音・呼出音の選択（2026-09-06追加）。プリセットからのラジオ選択に
/// 加え、末尾の「アップロード」から端末の音声ファイルを選んでカスタム
/// 音源に設定できる（`UserRepository.uploadCustomSound`参照）。
/// 通話中に実際に再生する`CallSoundPlayer`とは別に、試聴専用の
/// 一時的な`AudioPlayer`をこのウィジェットが所有する。
class _SoundSettingsFolder extends ConsumerStatefulWidget {
  const _SoundSettingsFolder({
    required this.strings,
    required this.category,
    required this.currentValue,
    required this.customSoundUpload,
    required this.userId,
  });

  final Strings strings;
  final SoundCategory category;
  final String? currentValue;

  /// この端末で最後にアップロードしたカスタム音源（プリセットへ切り替えた
  /// あとも保持され続ける、`xxxCustomSoundProvider`参照）。まだ一度も
  /// アップロードしたことがなければnull。
  final CustomSoundUpload? customSoundUpload;
  final String userId;

  @override
  ConsumerState<_SoundSettingsFolder> createState() =>
      _SoundSettingsFolderState();
}

/// ラジオグループ上で「アップロードした音源を使う」を表す値
/// （プリセットidは常に空でないため衝突しない）。
const _customSoundSentinel = '';

class _SoundSettingsFolderState extends ConsumerState<_SoundSettingsFolder> {
  // ブラウザ環境によってはAudioPlayer()のコンストラクタ自体が例外を投げる
  // ことがあり、State構築時に即座に生成するとこのウィジェット全体が
  // マウントに失敗してしまう（2026-09-12発覚）。試聴を諦めても選択UIは
  // 表示され続けるよう、初回試聴時まで生成を遅延させる。
  AudioPlayer? _previewPlayer;

  /// 現在試聴再生中の音源（アセットパスまたはURL）。再生ボタンを停止
  /// ボタンに切り替える判定に使う（2026-09-12追加）。
  String? _playingId;

  @override
  void dispose() {
    _previewPlayer?.dispose();
    super.dispose();
  }

  /// 再生ボタンのトグル。同じ音源を再度押したら停止し、別の音源を押したら
  /// 切り替えて再生する（2026-09-12追加）。
  Future<void> _preview(String assetOrUrl) async {
    try {
      final player = _previewPlayer ??= AudioPlayer()
        ..onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playingId = null);
        });
      if (_playingId == assetOrUrl) {
        await player.stop();
        if (mounted) setState(() => _playingId = null);
        return;
      }
      await player.stop();
      await player.play(
        assetOrUrl.startsWith('http')
            ? UrlSource(assetOrUrl)
            : AssetSource(assetOrUrl),
      );
      if (mounted) setState(() => _playingId = assetOrUrl);
    } catch (_) {
      // 試聴できない環境でも設定変更自体はブロックしない。
      if (mounted) setState(() => _playingId = null);
    }
  }

  void _select(String presetId) {
    switch (widget.category) {
      case SoundCategory.ringtone:
        ref.read(ringtoneSoundProvider.notifier).setSound(presetId);
      case SoundCategory.calling:
        ref.read(callingSoundProvider.notifier).setSound(presetId);
      case SoundCategory.notification:
        ref.read(notificationSoundProvider.notifier).setSound(presetId);
    }
  }

  Future<void> _remember(String url, String? fileName) {
    switch (widget.category) {
      case SoundCategory.ringtone:
        return ref
            .read(ringtoneCustomSoundProvider.notifier)
            .remember(url, fileName);
      case SoundCategory.calling:
        return ref
            .read(callingCustomSoundProvider.notifier)
            .remember(url, fileName);
      case SoundCategory.notification:
        return ref
            .read(notificationCustomSoundProvider.notifier)
            .remember(url, fileName);
    }
  }

  /// 「アップロード」行本体をタップした際、既に有効なカスタム音源
  /// （[url]）があれば再アップロードせずそれを選び直すだけにする
  /// （2026-09-12追加）。この端末の記憶（[remembered]）がまだ無い・
  /// 一致しない場合は、その場でバックフィルする（ファイル名は不明なので
  /// null。以前はこのバックフィルが無く、記憶が無い間は行本体タップでも
  /// アップロードが開いてしまう不具合があった）。
  void _selectExistingCustom(String url, CustomSoundUpload? remembered) {
    _select(url);
    if (remembered == null || remembered.url != url) {
      _remember(url, null);
    }
  }

  Future<void> _uploadCustom() async {
    final strings = widget.strings;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kAllowedSoundExtensions.toList(),
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final url = await ref
          .read(userRepositoryProvider)
          .uploadCustomSound(widget.userId, widget.category, bytes, file.name);
      _select(url);
      await _remember(url, file.name);
    } on SoundUploadTooLargeException {
      if (mounted) {
        showAutoDismissBanner(
          context,
          message: strings.soundUploadTooLargeError,
        );
      }
    } on SoundUploadUnsupportedFormatException {
      if (mounted) {
        showAutoDismissBanner(
          context,
          message: strings.soundUploadUnsupportedFormatError,
        );
      }
    }
  }

  String _labelFor(SoundPreset preset) {
    final strings = widget.strings;
    return switch (preset.id) {
      'phonebooth_ring' => strings.soundPresetRetroLabel,
      'marimba_ring' => strings.soundPresetMarimbaLabel,
      'european_ringback' => strings.soundPresetClassicLabel,
      'futuristic_dial' => strings.soundPresetFutureLabel,
      'notification_lasomarie' => strings.soundPresetChimeLabel,
      'notification_message_pop' => strings.soundPresetPopLabel,
      'notification_happy_bells' => strings.soundPresetHappyLabel,
      _ => preset.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final presets = widget.category.presets;
    final currentValue = widget.currentValue;
    final remembered = widget.customSoundUpload;
    // 現在有効な値そのものがカスタムURLかどうか（他端末でアップロードした
    // ものが同期されてきた場合も含む。ラジオの選択状態表示に使う）。
    final isCustom = currentValue != null && currentValue.startsWith('http');
    // 実効値: 現在有効な値がカスタムURLならそれを優先し、そうでなければ
    // この端末の記憶にフォールバックする（2026-09-12修正。以前はこの2つの
    // 判定がバラバラで、有効な値はカスタムなのにこの端末の記憶がまだ無い
    // ケースで行本体タップがアップロードに落ちてしまう不具合があった）。
    final effectiveCustomUrl = isCustom ? currentValue : remembered?.url;
    final hasCustom = effectiveCustomUrl != null;
    final effectiveFileName = remembered?.url == effectiveCustomUrl
        ? remembered?.fileName
        : null;
    final customLabel = effectiveFileName ?? strings.soundUploadOptionLabel;
    final canUpload = isSoundUploadCapablePlatform;
    final selectedValue = isCustom
        ? _customSoundSentinel
        : (currentValue ?? widget.category.defaultPreset.id);

    Widget previewButton(String assetOrUrl) {
      final isPlaying = _playingId == assetOrUrl;
      return IconButton(
        tooltip: '',
        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
        onPressed: () => _preview(assetOrUrl),
      );
    }

    Widget uploadButton() => IconButton(
      tooltip: '',
      icon: const Icon(Icons.upload_file),
      onPressed: _uploadCustom,
    );

    Widget customSoundTrailing() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveCustomUrl != null) previewButton(effectiveCustomUrl),
        uploadButton(),
      ],
    );

    void onCustomTap() {
      if (hasCustom) {
        _selectExistingCustom(effectiveCustomUrl, remembered);
      } else {
        _uploadCustom();
      }
    }

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [
          for (final preset in presets) preset.id.hashCode,
          if (canUpload) _customSoundSentinel.hashCode,
        ],
        selectedFlags: [
          for (final preset in presets) selectedValue == preset.id,
          if (canUpload) isCustom,
        ],
        children: [
          for (final preset in presets)
            GekigaTileContent(
              selected: selectedValue == preset.id,
              leading: Icon(
                selectedValue == preset.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_labelFor(preset)),
              trailing: previewButton(preset.assetPath),
              onTap: () => _select(preset.id),
            ),
          if (canUpload)
            GekigaTileContent(
              selected: isCustom,
              leading: Icon(
                isCustom
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(customLabel),
              trailing: customSoundTrailing(),
              onTap: onCustomTap,
            ),
        ],
      );
    }

    return RadioGroup<String>(
      groupValue: selectedValue,
      onChanged: (value) {
        if (value == null) return;
        if (value == _customSoundSentinel) {
          onCustomTap();
        } else {
          _select(value);
        }
      },
      child: Column(
        children: [
          for (final preset in presets)
            RadioListTile<String>(
              value: preset.id,
              title: Text(_labelFor(preset)),
              secondary: previewButton(preset.assetPath),
            ),
          if (canUpload)
            RadioListTile<String>(
              value: _customSoundSentinel,
              title: Text(customLabel),
              secondary: customSoundTrailing(),
            ),
        ],
      ),
    );
  }
}
