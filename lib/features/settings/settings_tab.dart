import 'dart:math' as math;
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, MultiFactorInfo;
import 'package:flutter/foundation.dart'
    show kIsWeb, LicenseEntry, LicenseParagraph, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/holiday_settings_provider.dart';
import '../../providers/calendar_week_start_provider.dart';
import '../../providers/calendar_system_provider.dart';
import '../../models/calendar_week_start.dart';
import '../../models/calendar_system.dart';
import '../calendar/calendar_settings_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/kiwami_providers.dart';
import '../../utils/kiwami.dart';
import '../../widgets/kiwami_only_dialog.dart';
import '../../router/back_stack.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../theme/block/block_theme.dart';
import '../../models/app_ui_style.dart';
import '../../models/font_design.dart';
import '../../models/app_user.dart';
import '../../models/chat_layout_style.dart';
import '../../models/slide_transition_style.dart';
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
import '../../providers/home_shell_providers.dart';
import '../../providers/icon_split_layout_provider.dart';
import '../../providers/text_size_provider.dart';
import '../../utils/sidebar_width.dart';
import '../../providers/slide_pick_enabled_provider.dart';
import '../../providers/slide_transition_style_provider.dart';
import '../../providers/talks_list_layout_style_provider.dart';
import '../../providers/draft_sync_enabled_provider.dart';
import '../../models/nav_chip_layout.dart';
import '../../models/room_list_swipe_action.dart';
import '../../providers/category_list_alignment_provider.dart';
import '../../providers/settings_expansion_provider.dart';
import '../../widgets/nav_chip.dart';
import '../../widgets/home_tab_swipe.dart';
import '../../widgets/slide_select_list.dart';
import '../../providers/icon_split_mirrored_provider.dart';
import '../../providers/room_list_swipe_action_provider.dart';
import '../../providers/join_video_camera_on_provider.dart';
import '../../providers/nav_chip_layout_provider.dart';
import '../../providers/gekiga_background_color_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/removed_default_color_presets_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/notification_sound_provider.dart';
import '../../providers/ringtone_sound_provider.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/sticker_send_mode_provider.dart';
import '../../providers/on_accent_color_provider.dart';
import '../../providers/text_color_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../services/google_calendar_auth_service.dart';
import '../../services/google_calendar_link_coordinator.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/glass/glass_colors.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/color_presets.dart';
import '../../utils/color_hex.dart';
import '../../utils/platform_info.dart';
import '../../utils/sound_upload.dart';
import '../../widgets/destructive_label.dart';
import '../auth/residence_survey_screen.dart';
import '../../models/residence.dart';
import '../guide/guide_pages.dart';
import '../../widgets/media_preview_frame.dart';
import '../../widgets/copy_link_row.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/gekiga/settings_tile.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/interactive_swipe_back.dart';
import '../../widgets/qr_scan_screen.dart';
import 'issue_qr_login_dialog.dart';
import '../../widgets/slide_back_page_transitions.dart';
import '../../widgets/slide_drilldown.dart';
import '../auth/passcode_setup_dialog.dart';
import '../auth/two_factor_setup_dialog.dart';
import '../chat/announcement_screen.dart';
import '../../router/app_router.dart' show goRouterProvider;
import '../../utils/community_group.dart';
import '../chat/group_member_list_screen.dart';
import 'owned_sticker_packs_popup.dart';
import 'ai_integration_dialog.dart';
import 'passkey_management_dialog.dart';
import 'rhing_seed_change_dialog.dart';
import 'settings_accordion_section.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toggles/app_switch.dart';
import '../../widgets/toggles/app_radio.dart';
import '../../widgets/delayed_spinner.dart';

/// 画面幅がこれ以上あれば、左にカテゴリ一覧（サイドバー）、右にそのカテゴリの
/// 内容を1ページにまとめて表示するDiscord設定風の2ペイン表示にする。
/// これ未満の狭い画面では、カテゴリ一覧→内容ページの1段だけドリルダウンする。
const _kSettingsSplitBreakpoint = 760.0;

/// サイドバーの幅。語らい一覧（`talks_tab.dart`）・身だしなみ
/// （`profile_tab.dart`）の各サイドバーと区切り線のx座標を揃える為、
/// 3画面とも`sidebarWidthFor`（`lib/utils/sidebar_width.dart`）で決める。
/// フォントサイズ別（小200・中230・大260px、2026-11-06）。

/// コンピューターで運営の下位階層を右隣に並べて表示する際の、運営の一覧の幅
/// （2026-10-10追加）。
const _kSupportListWidth = 280.0;

/// 同じく、ライセンスを右隣に並べる時の「アプリについて」の幅（2026-10-10追加）。
const _kAboutPaneWidth = 380.0;

/// 居住地を右隣に並べる時の、右の入力欄の最小幅。
const _kResidencePaneMinWidth = 420.0;

/// 設定タブ。サイドバーの階層は最上位カテゴリ（アカウント／アプリケーション／
/// 入力／通知）の1段だけに留め、それぞれの中身（旧: サブフォルダだった項目）は
/// カテゴリ毎に1つの縦スクロールページへ、見出し付きセクションとしてまとめる
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
  /// pushしていた為、サイドバー・区切り線ごと覆い隠し、スワイプで戻る
  /// 操作も効かなかった。カテゴリ一覧⇄カテゴリの中身と同じ
  /// `SlideDrilldown`の仕組みをもう1段だけ使い回すことで両方を解消する
  /// （`build`参照。専用の入れ子`SlideDrilldown`を使わないのは、
  /// `InteractiveSwipeBackTransition`の水平ドラッグ`GestureDetector`を
  /// 親子で二重に重ねるとジェスチャーアリーナで競合しかねない為）。
  bool _showAbout = false;

  /// 「アプリについて」の中からさらに1段階下の「オープンソースライセンス」を
  /// 表示中か（2026-09-15追加）。以前は`showLicensePage`（Flutter SDK標準）
  /// が独立した`MaterialPageRoute`でpushしていた為、サイドバー・区切り線
  /// ごと覆い隠し、スワイプで戻る操作も効かなかった。`_showAbout`と同じ
  /// 仕組みをもう1段だけ使い回すことで両方を解消する（`build`参照）。
  bool _showLicenses = false;

  /// オープンソースライセンスの中で、個別のパッケージのライセンス本文を
  /// 開いているか（2026-10-10追加）。ライセンス画面は専用のローカル
  /// `Navigator`を持ち、パッケージ詳細はそこへpushされる。戻る操作
  /// （スワイプ・戻る履歴）がこの階層を飛ばして「アプリについて」まで
  /// 戻らないよう、状態を追跡して1段だけ戻れるようにする。
  bool _licenseDetailOpen = false;

  final GlobalKey<NavigatorState> _licenseNavigatorKey =
      GlobalKey<NavigatorState>();

  /// ライセンス画面の戻る。パッケージ詳細を開いていれば詳細を閉じて
  /// ライセンス一覧へ戻り、一覧なら「アプリについて」へ戻る。
  void _backFromLicenses() {
    if (_popLicenseDetail()) return;
    setState(() => _showLicenses = false);
  }

  /// 開いているパッケージ詳細があれば閉じる（閉じたらtrue）。
  bool _popLicenseDetail() {
    final navigator = _findLicenseDetailNavigator(_licenseNavigatorKey);
    if (navigator == null || !navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  Widget _buildLicensePage() => _LicensePageContent(
    navigatorKey: _licenseNavigatorKey,
    onDetailChanged: (open) {
      if (_licenseDetailOpen == open) return;
      setState(() => _licenseDetailOpen = open);
    },
    onDisposed: () => _licenseDetailOpen = false,
  );

  /// 運営カテゴリの中からさらに1段階下の「お知らせ」を表示中か
  /// （2026-09-15追加）。以前はgo_routerの`/announcements`ルートへ
  /// `push`していた為、サイドバー・区切り線ごと覆い隠していた
  /// （スワイプで戻る操作自体は`slideDetailPage`側で既に機能していたが、
  /// サイドバーが消える点は`_showAbout`と同じ問題を抱えていた）。
  bool _showAnnouncements = false;

  /// 運営カテゴリの中の「使い方ガイド」の一覧を表示中か（2026-10-17追加）。
  /// 項目を押すとその場でガイドが始まる為、詳細ページは無い。
  bool _showGuide = false;

  /// 使い方ガイドの階層（一覧・詳細）。広い画面・狭い画面とも同じレイヤーを使う。
  List<DrilldownLayer> _guideLayers() => [
    if (_showGuide)
      DrilldownLayer(
        key: 'guide',
        child: _buildGuideList(),
        onBack: () => setState(() => _showGuide = false),
      ),
  ];

  Widget _buildGuideList() => const GuideTopicListPage();

  /// アカウントカテゴリの「居住地」を開いているか（2026-10-17追加）。以前は別の
  /// 全画面ルートへ`push`していたが、コンピューターでは右隣に並べ、それ以外では
  /// 他の下位階層と同じく重ねて右スワイプで戻れるようにした。
  bool _showResidence = false;

  List<DrilldownLayer> _residenceLayers() => [
    if (_showResidence)
      DrilldownLayer(
        key: 'residence',
        child: _buildResidenceEditor(),
        onBack: () => setState(() => _showResidence = false),
      ),
  ];

  Widget _buildResidenceEditor() => _ResidenceEditor(
    userId: widget.currentUser.userId,
    onCompleted: () => setState(() => _showResidence = false),
  );

  /// カテゴリタップの共通ハンドラ。広い画面はサイドバーが常設の為、
  /// 「アプリについて」表示中でも別カテゴリをクリックできてしまう——
  /// その場合は`_showAbout`等も一緒にリセットする（2026-09-15追加）。
  void _onCategorySelected(_SettingsCategory category) {
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;
    final leavingId = _selectedId ?? _firstCategoryId;
    setState(() {
      // コンピューター（広い画面）では、別カテゴリへ移っても、元のカテゴリで進んだ
      // 階層（運営の「アプリについて」「お便り」等）を覚えておき、戻った時に
      // その階層から再開する（2026-11-06）。
      if (isWide && leavingId != null) {
        _savedDepth[leavingId] = (
          _showAbout,
          _showLicenses,
          _showAnnouncements,
          _showGuide,
          _showResidence,
        );
      }
      final restored = isWide ? _savedDepth[category.id] : null;
      _selectedId = category.id;
      _showAbout = restored?.$1 ?? false;
      _showLicenses = restored?.$2 ?? false;
      _showAnnouncements = restored?.$3 ?? false;
      _showGuide = restored?.$4 ?? false;
      _showResidence = restored?.$5 ?? false;
    });
  }

  /// カテゴリ毎に覚えておく、進んだ階層（広い画面のみ）。
  final Map<String, (bool, bool, bool, bool, bool)> _savedDepth = {};

  /// 先頭カテゴリのid（広い画面で`_selectedId`が未選択の時の既定）。
  String? _firstCategoryId;

  /// 戻る・進む（`BackStackController`）の履歴に記録する現在位置
  /// （2026-10-06追加）。設定タブ内のカテゴリ移動と下位階層の表示状態。
  @override
  Widget build(BuildContext context) {
    return NavHistoryBackEntry<(String?, bool, bool, bool, bool, bool, bool)>(
      scope: BackScope.settings,
      location: (
        _selectedId,
        _showAbout,
        _showLicenses,
        _showAnnouncements,
        _showLicenses && _licenseDetailOpen,
        _showGuide,
        _showResidence,
      ),
      onRestore: (location) => setState(() {
        _selectedId = location.$1;
        _showAbout = location.$2;
        _showLicenses = location.$3;
        _showAnnouncements = location.$4;
        _showGuide = location.$6;
        _showResidence = location.$7;
        // 履歴上の位置がライセンス一覧（詳細を開いていない）なら、開いている
        // パッケージ詳細を閉じる。
        if (!location.$5) _popLicenseDetail();
      }),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final categories = _categories(
      strings,
      ref,
      widget.currentUser,
      () => setState(() => _showAbout = true),
      () => setState(() => _showAnnouncements = true),
      () => setState(() => _showGuide = true),
      () => setState(() => _showResidence = true),
    );
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;
    _firstCategoryId = categories.first.id;

    if (isWide) {
      final selected =
          _findCategoryById(categories, _selectedId) ?? categories.first;

      // サポート→アプリについて→オープンソースライセンス／お知らせという
      // 下位階層は、下の狭い画面向け分岐と同じ`master`/`detail`を組み立てて
      // `SlideDrilldown`で包む（2026-09-18追加）。以前はここで対象の
      // ウィジェットへ直接差し替えるだけだった為、サイドバーは常に
      // 見えたままだったものの、タブレット等サイドバー常設幅の端末では
      // スワイプで戻る手段が無かった（スマホ幅だけスワイプ出来る食い違い
      // があった）。サイドバー・区切り線はこの分岐の外にある為、
      // 下位階層表示中も常に見えたままになる点は変わらない。
      // 階層は`SlideDrilldownStack`のレイヤーとして重ねる（2026-10-16）。
      // 以前は階層毎に`master`/`detail`を差し替えていた為、戻ると1段上の
      // 画面が新しい`detail`として作り直され、右から再度スライドインしていた。
      final wideLayers = <DrilldownLayer>[
        if (_showAbout || _showLicenses)
          DrilldownLayer(
            key: 'about',
            child: _AboutPageContent(
              strings: strings,
              onOpenLicenses: () => setState(() => _showLicenses = true),
            ),
            onBack: () => setState(() => _showAbout = false),
          ),
        if (_showAnnouncements)
          DrilldownLayer(
            key: 'announcements',
            child: AnnouncementScreen(currentUser: widget.currentUser),
            onBack: () => setState(() => _showAnnouncements = false),
          ),
        if (_showLicenses)
          DrilldownLayer(
            key: 'licenses',
            child: _buildLicensePage(),
            onBack: _backFromLicenses,
            consumeBack: _popLicenseDetail,
          ),
        ..._guideLayers(),
        ..._residenceLayers(),
      ];

      // コンピューターでは、運営の下位階層（お便り／アプリについて／使い方ガイド）を
      // 運営の一覧の上に重ねず、右隣に並べて表示する（2026-10-10追加）。
      // 幅だけの判定（`isWide`）はタブレット横向きも含むため、
      // `classifyDevice`でコンピューターに限定する。タブレット・スマホは
      // 従来どおり`SlideDrilldown`による重ね表示のまま。
      final sideBySide =
          classifyDevice(context) == DeviceClass.computer &&
          (_showAbout ||
              _showAnnouncements ||
              _showLicenses ||
              _showGuide ||
              _showResidence);
      final Widget contentColumns;
      if (sideBySide) {
        // ライセンスは「アプリについて」の右隣にさらに並べて表示する
        // （一覧 | アプリについて | ライセンス）。
        final Widget detailPane;
        if (_showResidence) {
          detailPane = _buildResidenceEditor();
        } else if (_showAbout || _showLicenses) {
          detailPane = _AboutPageContent(
            strings: strings,
            onOpenLicenses: () => setState(() => _showLicenses = true),
          );
        } else if (_showAnnouncements) {
          detailPane = AnnouncementScreen(currentUser: widget.currentUser);
        } else {
          detailPane = _buildGuideList();
        }
        contentColumns = LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                // 居住地を開いている間の左の欄は、アカウントの一覧を普段と同じ幅
                // （640）のまま見せる（運営用の狭い幅に詰めない）。右の入力欄が
                // 窮屈にならないよう、幅が足りない時だけ縮める。
                width: _showResidence
                    ? (constraints.maxWidth - 1 - _kResidencePaneMinWidth)
                          .clamp(_kSupportListWidth, 640.0)
                    : _kSupportListWidth,
                child: _SettingsPage(
                  maxWidth: _showResidence ? 640 : _kSupportListWidth,
                  // 居住地を開いている間は、左の欄はアカウントの一覧にする。
                  child: _showResidence
                      ? _AccountPage(
                          strings: strings,
                          currentUser: widget.currentUser,
                          onOpenResidence: () =>
                              setState(() => _showResidence = true),
                        )
                      : _SupportPage(
                          strings: strings,
                          currentUser: widget.currentUser,
                          onOpenAbout: () => setState(() {
                            _showAbout = true;
                            _showLicenses = false;
                            _showAnnouncements = false;
                            _showGuide = false;
                          }),
                          onOpenAnnouncements: () => setState(() {
                            _showAnnouncements = true;
                            _showAbout = false;
                            _showLicenses = false;
                            _showGuide = false;
                          }),
                          onOpenGuide: () => setState(() {
                            _showGuide = true;
                            _showAbout = false;
                            _showLicenses = false;
                            _showAnnouncements = false;
                          }),
                        ),
                ),
              ),
              const VerticalDivider(width: 1),
              if (_showLicenses) ...[
                SizedBox(
                  width: _kAboutPaneWidth,
                  child: _SettingsPage(
                    maxWidth: _kAboutPaneWidth,
                    child: detailPane,
                  ),
                ),
                const VerticalDivider(width: 1),
                // ライセンスは一覧の右にパッケージの本文を並べる（2026-11-06）。
                Expanded(
                  child: _SettingsPage(
                    maxWidth: double.infinity,
                    child: _buildLicensePage(),
                  ),
                ),
              ] else
                Expanded(
                  child: _SettingsPage(maxWidth: 640, child: detailPane),
                ),
            ],
          ),
        );
      } else {
        contentColumns = _SettingsPage(
          // アプリケーション・語らいは、項目を横に並べるため頭打ちを外す（2026-11-06）。
          maxWidth:
              _showLicenses ||
                  selected.id == 'application' ||
                  selected.id == 'talk'
              ? double.infinity
              : 640,
          child: SlideDrilldownStack(
            base: Builder(builder: selected.pageBuilder),
            layers: wideLayers,
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: sidebarWidthFor(ref.watch(appTextSizeProvider)),
              child: _CategoryList(
                categories: categories,
                selectedId: selected.id,
                onSelect: _onCategorySelected,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: contentColumns),
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

    // 階層は`SlideDrilldownStack`のレイヤーとして重ねる（2026-10-16、理由は
    // 広い画面側の`wideLayers`参照）。下位階層の表示中は`_selectedId`が
    // 無くても、運営カテゴリの中身をその下に置く。
    final hasSubLayer =
        _showAbout || _showLicenses || _showAnnouncements || _showGuide;
    final layerCategory =
        selected ??
        (hasSubLayer ? _findCategoryById(categories, 'support') : null);
    final layers = <DrilldownLayer>[
      if (layerCategory != null)
        DrilldownLayer(
          key: 'cat-${layerCategory.id}',
          child: _NarrowSettingsPage(category: layerCategory),
          onBack: () => setState(() => _selectedId = null),
          onNext: nextCategory == null
              ? null
              : () => setState(() => _selectedId = nextCategory.id),
        ),
      if (_showAbout || _showLicenses)
        DrilldownLayer(
          key: 'about',
          child: _AboutPageContent(
            strings: strings,
            onOpenLicenses: () => setState(() => _showLicenses = true),
          ),
          onBack: () => setState(() => _showAbout = false),
        ),
      if (_showAnnouncements)
        DrilldownLayer(
          key: 'announcements',
          child: AnnouncementScreen(currentUser: widget.currentUser),
          onBack: () => setState(() => _showAnnouncements = false),
        ),
      if (_showLicenses)
        DrilldownLayer(
          key: 'licenses',
          child: _buildLicensePage(),
          onBack: _backFromLicenses,
          consumeBack: _popLicenseDetail,
        ),
      ..._guideLayers(),
      ..._residenceLayers(),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: SlideDrilldownStack(
            base: HomeTabSwipe(
              child: _CategoryList(
                key: const ValueKey('settings-categories'),
                categories: categories,
                selectedId: null,
                onSelect: _onCategorySelected,
                large: true,
              ),
            ),
            layers: layers,
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
  VoidCallback onOpenGuide,
  VoidCallback onOpenResidence,
) {
  return [
    _SettingsCategory(
      id: 'account',
      icon: Icons.person_outline,
      title: strings.settingsFolderAccount,
      pageBuilder: (context) => _AccountPage(
        strings: strings,
        currentUser: currentUser,
        onOpenResidence: onOpenResidence,
      ),
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
        onOpenGuide: onOpenGuide,
      ),
    ),
  ];
}

/// カテゴリ一覧（サイドバー、又は狭い画面での一覧画面）。
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

  /// 狭い画面（モバイル）でこの一覧が画面全体を占める時に、行を大きく
  /// 見やすくするか（2026-08-27追加、劇画UIのみ対象）。広い画面の
  /// サイドバー表示時は`false`のまま従来通りのサイズを保つ。
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // 一覧の上を縦になぞって選べる（メニューチップと同じ操作、2026-11-02）。広い画面の
    // サイドバーはなぞった先をその場で選び、狭い画面（[large]）はなぞっている間だけ
    // 強調して、指を離した項目を開く。
    final narrow = large;
    // 縦表示で項目一覧を下（メニューチップのすぐ上）へ寄せる設定（全スタイル）。
    final bottom =
        narrow &&
        ref.watch(categoryListVerticalProvider) == CategoryListVertical.bottom;
    return SlideSelectList(
      itemCount: categories.length,
      onSlide: narrow ? null : (i) => onSelect(categories[i]),
      onSlideEnd: narrow ? (i) => onSelect(categories[i]) : null,
      builder: (context, keyFor, slidingIndex) {
        bool isSelected(int i) =>
            narrow ? i == slidingIndex : categories[i].id == selectedId;
        if (isGekiga) {
          return alignCategoryList(
            bottom: bottom,
            SingleChildScrollView(
              // 下寄せの時は逆向きのスクロールにして、内容が短くても下に寄せる
              // （並びは変わらない。長ければこれまでどおりスクロールする）。
              reverse: bottom,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GekigaJointedTileList(
                seeds: [
                  for (final category in categories) category.title.hashCode,
                ],
                selectedFlags: [
                  for (var i = 0; i < categories.length; i++) isSelected(i),
                ],
                children: [
                  for (var i = 0; i < categories.length; i++)
                    KeyedSubtree(
                      key: keyFor(i),
                      child: _FolderTile(
                        icon: categories[i].icon,
                        title: categories[i].title,
                        selected: isSelected(i),
                        trailingChevron: false,
                        large: large,
                        onTap: () => onSelect(categories[i]),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        return alignCategoryList(
          bottom: bottom,
          ListView(
            shrinkWrap: bottom,
            padding: EdgeInsets.fromLTRB(8, 0, 8, bottom ? 8 : 0),
            children: [
              for (var i = 0; i < categories.length; i++)
                KeyedSubtree(
                  key: keyFor(i),
                  child: _FolderTile(
                    icon: categories[i].icon,
                    title: categories[i].title,
                    selected: isSelected(i),
                    trailingChevron: false,
                    onTap: () => onSelect(categories[i]),
                  ),
                ),
            ],
          ),
        );
      },
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

  /// 狭い画面でこの一覧が画面全体を占める時に行を大きくするか
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

    if (uiStyle == AppUiStyle.block) {
      // 版画: 太枠と硬い影の箱（選択中はアクセントで塗る）。
      final fg = selected ? colorScheme.onPrimary : colorScheme.onSurface;
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 6, 8),
        child: blockFitWidth(
          blockMaterialBox(
            context,
            color: selected
                ? colorScheme.primary
                : (Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : colorScheme.surface),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              iconColor: fg,
              textColor: fg,
              leading: Icon(icon),
              title: Text(title),
              trailing: trailingWidget,
              onTap: onTap,
            ),
          ),
        ),
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
  /// 左右並列表示（パッケージ一覧⇄ライセンス本文）を働かせたい為、
  /// `double.infinity`を渡して頭打ちを外す（2026-09-18追加）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // 内容ペインが余った横幅いっぱいに広がると、ラベルと値の間の余白ばかりが
    // 目立ってしまう（項目が横に広がりすぎる）ため、読みやすい幅で頭打ちにする。
    // ConstrainedBoxは、親（Expanded）から渡されるtight制約をそのまま
    // enforce()すると自分のmaxWidthが無視される（tightな下限に引き上げられる）
    // ため、先にAlignでtight制約をloose制約に変換してから渡す必要がある。
    // サイドバーで既にカテゴリ名が選択表示されている為、ここでの
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
    // 戻る導線がスワイプに一本化された為、以前ここにあった
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

/// ラベル＋値（読み取り専用、又は「準備中」）の1行。
class _InfoRow extends ConsumerWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return SettingsTile(title: Text(label), trailing: Text(value));
    }
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

/// 値をコピー出来る情報行（自分のRhing Seed、2026-10-31）。身だしなみ>縁結びの招待リンクと
/// 同じボックス（[CopyLinkRow]）で、ラベルの下に値とコピーボタンを出す（2026-11-03）。
class _CopyableInfoRow extends ConsumerWidget {
  const _CopyableInfoRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;

  /// コピーボタンの右に置くボタン（Rhing Seedの「変更」、箱の中に入れる）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final box = isGekiga
        ? GekigaJointedTileList(
            seeds: [value.hashCode],
            selectedFlags: const [true],
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: CopyLinkRow(
                  link: value,
                  trailing: trailing,
                  copyOnlyByButton: true,
                  gekiga: true,
                  textStyle: const TextStyle(color: GekigaColors.panel),
                ),
              ),
            ],
          )
        : ref.watch(appUiStyleProvider) == AppUiStyle.block
        // 版画: 太枠と硬い影の箱（影の分の余白を含める）。
        // 左右の余白は下の外側の余白に任せ、「検索に表示する」の行（[SettingsTile]）と
        // 同じ左右の端に揃える（2026-11-06）。
        ? Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 6, 4),
            child: blockMaterialBox(
              context,
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: CopyLinkRow(
                  link: value,
                  trailing: trailing,
                  copyOnlyByButton: true,
                ),
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CopyLinkRow(
              link: value,
              trailing: trailing,
              copyOnlyByButton: true,
            ),
          );
    // 劇画・版画は箱を左右いっぱいに広げ、「検索に表示する」の箱と幅を揃える。
    final blockStyle =
        isGekiga || ref.watch(appUiStyleProvider) == AppUiStyle.block;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: blockStyle ? 0 : 16,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: blockStyle ? 16 : 0),
            child: Text(label),
          ),
          const SizedBox(height: 8),
          if (blockStyle) SizedBox(width: double.infinity, child: box) else box,
        ],
      ),
    );
  }
}

/// 他の住人が友達申請でRhing Seedを入力して自分を検索出来るかの切り替え（2026-10-31）。
/// 招待リンク・QRコードからの申請には影響しない。
class _SeedSearchableRow extends ConsumerStatefulWidget {
  const _SeedSearchableRow({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  @override
  ConsumerState<_SeedSearchableRow> createState() => _SeedSearchableRowState();
}

class _SeedSearchableRowState extends ConsumerState<_SeedSearchableRow> {
  late bool _value = widget.currentUser.isSeedSearchable;

  Future<void> _change(bool next) async {
    setState(() => _value = next);
    try {
      await ref
          .read(userRepositoryProvider)
          .setSeedSearchable(widget.currentUser.userId, next);
    } catch (_) {
      if (mounted) setState(() => _value = !next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(widget.strings.settingsSeedSearchableTitle),
      subtitle: Text(widget.strings.settingsSeedSearchableDescription),
      value: _value,
      onChanged: _change,
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
    return SettingsTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: destructive ? DestructiveLabel(label) : Text(label),
      onTap: onTap,
    );
  }
}

/// 2段階認証（TOTP）の状態表示・登録・解除を1行にまとめたもの
/// （2026-08-09追加）。`_InfoRow`のように現在の状態（有効/無効）を右側に
/// 出しつつ、`_ActionRow`のようにタップで操作出来る。
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
  // 飛んでくることがある為、型チェックに加えてメッセージ文字列でも
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
    return FutureBuilder<List<MultiFactorInfo>>(
      future: _factorsFuture,
      builder: (context, snapshot) {
        final factors = snapshot.data;
        // 2段階認証のオン/オフはトグルで切り替える。オンにすると登録ダイアログ、
        // オフにすると確認ダイアログを開き、完了・取消後は登録状態から値が決まる。
        return AppSwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(strings.settingsTwoFactor),
          value: factors != null && factors.isNotEmpty,
          onChanged: factors == null ? null : (_) => _onTap(factors),
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
    // 入口は1つ。開くとこの端末のQRコードが出て（別の端末に読み取ってもらう）、その下の
    // 「QRコードを読み取る」で逆向き（別の端末のQRコードを読み取る）も行える。
    return _ActionRow(
      label: strings.settingsQrLogin,
      onTap: () async {
        final scan = await IssueQrLoginDialog.show(context);
        if (scan && context.mounted) await _scan(context, ref);
      },
    );
  }
}

/// アクセントカラーのプリセットを削除する前の確認ダイアログ
/// （`_AccentColorFolderState`の「プリセット」長押し、2026-08-29追加。
/// 2026-09-15、固定プリセット・ユーザー登録色の両方を統合した「プリセット」
/// 1セクションの削除確認に使うよう拡張し`_confirmDeleteCustomColor`から
/// 改名）。
Future<bool> confirmDeletePresetColor(
  BuildContext context,
  Strings strings,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showAppDialog<bool>(
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
          : KeyboardAlertDialog(title: title, actions: actions);
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
  final confirmed = await showAppDialog<bool>(
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
          : KeyboardAlertDialog(
              title: title,
              content: content,
              actions: actions,
            );
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
  final confirmed = await showAppDialog<bool>(
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
          : KeyboardAlertDialog(
              title: title,
              content: content,
              actions: actions,
            );
    },
  );
  return confirmed ?? false;
}

/// Googleカレンダー連携の状態表示・切り替え行（2026-09-01追加）。初回確認は
/// `_CalendarButton`（`chat_panes.dart`、カレンダー機能を初めて開いた時）が
/// 主導線で、ここは後からいつでも許可/停止を切り替える為の副導線
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
    // 見える為、`watchedUserProvider`で最新値を購読する。
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
    // 連携の状態は文言ではなくトグルの位置で示す。
    final title = Text(strings.settingsGoogleCalendarSyncLabel);

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
            trailing: AppSwitch(
              value: showConnected,
              onChanged: setEnabled,
              onDarkSurface: true,
            ),
            onTap: () => setEnabled(!showConnected),
          ),
        ],
      );
    }
    return AppSwitchListTile(
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
  final confirmed = await showAppDialog<bool>(
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
          : KeyboardAlertDialog(
              title: title,
              content: content,
              actions: actions,
            );
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
    required this.onOpenGuide,
  });

  final Strings strings;
  final AppUser currentUser;

  /// 「使い方ガイド」タップ時の処理（2026-10-17追加）。`onOpenAbout`と同じく
  /// `_SettingsTabState`側の状態（`_showGuide`）を切り替えるだけにする。
  final VoidCallback onOpenGuide;

  /// 「アプリについて」タップ時の処理（2026-09-15追加）。以前はここで
  /// `Navigator.push`していたが、サイドバー・区切り線を覆い隠しスワイプ
  /// 戻るも効かない問題があった為、`_SettingsTabState`側の状態
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
        if (kCommunityGroupId.isNotEmpty)
          _ActionRow(
            label: strings.settingsCommunity,
            onTap: () =>
                ref.read(goRouterProvider).push('/join/$kCommunityGroupId'),
          ),
        _ActionRow(label: strings.settingsUsageGuide, onTap: onOpenGuide),
        _ActionRow(
          label: strings.settingsContact,
          onTap: () => _openExternalUrl(_contactUrl),
        ),
        _ActionRow(label: strings.settingsAboutApp, onTap: onOpenAbout),
      ],
    );
  }
}

const _termsUrl = 'https://rhing.jp/legal/terms';
const _privacyPolicyUrl = 'https://rhing.jp/legal/privacy';
const _disclaimerUrl = 'https://rhing.jp/legal/disclaimer';
const _contactUrl = 'https://rhing.jp/contact';

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
/// サイドバー・区切り線を覆い隠しスワイプ戻るも効かなかった為、
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
  /// スワイプ戻るも効かない問題があった為、`onOpenAbout`と同じく
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
/// アプリ全体のNavigatorへフルスクリーンでpushしていた為、サイドバー・
/// 区切り線ごと覆い隠し、スワイプで戻る操作も効かなかった。専用のローカル
/// `Navigator`で包むことで（2026-11-06から中身は標準の`LicensePage`ではなく
/// 設定の他画面と同じ部品で組んだ自前の一覧）パッケージ詳細へのpushをこのdetailスロット内に閉じ込め、
/// 外側（「アプリについて」への復帰）は`_SettingsTabState._showLicenses`の
/// トグル＋既存の`SlideDrilldown`/`InteractiveSwipeBackTransition`に任せる。
class _LicensePageContent extends StatefulWidget {
  const _LicensePageContent({
    required this.navigatorKey,
    required this.onDetailChanged,
    required this.onDisposed,
  });

  /// ローカル`Navigator`のキー。外側の戻る操作がパッケージ詳細を1段閉じる
  /// ために使う（2026-10-10追加）。
  final GlobalKey<NavigatorState> navigatorKey;

  /// パッケージ詳細を開いた／閉じた時の通知。
  final ValueChanged<bool> onDetailChanged;

  /// このページが破棄された時の通知（詳細の開閉状態をリセットする用）。
  final VoidCallback onDisposed;

  @override
  State<_LicensePageContent> createState() => _LicensePageContentState();
}

class _LicensePageContentState extends State<_LicensePageContent> {
  // パッケージ詳細はローカル`Navigator`へpushされ、外側から
  // push/popを購読する手段が無い為、開閉を一定間隔で確認して親へ伝える。
  Timer? _pollTimer;
  bool _detailOpen = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final open =
          _findLicenseDetailNavigator(widget.navigatorKey)?.canPop() ?? false;
      if (open == _detailOpen) return;
      _detailOpen = open;
      widget.onDetailChanged(open);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 広い時は一覧の右に本文を並べ、狭い時は本文を右からスライドして重ねる
        // （`SlideBackPageTransitionsBuilder`、2026-10-16）。
        if (constraints.maxWidth >= _kLicenseSplitMinWidth) {
          return const _LicenseSplitView();
        }
        return Theme(
          data: Theme.of(context).copyWith(
            pageTransitionsTheme: SlideBackPageTransitionsBuilder.theme,
          ),
          child: Navigator(
            key: widget.navigatorKey,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (context) => _LicenseListView(
                onOpen: (package, entries) =>
                    widget.navigatorKey.currentState?.push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: _LicenseDetailView(
                            package: package,
                            entries: entries,
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 一覧と本文を左右に並べる最小の幅。
const _kLicenseSplitMinWidth = 720.0;

/// 一覧（左）と選んだパッケージの本文（右）を並べる（2026-11-06）。
class _LicenseSplitView extends StatefulWidget {
  const _LicenseSplitView();

  @override
  State<_LicenseSplitView> createState() => _LicenseSplitViewState();
}

class _LicenseSplitViewState extends State<_LicenseSplitView> {
  String? _package;
  List<LicenseEntry> _entries = const [];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _kAboutPaneWidth,
          child: _LicenseListView(
            selected: _package,
            onOpen: (package, entries) => setState(() {
              _package = package;
              _entries = entries;
            }),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _package == null
              ? const SizedBox.shrink()
              : _LicenseDetailView(
                  key: ValueKey(_package),
                  package: _package!,
                  entries: _entries,
                ),
        ),
      ],
    );
  }
}

/// パッケージ名ごとにまとめたライセンスを読み込む（2026-11-06）。
Future<Map<String, List<LicenseEntry>>> _loadLicenses() async {
  final byPackage = <String, List<LicenseEntry>>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      byPackage.putIfAbsent(package, () => []).add(entry);
    }
  }
  return byPackage;
}

/// ライセンス一覧（2026-11-06）。標準の`LicensePage`をやめ、設定の他の画面と同じ
/// [SettingsTile]・[GekigaSectionHeader]で組む。4つのUIスタイルの見た目は部品側が持つ。
class _LicenseListView extends StatefulWidget {
  const _LicenseListView({required this.onOpen, this.selected});

  final void Function(String package, List<LicenseEntry> entries) onOpen;

  /// 本文を開いているパッケージ（左右に並べる時の選択表示）。
  final String? selected;

  @override
  State<_LicenseListView> createState() => _LicenseListViewState();
}

class _LicenseListViewState extends State<_LicenseListView> {
  late final Future<Map<String, List<LicenseEntry>>> _future = _loadLicenses();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, List<LicenseEntry>>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const DelayedSpinner();
          }
          final names = data.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final name in names)
                SettingsTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(name),
                  trailing: Text('${data[name]!.length}'),
                  selected: name == widget.selected,
                  onTap: () => widget.onOpen(name, data[name]!),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// パッケージ1件のライセンス本文（2026-11-06）。一覧の右に並べる（狭い時は重ねる）。
/// ライセンス1件を1つの[SettingsTile]に入れ、UIスタイルに沿った見た目にする。
class _LicenseDetailView extends StatelessWidget {
  const _LicenseDetailView({
    super.key,
    required this.package,
    required this.entries,
  });

  final String package;
  final List<LicenseEntry> entries;

  String _text(LicenseEntry entry) {
    final buffer = StringBuffer();
    for (final p in entry.paragraphs) {
      if (p.indent == LicenseParagraph.centeredIndent) {
        buffer.writeln(p.text);
      } else {
        buffer.writeln('${'    ' * p.indent}${p.text}');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          GekigaSectionHeader(package),
          for (final entry in entries)
            SettingsTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              // 文字色は指定しない（劇画の黒いブロックの白文字・版画の黒文字を壊さない）。
              title: Text(
                _text(entry),
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}

/// アカウントカテゴリの中身。旧: Rhing Seed／プロフィール名／セキュリティ／
/// QRコードログイン／ログアウト／アカウント削除の各サブフォルダを、
/// 見出し付きセクションとして1ページにまとめた。
class _AccountPage extends ConsumerWidget {
  const _AccountPage({
    required this.strings,
    required this.currentUser,
    required this.onOpenResidence,
  });

  final Strings strings;
  final AppUser currentUser;

  /// 居住地の変更を開く。`_SettingsTabState`の`_showResidence`を切り替えるだけ。
  final VoidCallback onOpenResidence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveSeed =
        ref.watch(watchedUserProvider(currentUser.userId)).value?.rhingSeed ??
        currentUser.rhingSeed;
    Future<void> changeSeed() async {
      final changed = await RhingSeedChangeDialog.show(
        context,
        userId: currentUser.userId,
        currentSeed: liveSeed,
      );
      if (changed == true && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.rhingSeedChangeDone)));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionHeader(strings.settingsAccountInfoSection),
        _CopyableInfoRow(
          label: strings.settingsRhingSeedLabel,
          // 変更後すぐ表示が替わるよう、保存済みの住人を購読して使う。
          value: '@$liveSeed',
          // 劇画では、箱が白地（文字は黒）なので、標準の`IconButton`だと白い印が白地に
          // 溶けて見えない。コピーのボタンと同じ黒いバッジにする（2026-11-08）。
          trailing: ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
              ? Tooltip(
                  message: strings.settingsRhingSeedChange,
                  child: GekigaIconButton(
                    icon: Icons.edit_outlined,
                    onPressed: changeSeed,
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: strings.settingsRhingSeedChange,
                  onPressed: changeSeed,
                ),
        ),
        _SeedSearchableRow(strings: strings, currentUser: currentUser),
        // 居住地（伝書鳩・安否確認用の自己申告、2026-10-16追加）。
        _ActionRow(label: strings.settingsResidence, onTap: onOpenResidence),
        const Divider(height: 24),
        _SectionHeader(strings.settingsSecurity),
        _TwoFactorRow(strings: strings, rhingSeed: currentUser.rhingSeed),
        _ActionRow(
          label: strings.settingsPasskey,
          onTap: () => PasskeyManagementDialog.show(context),
        ),
        _QrLoginRow(strings: strings),
        // AIエージェント連携（bot API、2026-11-09）。自分のAIに全ての会話を
        // 読ませ、返信させるためのトークンを作る。
        _ActionRow(
          label: strings.assistantTitle,
          onTap: () => AiIntegrationDialog.show(context, ref, currentUser),
        ),
        // パスコードロック（2026-11-06、設定>使い心地から移動）。端末ローカルのセキュア
        // ストレージ・生体認証に依存するので、管理画面には出さない（この画面は利用者用）。
        _PasscodeLockFolder(strings: strings, showHeader: false),
        const Divider(height: 24),
        _SectionHeader(strings.settingsGoogleCalendarSyncSectionTitle),
        _GoogleCalendarSyncRow(strings: strings, currentUser: currentUser),
        const Divider(height: 24),
        _SectionHeader(strings.kiwamiSectionTitle),
        _KiwamiRow(strings: strings, currentUser: currentUser),
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
            showAppDialog<void>(
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
/// 一覧はライブ購読の為、譲渡が完了すると自動的にその広場が消え、
/// 全て消えると「続ける」が押せるようになる。
/// 極みの購入／契約の管理の1行（2026-10-18追加）。極みでなければStripeの決済リンクを
/// 購入者のuid付きで開き、極みなら解約・カード変更用のカスタマーポータルを開く。
class _KiwamiRow extends ConsumerWidget {
  const _KiwamiRow({required this.strings, required this.currentUser});

  final Strings strings;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kiwami = isKiwami(currentUser);
    return _ActionRow(
      label: kiwami ? strings.kiwamiManage : strings.kiwamiPurchase,
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final Uri uri;
        if (kiwami) {
          try {
            uri = await ref
                .read(userRepositoryProvider)
                .createKiwamiPortalUrl();
          } catch (error) {
            // 契約が無い（手動付与など）時だけ「見つからない」と案内し、
            // それ以外（Stripe側の設定・鍵の不備等）は別の文言にする。
            final notFound =
                error is FirebaseFunctionsException &&
                error.code == 'not-found';
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  notFound
                      ? strings.kiwamiManageFailed
                      : strings.kiwamiManageUnavailable,
                ),
              ),
            );
            return;
          }
        } else {
          uri = kiwamiPurchaseUri(currentUser.userId);
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

class _OwnerGroupsGuardDialog extends ConsumerWidget {
  const _OwnerGroupsGuardDialog({required this.currentUser});

  final AppUser currentUser;

  /// trueが返れば、削除操作の続き（確認ダイアログ）へ進んでよいという合図。
  static Future<bool> show(BuildContext context, AppUser currentUser) async {
    final proceed = await showAppDialog<bool>(
      context: context,
      builder: (_) => _OwnerGroupsGuardDialog(currentUser: currentUser),
    );
    return proceed ?? false;
  }

  Future<void> _openTransfer(BuildContext context, WidgetRef ref, Group group) {
    return showAppDialog<void>(
      context: context,
      builder: (_) => glassAwareDialog(
        isGlass: ref.read(appUiStyleProvider) == AppUiStyle.glass,
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
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}

enum _DeleteAccountChoice { grace, immediate }

/// アカウント削除ボタンから開く選択ポップアップ（2026-08-11、それまでの
/// 「通常削除」「即時削除」2つの操作行＋各々の`AlertDialog`確認という
/// 2段階UIを、1つの選択ポップアップに統合）。「30日後に削除」「今直ぐ削除」
/// （取り消せない旨をカード内に明記）「やめる」を縦に並べたカード形式で、
/// タップした時点でその場の1操作として確定する（従来のような2段階目の
/// 確認ダイアログは挟まない）。
Future<_DeleteAccountChoice?> _showDeleteAccountDialog(
  BuildContext context,
  Strings strings,
) {
  return showAppDialog<_DeleteAccountChoice>(
    context: context,
    builder: (context) => glassAwareDialog(
      isGlass:
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(appUiStyleProvider) ==
          AppUiStyle.glass,
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
  const _ApplicationPage({required this.strings, this.showNavChips = true});

  final Strings strings;

  /// 下部メニューチップの揃え・並びの設定を出すか。管理画面（[ApplicationSettingsView]）は
  /// 別のナビ（`ChipNavShell`）で、この設定の対象外のため出さない（2026-11-01）。
  final bool showNavChips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「フォントカラー」（旧・文字色）は劇画スタイル選択中は対象外
    // （固定モノクロ配色の為、`_TextColorFolder`参照）。以前は
    // `_DesignFolder`内に埋め込まれていたが、2026-09-15にUIスタイルと
    // フォントデザインの間へ独立させた。
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // 項目のまとまり毎に分け、広い画面では横に並べて、スクロール無しで全部に
    // 届くようにする（2026-11-06）。`weight`は縦の高さの目安（列への振り分け用）。
    return _MultiColumnSections(
      // 横に並ぶ時は、列ごとに縦スクロールする（2026-11-06）。
      scrollPerColumn: true,
      storageId: 'application',
      sections: [
        // 劇画UI選択中は、外観（ライト/ダーク）が見た目に効かない為、項目ごと
        // 表示しない（2026-10-31、以前はグレーアウトして案内を出していた）。
        if (!isGekiga) (weight: 220, child: AppearanceFolder(strings: strings)),
        (
          weight: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(strings.settingsSubUI),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  strings.settingsUIDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              UiStyleFolder(strings: strings),
            ],
          ),
        ),
        // 画面遷移はUIの直下に置く（2026-11-06）。
        (weight: 300, child: SlideTransitionFolder(strings: strings)),
        (weight: 330, child: AccentColorFolder(strings: strings)),
        if (!isGekiga) (weight: 280, child: const _TextColorFolder()),
        (weight: 230, child: TextSizeFolder(strings: strings)),
        (
          weight: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(strings.settingsFontDesign),
              FontDesignFolder(strings: strings),
            ],
          ),
        ),
        if (showNavChips)
          (
            weight: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(strings.settingsNavChipsTitle),
                NavChipLayoutFolder(strings: strings),
                const Divider(height: 24),
                _SlidePickSwitch(strings: strings),
              ],
            ),
          ),
        (weight: 300, child: _LanguageFolder(strings: strings)),
        (weight: 180, child: TimeFormatFolder(strings: strings)),
      ],
    );
  }
}

/// 設定ページの項目のまとまりを、幅に応じて横に並べる（2026-11-06）。狭い時（1列）は従来どおり
/// 縦に並べて区切り線を挟む。広い時は、まとまりの順を保ったまま高さの目安（`weight`）で
/// 列に振り分け、全体を1つのスクロールにまとめる（収まれば、スクロールしなくてよい）。
class _MultiColumnSections extends StatelessWidget {
  const _MultiColumnSections({
    required this.sections,
    this.columnSplit,
    this.scrollPerColumn = false,
    this.storageId,
  });

  final List<({double weight, Widget child})> sections;

  /// 列数が`columnSplit.length`に一致した時だけ、高さの目安に依らず、先頭から順に
  /// 各列へ入れるまとまりの数。例: `[3, 1, 1]`は左3・中央1・右1。
  final List<int>? columnSplit;

  /// 複数列の時、全体で1つではなく、列ごとに縦スクロールさせる（高さが決まっている時だけ）。
  final bool scrollPerColumn;

  /// 指定すると、スクロール位置を別のカテゴリへ移って戻っても保つ（`PageStorageKey`）。
  final String? storageId;

  PageStorageKey<String>? _keyFor(String part) =>
      storageId == null ? null : PageStorageKey<String>('$storageId-$part');

  /// 1列あたりの最小幅。これ未満の幅では列を増やさない。
  static const double _minColumnWidth = 420;
  static const int _maxColumns = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / _minColumnWidth)
            .floor()
            .clamp(1, math.min(_maxColumns, sections.length))
            .toInt();
        if (columns == 1) {
          return ListView(
            key: _keyFor('list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                sections[i].child,
              ],
            ],
          );
        }
        final total = sections.fold<double>(0, (sum, s) => sum + s.weight);
        final groups = List.generate(columns, (_) => <Widget>[]);
        var cumulative = 0.0;
        final split = columnSplit;
        if (split != null && split.length == columns) {
          var next = 0;
          for (var c = 0; c < columns; c++) {
            for (var n = 0; n < split[c]; n++) {
              groups[c].add(sections[next++].child);
            }
          }
          cumulative = double.infinity;
        }
        for (final section in sections) {
          if (cumulative == double.infinity) break;
          // 区間の中央がどの列の範囲に入るかで振り分ける（順序を保つ）。
          final mid = cumulative + section.weight / 2;
          final index = (mid / (total / columns))
              .floor()
              .clamp(0, columns - 1)
              .toInt();
          groups[index].add(section.child);
          cumulative += section.weight;
        }
        Widget columnOf(int c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < groups[c].length; i++) ...[
              if (i > 0) const Divider(height: 24),
              groups[c][i],
            ],
          ],
        );
        if (scrollPerColumn && constraints.hasBoundedHeight) {
          // 列ごとに独立して縦スクロールする（他の列は動かない）。
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < groups.length; c++) ...[
                if (c > 0) const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    key: _keyFor('col$c'),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: columnOf(c),
                  ),
                ),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          key: _keyFor('all'),
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < groups.length; c++) ...[
                if (c > 0) const SizedBox(width: 16),
                Expanded(child: columnOf(c)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 管理画面（`lib/features/admin/`）の設定タブ。利用者画面の設定>
/// アプリケーションと同じ項目（外観・UI・アクセントカラー・フォントカラー・
/// フォントデザイン・言語・時刻の表示方法）を、パスコードロック以外について
/// そのまま表示する（2026-10-10追加）。設定の保存先は利用者画面と同じ
/// （端末のSharedPreferences＋管理者本人の`users/{uid}.preferences`）で、
/// 管理画面で変えると同じアカウントの利用者画面にも反映される。
class ApplicationSettingsView extends ConsumerWidget {
  const ApplicationSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      // 幅の頭打ちを外し、広い窓では項目を複数列に並べる（2026-11-07）。
      child: _SettingsPage(
        maxWidth: double.infinity,
        child: _ApplicationPage(strings: strings, showNavChips: false),
      ),
    );
  }
}

/// フォントサイズ（小・中・大）の選択（2026-11-05）。アプリ全体の文字の大きさと、
/// 「アイコン＋寄合一覧」の幅・アイコンに効く。端末毎に保存。
class TextSizeFolder extends ConsumerWidget {
  const TextSizeFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appTextSizeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    void select(AppTextSize size) =>
        ref.read(appTextSizeProvider.notifier).setSize(size);
    final options = [
      (size: AppTextSize.small, label: strings.settingsTextSizeSmall),
      (size: AppTextSize.medium, label: strings.settingsTextSizeMedium),
      (size: AppTextSize.large, label: strings.settingsTextSizeLarge),
    ];
    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final o in options) o.size.hashCode],
            selectedFlags: [for (final o in options) current == o.size],
            children: [
              for (final o in options)
                GekigaTileContent(
                  selected: current == o.size,
                  leading: AppRadioMark(
                    selected: current == o.size,
                    color: (current == o.size)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
                  ),
                  title: Text(o.label),
                  onTap: () => select(o.size),
                ),
            ],
          )
        : RadioGroup<AppTextSize>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final o in options)
                  AppRadioListTile<AppTextSize>(
                    value: o.size,
                    title: Text(o.label),
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
          child: GekigaSectionHeader(strings.settingsTextSizeTitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsTextSizeSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        control,
      ],
    );
  }
}

/// 外観（ライト/ダーク/端末に合わせる）の選択（2026-09-15、`_DesignFolder`
/// から分離。以前はアクセントカラーと同じウィジェット内にまとめていたが、
/// 設定画面の項目順を「外観→UI→アクセントカラー→…」に揃える為、
/// UIスタイル選択（`UiStyleFolder`）を挟んで別ウィジェットにした）。
class AppearanceFolder extends ConsumerWidget {
  const AppearanceFolder({required this.strings});

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
                  leading: AppRadioMark(
                    selected: themeMode == option.mode,
                    color: (themeMode == option.mode)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<ThemeMode>(
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
          child: GekigaSectionHeader(strings.settingsAppearance),
        ),
        // 劇画UI選択中は外観（ライト/ダーク/端末に合わせる）を変更不可にする
        // （グレーアウト＋操作無効化）。themeModeに関わらず常に同じ見た目を
        // 返す設計の為、この設定を変えても効果が無い（2026-08-04追加）。
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
            // 左右の余白は付けない（他のラジオの一覧と同じ位置に揃える、2026-11-06）。
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: appearanceControl,
            ),
          ),
        ),
      ],
    );
  }
}

/// アクセントカラー（フラットUI/ガラスUI）・劇画UIの背景色の選択
/// （2026-09-15、`_DesignFolder`から分離。上記[AppearanceFolder]参照）。
class AccentColorFolder extends ConsumerStatefulWidget {
  const AccentColorFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<AccentColorFolder> createState() => _AccentColorFolderState();
}

/// アクセントカラーのプリセット（8桁hex＝RRGGBBAA）。フラット/ガラス/劇画の
/// 3スタイル共通の1リスト（2026-09-15、以前はフラット/ガラス用の
/// `_kAccentColorPresets`と劇画用の`_kGekigaBackgroundColorPresets`に
/// 分かれていたが、中身は同じRGB5色だったため統合した）。劇画UIの背景色は
/// 常に不透明として扱う（`GekigaBackgroundColorNotifier.setColor`参照）ため、
/// 末尾のアルファは劇画側では単に無視される。ユーザーが長押しで削除した
/// 要素は`removedDefaultColorPresetsProvider`側の集合で管理し、この
/// リスト自体からは取り除かない（削除は表示フィルタで実現し、復活手段は
/// 設けない）。固定プリセットの一覧は`kDefaultColorPresets`（`lib/utils/color_presets.dart`）。
class _AccentColorFolderState extends ConsumerState<AccentColorFolder> {
  late final TextEditingController _hexController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: ref.read(accentColorProvider).toHexString().replaceFirst('#', ''),
    );
    final style = ref.read(appUiStyleProvider);
    if (style == AppUiStyle.gekiga || style == AppUiStyle.block) {
      _hexController.text = _fieldText(_hexController.text, true);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  /// 劇画・ブロックは透明度を使わない（6桁まで、プリセットの末尾のアルファも
  /// 見せない、2026-11-06）。
  bool get _opaqueOnly {
    final style = ref.read(appUiStyleProvider);
    return style == AppUiStyle.gekiga || style == AppUiStyle.block;
  }

  /// 入力欄に出す文字列（不透明のみのスタイルでは先頭6桁）。
  String _fieldText(String hex, bool opaqueOnly) {
    final h = hex.replaceFirst('#', '').toUpperCase();
    return opaqueOnly && h.length > 6 ? h.substring(0, 6) : h;
  }

  /// 6桁・8桁を入力し終えたら、決定ボタンを押さずに即時反映する（2026-10-31）。
  void _applyHexIfComplete(String text) {
    final length = text.replaceFirst('#', '').length;
    if (length != 6 && (length != 8 || _opaqueOnly)) {
      if (_errorText != null) setState(() => _errorText = null);
      return;
    }
    _applyHexInput();
  }

  void _applyHexInput() {
    final color = tryParseHexColor(_hexController.text);
    if (color == null) {
      setState(() => _errorText = widget.strings.settingsHexColorFormatError);
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
      _hexController.text = _fieldText(hex, _opaqueOnly);
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
      for (final hex in kDefaultColorPresets)
        if (!removedDefaultHex.contains(hex)) tryParseHexColor(hex)!,
    ];
    // 劇画UIは背景色を常に不透明として扱うため、アルファ差だけの重複は
    // 同一色とみなして弾く（同じ見た目の色が2つのスウォッチとして並ぶのを
    // 防ぐ）。フラット/ガラスは従来通りアルファ込みの完全一致で比較する。
    bool sameColor(Color a, Color b) =>
        _opaqueOnly ? a.withAlpha(0xFF) == b.withAlpha(0xFF) : a == b;
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
    // 劇画UIの`gekigaBackgroundColorProvider`で使い回している為、
    // `UiStyleFolder`（同じ`_ApplicationPage`内の兄弟）でスタイルを
    // 切り替えた瞬間に、表示中の値を新しく有効になった側のプロバイダの
    // 現在値へリセットする。build中に`_hexController`を直接書き換えると
    // GekigaTextField/TextFieldという別ウィジェット間の切り替え時に
    // タイミング次第で不安定になる為、`ref.listen`のコールバック内で
    // 安全にsetStateする。
    ref.listen<AppUiStyle>(appUiStyleProvider, (previous, next) {
      if (previous == next) return;
      final color = next == AppUiStyle.gekiga
          ? ref.read(gekigaBackgroundColorProvider)
          : ref.read(accentColorProvider);
      setState(() {
        _errorText = null;
        _hexController.text = _fieldText(
          color.toHexString(),
          next == AppUiStyle.gekiga || next == AppUiStyle.block,
        );
      });
    });

    final accentColor = ref.watch(accentColorProvider);
    final customColors = ref.watch(customAccentColorsProvider);
    final gekigaBackgroundColor = ref.watch(gekigaBackgroundColorProvider);
    final uiStyleNow = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyleNow == AppUiStyle.gekiga;
    final opaqueOnly = isGekiga || uiStyleNow == AppUiStyle.block;
    final activeColor = isGekiga ? gekigaBackgroundColor : accentColor;
    final removedDefaultHex = ref.watch(removedDefaultColorPresetsProvider);

    // 劇画UIは背景色を常に不透明として扱うため、選択中判定・登録時の重複
    // チェックはアルファを無視して比較する（そうしないと透明度付きの固定
    // プリセットが劇画側で永遠に「選択中」にならない）。フラット/ガラスは
    // 従来通りアルファ込みの完全一致で比較する。
    bool sameColor(Color a, Color b) =>
        opaqueOnly ? a.withAlpha(0xFF) == b.withAlpha(0xFF) : a == b;

    // 固定プリセット（削除されていないもの）とユーザー登録色を1つの
    // 「プリセット」一覧にまとめる（2026-09-15、以前は「プリセット」
    // 「登録した色」の2セクションに分かれ、劇画UIでは後者を非表示にして
    // いた）。出自を`isDefault`で区別し、長押し削除時にどちらのプロバイダを
    // 更新するか振り分ける。
    final presetEntries = [
      for (final hex in kDefaultColorPresets)
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
        // 劇画は、Rhing Seedの箱（`_CopyableInfoRow`）と同じ作り（ジョイント枠＋縦横の余白
        // 12/8＋標準サイズ36のバッジのボタン）にして、縦幅・ボタンの大きさを揃える。
        // 入力欄は枠・塗り無しの素の`TextField`を、黒い箱の中に置く（2026-11-06）。
        ? GekigaJointedTileList(
            seeds: [_hexController.hashCode],
            selectedFlags: const [false],
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hexController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[0-9a-fA-F]'),
                          ),
                          LengthLimitingTextInputFormatter(opaqueOnly ? 6 : 8),
                        ],
                        style: const TextStyle(color: GekigaColors.onPanel),
                        cursorColor: GekigaColors.onPanel,
                        decoration: InputDecoration(
                          prefixText: '#',
                          prefixStyle: const TextStyle(
                            color: GekigaColors.onPanel,
                          ),
                          hintText: 'F08300',
                          hintStyle: TextStyle(
                            color: GekigaColors.onPanel.withValues(alpha: 0.5),
                          ),
                          errorText: _errorText,
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                        onChanged: _applyHexIfComplete,
                        onSubmitted: (_) => _applyHexInput(),
                      ),
                    ),
                    CopyIconButton(
                      gekiga: true,
                      textBuilder: () => _hexText(_hexController.text),
                    ),
                    GekigaIconButton(
                      icon: Icons.add,
                      onPressed: () => _registerCustomColor(context),
                    ),
                  ],
                ),
              ),
            ],
          )
        : BlockFieldFrame(
            child: TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(opaqueOnly ? 6 : 8),
              ],
              decoration: InputDecoration(
                prefixText: '#',
                hintText: 'F08300',
                errorText: _errorText,
                counterText: '',
                // フラットUIでもこの欄だけガラスUIと同じ見た目
                // （半透明の塗り＋アクセントカラーの縁取り）にする
                // （2026-09-14変更、ユーザー要望）。塗り色は
                // `colorScheme.surfaceContainerHighest`だとフラット/
                // ガラスでアクセントカラーの色味有無が異なり見た目が
                // ズレていた為、`GlassColors`の固定値を直接参照して
                // UIスタイルに関係なく常に同じ色にする（2026-09-15修正）。
                filled: !isBlockTheme(context),
                fillColor:
                    (Theme.of(context).brightness == Brightness.dark
                            ? GlassColors.darkSurfaceBase
                            : GlassColors.lightSurfaceBase)
                        .withValues(alpha: 0.65),
                border: isBlockTheme(context)
                    ? InputBorder.none
                    : OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: activeColor.withValues(alpha: 0.3),
                        ),
                      ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CopyIconButton(
                      textBuilder: () => _hexText(_hexController.text),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: '',
                      onPressed: () => _registerCustomColor(context),
                    ),
                  ],
                ),
              ),
              onChanged: _applyHexIfComplete,
              onSubmitted: (_) => _applyHexInput(),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: GekigaSectionHeader(widget.strings.settingsAccentColor),
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
                  // 色見本の丸は劇画UIでは出さず、その分入力欄を左に詰める（2026-11-01、
                  // 劇画の背景色は画面自体がそのプレビューになる為）。
                  if (!isGekiga) ...[
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
                  ],
                  // 8桁のカラーコードと「＋」が収まる幅に絞る（2026-11-01、以前は行いっぱいに
                  // 広がっていた）。
                  SizedBox(width: 248, child: accentColorField),
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
                        PresetColorSwatch(
                          hex: _fieldText(entry.hex, opaqueOnly),
                          selected: sameColor(entry.color, activeColor),
                          onTap: () => _applyPreset(entry.hex),
                          onLongPress: () async {
                            final confirmed = await confirmDeletePresetColor(
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
/// カラーと違い背景とのコントラストが直接可読性に関わる為、
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
      setState(
        () => _lightErrorText = ref
            .read(appStringsProvider)
            .settingsHexColorFormatError,
      );
      return;
    }
    setState(() => _lightErrorText = null);
    ref.read(textColorLightProvider.notifier).setColor(color);
  }

  void _applyDark() {
    final color = tryParseHexColor(_darkController.text);
    if (color == null) {
      setState(
        () => _darkErrorText = ref
            .read(appStringsProvider)
            .settingsHexColorFormatError,
      );
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
          Flexible(
            // 入力した文字の長さに合わせて欄の横幅を変える（2026-11-06）。
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _colorFieldWidth(context, controller.text, label),
                  child: child,
                ),
              ),
              child: BlockFieldFrame(
                label: label,
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    labelText: isBlockTheme(context) ? null : label,
                    prefixText: '#',
                    hintText: '1C1C1C',
                    errorText: errorText,
                    counterText: '',
                    // アクセントカラーの入力欄と同じ、ガラスUI風の見た目に揃える
                    // （2026-09-14変更、`_DesignFolderState`のアクセントカラー欄参照）。
                    // 塗り色は`GlassColors`の固定値を直接参照し、フラット/ガラスで
                    // 常に同じ色になるようにする（2026-09-15修正、理由は
                    // アクセントカラー欄側のコメント参照）。
                    filled: !isBlockTheme(context),
                    fillColor:
                        (Theme.of(context).brightness == Brightness.dark
                                ? GlassColors.darkSurfaceBase
                                : GlassColors.lightSurfaceBase)
                            .withValues(alpha: 0.65),
                    border: isBlockTheme(context)
                        ? InputBorder.none
                        : OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: color.withValues(alpha: 0.3),
                            ),
                          ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CopyIconButton(
                          textBuilder: () => _hexText(controller.text),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '',
                          onPressed: onReset,
                        ),
                      ],
                    ),
                  ),
                  // 6桁・8桁を入力し終えたら、決定ボタン無しで即時反映する（2026-10-31）。
                  onChanged: (text) {
                    final length = text.replaceFirst('#', '').length;
                    if (length == 6 || length == 8) onApply();
                  },
                  onSubmitted: (_) => onApply(),
                ),
              ),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: GekigaSectionHeader(strings.settingsTextColorTitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            strings.settingsTextColorDescription,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
        ),
        const SizedBox(height: 8),
        // 今の外観（ライト/ダーク、「端末に合わせる」の場合は端末の設定）の
        // 欄だけを表示する（2026-11-06）。もう一方の値は保持したまま。
        if (Theme.of(context).brightness == Brightness.light)
          _colorRow(
            color: textColorLight,
            label: strings.settingsTextColorLightLabel,
            controller: _lightController,
            errorText: _lightErrorText,
            onApply: _applyLight,
            onReset: _resetLight,
          )
        else
          _colorRow(
            color: textColorDark,
            label: strings.settingsTextColorDarkLabel,
            controller: _darkController,
            errorText: _darkErrorText,
            onApply: _applyDark,
            onReset: _resetDark,
          ),
        // アクセントで塗った面の上に乗る文字色（劇画はアクセントを使わないため出さない）。
        if (ref.watch(appUiStyleProvider) != AppUiStyle.gekiga)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _OnAccentColorField(strings: strings),
          ),
      ],
    );
  }
}

/// カラーコード欄の横幅。入力の桁数（最低6桁）だけで決め、ラベルやヒントの長さ・
/// 入力した文字の字形には左右されない。フォントカラー（ライト用・ダーク用）と
/// アクセント上の欄が、同じ桁数なら必ずぴったり同じ幅になる。
double _colorFieldWidth(BuildContext context, String text, String label) {
  final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  double measure(String t) {
    final painter = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  final digits = text.replaceFirst('#', '').length;
  final body = measure('D' * (digits < 6 ? 6 : digits));
  // 先頭の「#」+ 右端のボタン2つ（各48）+ 左右の内側余白（各16）+ 余裕。
  return body + measure('#') + 96 + 32 + 8;
}

/// カラーコード欄の内容を、コピーする文字（`#RRGGBB`形式、空欄なら空文字）にする。
String _hexText(String text) {
  final hex = text.trim().replaceFirst('#', '');
  return hex.isEmpty ? '' : '#${hex.toUpperCase()}';
}

/// アクセントカラーのプリセット1つ分の円形スウォッチ。タップで即適用する。
class PresetColorSwatch extends StatelessWidget {
  const PresetColorSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  /// 削除導線用のコールバック。固定プリセット・ユーザー登録色のどちらも
  /// この`PresetColorSwatch`を共通で使うため、呼び出し元
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
/// 「言語・用語設定によってブロックの大きさが変わる為、全てに対応するのが
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
                  leading: AppRadioMark(
                    selected: currentLocale == locale,
                    color: (currentLocale == locale)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<AppLocale>(
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
          child: GekigaSectionHeader(strings.settingsDisplayLanguage),
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
class UiStyleFolder extends ConsumerWidget {
  const UiStyleFolder({required this.strings});

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
          AppUiStyle.block.hashCode,
          AppUiStyle.gekiga.hashCode,
        ],
        selectedFlags: [
          style == AppUiStyle.flat,
          style == AppUiStyle.glass,
          style == AppUiStyle.block,
          style == AppUiStyle.gekiga,
        ],
        children: [
          GekigaTileContent(
            selected: style == AppUiStyle.flat,
            leading: AppRadioMark(
              selected: style == AppUiStyle.flat,
              color: (style == AppUiStyle.flat)
                  ? GekigaColors.panel
                  : GekigaColors.onPanel,
            ),
            title: Text(strings.settingsUiStyleFlatLabel),
            onTap: () => select(AppUiStyle.flat),
          ),
          GekigaTileContent(
            selected: style == AppUiStyle.glass,
            leading: AppRadioMark(
              selected: style == AppUiStyle.glass,
              color: (style == AppUiStyle.glass)
                  ? GekigaColors.panel
                  : GekigaColors.onPanel,
            ),
            title: Text(strings.settingsUiStyleGlassLabel),
            onTap: () => select(AppUiStyle.glass),
          ),
          GekigaTileContent(
            selected: style == AppUiStyle.block,
            leading: AppRadioMark(
              selected: style == AppUiStyle.block,
              color: (style == AppUiStyle.block)
                  ? GekigaColors.panel
                  : GekigaColors.onPanel,
            ),
            title: Text(strings.settingsUiStyleBlockLabel),
            onTap: () => select(AppUiStyle.block),
          ),
          GekigaTileContent(
            selected: style == AppUiStyle.gekiga,
            leading: AppRadioMark(
              selected: style == AppUiStyle.gekiga,
              color: (style == AppUiStyle.gekiga)
                  ? GekigaColors.panel
                  : GekigaColors.onPanel,
            ),
            title: Text(strings.settingsUiStyleGekigaLabel),
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
          AppRadioListTile<AppUiStyle>(
            value: AppUiStyle.flat,
            title: Text(strings.settingsUiStyleFlatLabel),
          ),
          AppRadioListTile<AppUiStyle>(
            value: AppUiStyle.glass,
            title: Text(strings.settingsUiStyleGlassLabel),
          ),
          AppRadioListTile<AppUiStyle>(
            value: AppUiStyle.block,
            title: Text(strings.settingsUiStyleBlockLabel),
          ),
          AppRadioListTile<AppUiStyle>(
            value: AppUiStyle.gekiga,
            title: Text(strings.settingsUiStyleGekigaLabel),
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
class FontDesignFolder extends ConsumerStatefulWidget {
  const FontDesignFolder({required this.strings});

  final Strings strings;

  @override
  ConsumerState<FontDesignFolder> createState() => _FontDesignFolderState();
}

class _FontDesignFolderState extends ConsumerState<FontDesignFolder> {
  // 開閉は別のカテゴリへ移って戻っても保つ（`settingsExpansionProvider`）。
  static const _stateKey = 'application.fontDesign';
  bool get _expanded =>
      ref.read(settingsExpansionProvider).expandedOr(_stateKey, false);
  set _expanded(bool value) =>
      ref.read(settingsExpansionProvider.notifier).set(_stateKey, value);

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final locale = ref.watch(appLocaleProvider);
    // 選択中のフォントがこの表示言語で使えない場合は、実際に適用される
    // フォント（既定）を選択中として見せる。
    // 極みでない人は、極み限定フォントを保存していても標準を選択中として見せる
    // （2026-10-17）。
    final userId = ref.watch(authStateProvider).value?.uid;
    final kiwami = userId != null && ref.watch(isKiwamiProvider(userId));
    final design = ref
        .watch(fontDesignProvider)
        .resolvedFor(locale, kiwami: kiwami);
    final available = FontDesign.availableFor(locale);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(FontDesign value) {
      // 極み限定のフォントは、極みの人だけが選べる。
      if (value.isKiwamiExclusive && !kiwami) {
        showKiwamiOnlyDialog(
          context,
          strings,
          body: strings.kiwamiOnlyFontBody,
        );
        return;
      }
      ref.read(fontDesignProvider.notifier).setDesign(value);
    }

    // 2026-09-26: 蔵のフォントデザイン素材選択（`_FontDesignMaterialDialog`）
    // でも同じラベル一覧が必要になった為、`Strings.fontDesignLabel`に
    // 一本化した（以前はここに25分岐のswitchを直書きしていた）。
    String labelFor(FontDesign value) => strings.fontDesignLabel(value);

    final hasMore = available.length > kFontDesignPreviewCount;
    final visibleDesigns = _expanded
        ? available
        : available.take(kFontDesignPreviewCount);
    final remaining = available.length - visibleDesigns.length;

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
              leading: AppRadioMark(
                selected: design == value,
                color: (design == value)
                    ? GekigaColors.panel
                    : GekigaColors.onPanel,
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
            AppRadioListTile<FontDesign>(
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
            SettingsTile(
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

class ChatLayoutFolder extends ConsumerWidget {
  const ChatLayoutFolder({required this.strings});

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
                  leading: AppRadioMark(
                    selected: style == option.value,
                    color: (style == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<ChatLayoutStyle>(
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
          child: GekigaSectionHeader(strings.settingsChatLayoutTitle),
        ),
        control,
      ],
    );
  }
}

/// 画面遷移の動きの種類の選択（2026-11-04追加、端末毎の個人設定）。
class SlideTransitionFolder extends ConsumerWidget {
  const SlideTransitionFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(slideTransitionStyleProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void select(SlideTransitionStyle value) =>
        ref.read(slideTransitionStyleProvider.notifier).setStyle(value);

    final options = [
      (
        value: SlideTransitionStyle.slideBlur,
        title: strings.settingsSlideTransitionSlideBlur,
      ),
      (
        value: SlideTransitionStyle.slide,
        title: strings.settingsSlideTransitionSlide,
      ),
      (
        value: SlideTransitionStyle.suck,
        title: strings.settingsSlideTransitionSuck,
      ),
      (
        value: SlideTransitionStyle.pop,
        title: strings.settingsSlideTransitionPop,
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
                  leading: AppRadioMark(
                    selected: style == option.value,
                    color: (style == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
                  ),
                  title: Text(option.title),
                  onTap: () => select(option.value),
                ),
            ],
          )
        : RadioGroup<SlideTransitionStyle>(
            groupValue: style,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  AppRadioListTile<SlideTransitionStyle>(
                    value: option.value,
                    title: Text(option.title),
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
          child: GekigaSectionHeader(strings.settingsSlideTransitionTitle),
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
class TalksListLayoutFolder extends ConsumerWidget {
  const TalksListLayoutFolder({required this.strings});

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
                  leading: AppRadioMark(
                    selected: style == option.value,
                    color: (style == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<TalksListLayoutStyle>(
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
          child: GekigaSectionHeader(strings.settingsTalksListLayoutTitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsTalksListLayoutNote,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        control,
        if (style == TalksListLayoutStyle.iconSplit) ...[
          _MirrorSwitch(strings: strings),
          _AdjustWidthButton(strings: strings),
          // 寄合一覧の横スワイプの割り当ては、寄合一覧だけを出すスマホ（画面の短辺が
          // 600px未満）でだけ意味がある（2026-11-08）。
          if (MediaQuery.sizeOf(context).shortestSide < kNavChipWideBreakpoint)
            _RoomListSwipeSetting(strings: strings),
        ] else if (classifyDevice(context) == DeviceClass.computer)
          // コンピューターの左右分割でも、語らい一覧の幅を変えられる。
          _AdjustWidthButton(strings: strings),
      ],
    );
  }
}

/// 縦表示（狭い画面）の下部メニューチップの揃え（左・中央・右）と並びの設定
/// （2026-11-01）。並びは`ReorderableListView`のドラッグで入れ替える。ホーム画面は
/// 各タブの論理インデックスを変えず、表示の並びだけを入れ替える（`home_screen.dart`）。
class NavChipLayoutFolder extends ConsumerWidget {
  const NavChipLayoutFolder({super.key, required this.strings});

  final Strings strings;

  static const _icons = {
    HomeTabId.talk: Icons.forum_outlined,
    HomeTabId.profile: Icons.face_outlined,
    HomeTabId.settings: Icons.settings_outlined,
  };

  String _tabLabel(HomeTabId tab) => switch (tab) {
    HomeTabId.talk => strings.navTalk,
    HomeTabId.profile => strings.navProfile,
    HomeTabId.settings => strings.navSettings,
  };

  /// 広い画面（幅600px以上、`home_screen.dart`の縦並びサイドバー）では上・下、
  /// 狭い画面では左・右の表記にする。
  String _alignLabel(NavChipAlignment alignment, {required bool wide}) =>
      switch (alignment) {
        NavChipAlignment.start =>
          wide
              ? strings.settingsNavChipsAlignTop
              : strings.settingsNavChipsAlignStart,
        NavChipAlignment.center => strings.settingsNavChipsAlignCenter,
        NavChipAlignment.end =>
          wide
              ? strings.settingsNavChipsAlignBottom
              : strings.settingsNavChipsAlignEnd,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(navChipLayoutProvider);
    final notifier = ref.read(navChipLayoutProvider.notifier);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final colorScheme = Theme.of(context).colorScheme;

    // 縦表示（下端の横並び: 左・中央・右）と横表示（左端の縦並び: 上・中央・下）は、
    // 別々に保存する（2026-11-06、以前は共通で「上揃え＝左揃え」だった）。
    Widget alignmentControlFor({
      required NavChipAlignment current,
      required ValueChanged<NavChipAlignment> onSelect,
      required bool forWide,
    }) => isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final a in NavChipAlignment.values) a.hashCode],
            selectedFlags: [
              for (final a in NavChipAlignment.values) current == a,
            ],
            children: [
              for (final a in NavChipAlignment.values)
                GekigaTileContent(
                  selected: current == a,
                  leading: AppRadioMark(
                    selected: current == a,
                    color: (current == a)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
                  ),
                  title: Text(_alignLabel(a, wide: forWide)),
                  onTap: () => onSelect(a),
                ),
            ],
          )
        : RadioGroup<NavChipAlignment>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: Column(
              children: [
                for (final a in NavChipAlignment.values)
                  AppRadioListTile<NavChipAlignment>(
                    value: a,
                    title: Text(_alignLabel(a, wide: forWide)),
                  ),
              ],
            ),
          );
    final alignmentControl = alignmentControlFor(
      current: layout.alignment,
      onSelect: notifier.setAlignment,
      forWide: false,
    );
    final wideAlignmentControl = alignmentControlFor(
      current: layout.wideAlignment,
      onSelect: notifier.setWideAlignment,
      forWide: true,
    );

    // 項目一覧の縦の位置（上・下、縦表示のみ、全スタイル）。
    final listVertical = ref.watch(categoryListVerticalProvider);
    void selectListVertical(CategoryListVertical value) =>
        ref.read(categoryListVerticalProvider.notifier).setVertical(value);
    String verticalLabel(CategoryListVertical v) => switch (v) {
      CategoryListVertical.top => strings.settingsCategoryListVerticalTop,
      CategoryListVertical.bottom => strings.settingsCategoryListVerticalBottom,
    };
    final listVerticalControl = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final v in CategoryListVertical.values) v.hashCode],
            selectedFlags: [
              for (final v in CategoryListVertical.values) listVertical == v,
            ],
            children: [
              for (final v in CategoryListVertical.values)
                GekigaTileContent(
                  selected: listVertical == v,
                  leading: AppRadioMark(
                    selected: listVertical == v,
                    color: (listVertical == v)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
                  ),
                  title: Text(verticalLabel(v)),
                  onTap: () => selectListVertical(v),
                ),
            ],
          )
        : RadioGroup<CategoryListVertical>(
            groupValue: listVertical,
            onChanged: (value) {
              if (value != null) selectListVertical(value);
            },
            child: Column(
              children: [
                for (final v in CategoryListVertical.values)
                  AppRadioListTile<CategoryListVertical>(
                    value: v,
                    title: Text(verticalLabel(v)),
                  ),
              ],
            ),
          );

    final orderControl = Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 220,
        child: _NavChipOrderList(
          order: layout.order,
          onReorder: notifier.setOrder,
          tileBuilder: (tab, handle) {
            // `ListTile`は枠の高さが足りない（劇画の箱の内側など）と中身が下へはみ出し、
            // 文字が縦に中央からずれる為、`Row`で縦中央に揃えて自前で組む。
            final contentColor = isGekiga
                ? GekigaColors.onPanel
                : colorScheme.onSurface;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 12),
                Icon(_icons[tab], color: contentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _tabLabel(tab),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: contentColor,
                      height: 1.0,
                    ),
                  ),
                ),
                Icon(
                  Icons.drag_handle,
                  color: isGekiga
                      ? GekigaColors.onPanel
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
              ],
            );
            // 箱の外枠（劇画は上下の余白3＋枠の黒3＋白線3の左右上下）の分を引いた高さ。
            final tile = SizedBox(
              height: isGekiga
                  ? _NavChipOrderListState.itemHeight - 6 - 12
                  : _NavChipOrderListState.itemHeight,
              child: content,
            );
            if (ref.watch(appUiStyleProvider) == AppUiStyle.block) {
              // 版画: 太枠と硬い影の箱（影の分の余白を含めて1行の高さに収める）。
              return Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 6, 8),
                child: blockMaterialBox(
                  context,
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : colorScheme.surface,
                  child: SizedBox(
                    height: _NavChipOrderListState.itemHeight - 12,
                    child: content,
                  ),
                ),
              );
            }
            if (!isGekiga) return tile;
            // 劇画は単色の黒ベタにせず、他の箱と同じ「黒外枠→白の細い線→黒地」の
            // 直角モノクロボックスで描く。項目同士は縦に少し間を空ける。
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: GekigaStraightMonochromeBox(isMe: false, child: tile),
            );
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsNavChipsDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        // 揃えは今の表示（幅600px以上＝横表示、未満＝縦表示）のぶんだけ出す
        // （2026-11-06。揃えは端末ごとの保存で、その端末の向きが分かれば足りる）。
        if (MediaQuery.sizeOf(context).width >= kNavChipWideBreakpoint) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GekigaSectionHeader(
              strings.settingsNavChipsAlignmentWideTitle,
            ),
          ),
          wideAlignmentControl,
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GekigaSectionHeader(
              strings.settingsNavChipsAlignmentNarrowTitle,
            ),
          ),
          alignmentControl,
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GekigaSectionHeader(strings.settingsNavChipsOrderTitle),
        ),
        orderControl,
        // 項目一覧の縦の位置は、縦表示（幅600px未満）でだけ出す（2026-11-07）。
        if (MediaQuery.sizeOf(context).width < kNavChipWideBreakpoint) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: GekigaSectionHeader(
              strings.settingsCategoryListVerticalTitle,
            ),
          ),
          listVerticalControl,
        ],
      ],
    );
  }
}

/// メニューチップの並び替えリスト。3項目の枠の中だけをドラッグでき、枠の外へは
/// 出ない（`ReorderableListView`は軸・範囲を制限出来ないため自前。2026-11-01）。
/// 項目は背景ごと（劇画の黒いラベルも含めて）一緒に動く。
class _NavChipOrderList extends StatefulWidget {
  const _NavChipOrderList({
    required this.order,
    required this.onReorder,
    required this.tileBuilder,
  });

  final List<HomeTabId> order;
  final ValueChanged<List<HomeTabId>> onReorder;
  final Widget Function(HomeTabId tab, Widget handle) tileBuilder;

  @override
  State<_NavChipOrderList> createState() => _NavChipOrderListState();
}

class _NavChipOrderListState extends State<_NavChipOrderList> {
  static const itemHeight = 56.0;

  HomeTabId? _dragging;
  double _dragTop = 0;

  int get _provisionalIndex {
    final max = widget.order.length - 1;
    return (_dragTop / itemHeight).round().clamp(0, max);
  }

  List<HomeTabId> get _displayOrder {
    final dragging = _dragging;
    if (dragging == null) return widget.order;
    final list = [...widget.order]..remove(dragging);
    list.insert(_provisionalIndex, dragging);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayOrder;
    final maxTop = (widget.order.length - 1) * itemHeight;
    final tabs = [
      for (final t in display)
        if (t != _dragging) t,
      if (_dragging != null) _dragging!,
    ];
    return SizedBox(
      height: widget.order.length * itemHeight,
      child: Stack(
        children: [
          for (final tab in tabs)
            AnimatedPositioned(
              key: ValueKey(tab),
              duration: tab == _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              height: itemHeight,
              top: tab == _dragging
                  ? _dragTop.clamp(0.0, maxTop)
                  : display.indexOf(tab) * itemHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(() {
                  _dragging = tab;
                  _dragTop = widget.order.indexOf(tab) * itemHeight;
                }),
                onVerticalDragUpdate: (details) => setState(() {
                  _dragTop = (_dragTop + details.delta.dy).clamp(0.0, maxTop);
                }),
                onVerticalDragEnd: (_) => _finish(),
                onVerticalDragCancel: _finish,
                child: widget.tileBuilder(tab, const SizedBox.shrink()),
              ),
            ),
        ],
      ),
    );
  }

  void _finish() {
    if (_dragging == null) return;
    final result = _displayOrder;
    setState(() => _dragging = null);
    widget.onReorder(result);
  }
}

/// メッセージの送信時刻表示形式（24時間表記／12時間表記）の切り替え。
class TimeFormatFolder extends ConsumerWidget {
  const TimeFormatFolder({required this.strings});

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
                  leading: AppRadioMark(
                    selected: currentFormat == format,
                    color: (currentFormat == format)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<MessageTimeFormat>(
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
          child: GekigaSectionHeader(strings.settingsTimeFormat),
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
  const _PasscodeLockFolder({required this.strings, this.showHeader = true});

  /// 見出しを出すか。セキュリティの中に置く時は、切り替えの行が同じ名前なので出さない。
  final bool showHeader;

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
    // 他人が勝手に無効化出来ないよう、OFFにする前に現在のパスコードで
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
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: GekigaSectionHeader(strings.settingsPasscodeLockToggleLabel),
          ),
        if (_loading)
          const SizedBox.shrink()
        else ...[
          AppSwitchListTile(
            title: Text(strings.settingsPasscodeLockToggleLabel),
            value: _passcodeEnabled,
            onChanged: _onPasscodeToggle,
          ),
          if (_passcodeEnabled) ...[
            SettingsTile(
              title: Text(strings.settingsPasscodeChangeButton),
              onTap: _onChangePasscode,
            ),
            if (_canUseBiometrics)
              AppSwitchListTile(
                title: Text(strings.settingsPasscodeBiometricToggleLabel),
                value: _biometricEnabled,
                onChanged: _onBiometricToggle,
              ),
          ],
          // 説明文は、切り替え・パスコードを変更・生体認証の各ブロックよりも下に置く
          // （2026-11-09、ユーザー指示）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              strings.settingsPasscodeLockDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
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
    return _MultiColumnSections(
      // 3列の時は、左=ブロック・メッセージの表示・語らい一覧のレイアウト、
      // 中央=カレンダー、右=詳細設定（2026-11-06）。
      columnSplit: const [3, 1, 1],
      storageId: 'talk',
      sections: [
        (
          weight: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(strings.settingsBlockedUsersTitle),
              _BlockedUsersFolder(strings: strings, currentUser: currentUser),
            ],
          ),
        ),
        (weight: 260, child: ChatLayoutFolder(strings: strings)),
        (weight: 300, child: TalksListLayoutFolder(strings: strings)),
        (weight: 520, child: _CalendarSettingsFolder(strings: strings)),
        (
          weight: 120,
          child: SettingsAccordionSection(
            stateKey: 'talk.advanced',
            title: strings.settingsAdvancedSectionTitle,
            // 横に広い画面では最初から開いておく（2026-11-06）。
            initiallyExpanded:
                MediaQuery.sizeOf(context).width >= kNavChipWideBreakpoint,
            children: [
              SendKeyFolder(strings: strings),
              const Divider(height: 24),
              _StickerSendModeFolder(strings: strings),
              const Divider(height: 24),
              _DraftSyncFolder(strings: strings),
              const Divider(height: 24),
              _JoinVideoCameraFolder(strings: strings),
            ],
          ),
        ),
      ],
    );
  }
}

/// 設定>語らい>カレンダー（2026-11-05）。自分のカレンダーの標準を決める。ここで決めた
/// 設定が全てのカレンダーに適用され、語らい毎のカレンダーの歯車から変えられる。
/// 週の始まり・暦・祝日/祭日/宗教上の祝日の選択を、端末とアカウントの両方に保存する。
class _CalendarSettingsFolder extends ConsumerWidget {
  const _CalendarSettingsFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    final background = colorScheme.surface;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final weekStart = ref.watch(calendarWeekStartProvider);
    final system = ref.watch(calendarSystemProvider);
    final holidays = ref.watch(holidaySettingsProvider);
    final residence = ref.watch(holidayCountryProvider).value ?? 'JP';
    final holidayNotifier = ref.read(holidaySettingsProvider.notifier);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GekigaSectionHeader(text),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(strings.calendarSettingsFolderTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            strings.calendarSettingsDefaultNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        label(strings.calendarWeekStartLabel),
        _calendarRadioGroup<CalendarWeekStart>(
          isGekiga: isGekiga,
          current: weekStart,
          options: [
            (
              value: CalendarWeekStart.sunday,
              label: strings.calendarWeekStartSunday,
            ),
            (
              value: CalendarWeekStart.monday,
              label: strings.calendarWeekStartMonday,
            ),
          ],
          onSelected: (value) =>
              ref.read(calendarWeekStartProvider.notifier).setWeekStart(value),
        ),
        label(strings.calendarSystemLabel),
        _calendarRadioGroup<CalendarSystem>(
          isGekiga: isGekiga,
          current: system,
          options: [
            for (final option in CalendarSystem.values)
              (value: option, label: calendarSystemLabelOf(strings, option)),
          ],
          onSelected: (value) =>
              ref.read(calendarSystemProvider.notifier).setSystem(value),
        ),
        label(strings.holidaySettingsTitle),
        Padding(
          // 劇画・版画は行がブロックなので、ラジオのブロックと同じ左端に置く（余白を足さない）。
          padding: EdgeInsets.symmetric(
            horizontal: isGekiga || isBlockTheme(context) ? 0 : 16,
          ),
          child: HolidayCheckboxes(
            gekigaBlocks: isGekiga,
            strings: strings,
            settings: holidays,
            residenceCountry: residence,
            onRegion: (country, enabled) =>
                holidayNotifier.setRegion(country, enabled, residence),
            onObservances: holidayNotifier.setObservances,
            onReligion: holidayNotifier.setReligion,
            foreground: foreground,
            background: background,
          ),
        ),
      ],
    );
  }
}

/// 設定>語らい>カレンダーのラジオの並び。劇画は他の設定と同じ`GekigaJointedTileList`、
/// フラット・ガラスは`RadioGroup`＋`AppRadioListTile`（ラジオは左端）。
Widget _calendarRadioGroup<T>({
  required bool isGekiga,
  required T current,
  required List<({T value, String label})> options,
  required ValueChanged<T> onSelected,
}) {
  if (isGekiga) {
    return GekigaJointedTileList(
      seeds: [for (final o in options) o.value.hashCode],
      selectedFlags: [for (final o in options) current == o.value],
      children: [
        for (final o in options)
          GekigaTileContent(
            selected: current == o.value,
            leading: AppRadioMark(
              selected: current == o.value,
              color: current == o.value
                  ? GekigaColors.panel
                  : GekigaColors.onPanel,
            ),
            title: Text(o.label),
            onTap: () => onSelected(o.value),
          ),
      ],
    );
  }
  return RadioGroup<T>(
    groupValue: current,
    onChanged: (value) {
      if (value != null) onSelected(value);
    },
    child: Column(
      children: [
        for (final o in options)
          AppRadioListTile<T>(value: o.value, title: Text(o.label)),
      ],
    ),
  );
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
  // 開閉は別のカテゴリへ移って戻っても保つ（`settingsExpansionProvider`）。
  static const _stateKey = 'talk.blockedUsers';
  bool get _expanded =>
      ref.read(settingsExpansionProvider).expandedOr(_stateKey, false);
  set _expanded(bool value) =>
      ref.read(settingsExpansionProvider.notifier).set(_stateKey, value);

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
      showAutoDismissBanner(
        context,
        message: widget.strings.genericErrorTemplate(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final blockedIdsAsync = ref.watch(
      blockedUserIdsProvider(widget.currentUser.userId),
    );

    Widget messageView(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
    Widget emptyView() => messageView(strings.settingsBlockedUsersEmpty);

    return blockedIdsAsync.when(
      loading: () => const SizedBox.shrink(),
      // 開発中のホットリロード直後に出る「ProviderContainer ... already disposed」は、
      // 古い画面が破棄済みの状態を読んだだけなので「ブロックしたユーザーはいません」と
      // 表示する。本当に取得できなかった時（権限エラーなど）は「取得に失敗しました」
      // （2026-11-06、ユーザー指示）。どちらも原因はログに残す。
      error: (e, _) {
        debugPrint('[blockedUsers] 取得に失敗: $e');
        final disposed =
            e is StateError && e.message.contains('already disposed');
        return disposed
            ? emptyView()
            : messageView(strings.settingsBlockedUsersLoadFailed);
      },
      data: (blockedIds) {
        if (blockedIds.isEmpty) return emptyView();
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final user in visibleUsers)
                  SettingsTile(
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
                  SettingsTile(
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

class SendKeyFolder extends ConsumerWidget {
  const SendKeyFolder({required this.strings});

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
                  leading: AppRadioMark(
                    selected: mode == option.value,
                    color: (mode == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<SendKeyMode>(
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
          child: GekigaSectionHeader(strings.settingsSendKeyTitle),
        ),
        control,
      ],
    );
  }
}

/// ぺったん（スタンプ）の送信方式（LINE型2タップ確認／Discord型1タップ即送信）
/// の選択。`SendKeyFolder`と同じ2択ラジオ構成を踏襲する（2026-08-13追加）。
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
                  leading: AppRadioMark(
                    selected: mode == option.value,
                    color: (mode == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
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
                  AppRadioListTile<StickerSendMode>(
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
          child: GekigaSectionHeader(strings.settingsStickerSendModeTitle),
        ),
        control,
      ],
    );
  }
}

/// ビデオ通話に応答・参加した時、カメラをオンで入るかのオン/オフ（標準オン）。
class _JoinVideoCameraFolder extends ConsumerWidget {
  const _JoinVideoCameraFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(joinVideoCameraOnProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    void setEnabled(bool value) =>
        ref.read(joinVideoCameraOnProvider.notifier).setEnabled(value);

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: const [0],
        selectedFlags: const [false],
        children: [
          GekigaTileContent(
            selected: false,
            title: Text(strings.settingsCallJoinCameraTitle),
            subtitle: Text(strings.settingsCallJoinCameraSubtitle),
            trailing: AppSwitch(
              value: enabled,
              onChanged: setEnabled,
              onDarkSurface: true,
            ),
            onTap: () => setEnabled(!enabled),
          ),
        ],
      );
    }
    return AppSwitchListTile(
      value: enabled,
      title: Text(strings.settingsCallJoinCameraTitle),
      subtitle: Text(strings.settingsCallJoinCameraSubtitle),
      onChanged: setEnabled,
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
            trailing: AppSwitch(
              value: enabled,
              onChanged: setEnabled,
              onDarkSurface: true,
            ),
            onTap: () => setEnabled(!enabled),
          ),
        ],
      );
    }
    return AppSwitchListTile(
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
/// 参照）。OS/ブラウザ側の許可自体はアプリから取り消せない為、オフに
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
                trailing: AppSwitch(
                  value: enabled,
                  onChanged: setEnabled,
                  onDarkSurface: true,
                ),
                onTap: () => setEnabled(!enabled),
              ),
            ],
          )
        else
          AppSwitchListTile(
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
        // 通知音（メッセージ受信音）はOSのプッシュ通知を経由する為、
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
/// 音源に設定出来る（`UserRepository.uploadCustomSound`参照）。
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

  /// 現在試聴再生中の音源（アセットパス又はURL）。再生ボタンを停止
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
      // 試聴出来ない環境でも設定変更自体はブロックしない。
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
              leading: AppRadioMark(
                selected: selectedValue == preset.id,
                color: (selectedValue == preset.id)
                    ? GekigaColors.panel
                    : GekigaColors.onPanel,
              ),
              title: Text(_labelFor(preset)),
              trailing: previewButton(preset.assetPath),
              onTap: () => _select(preset.id),
            ),
          if (canUpload)
            GekigaTileContent(
              selected: isCustom,
              leading: AppRadioMark(
                selected: isCustom,
                color: (isCustom) ? GekigaColors.panel : GekigaColors.onPanel,
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
            AppRadioListTile<String>(
              value: preset.id,
              title: Text(_labelFor(preset)),
              secondary: previewButton(preset.assetPath),
            ),
          if (canUpload)
            AppRadioListTile<String>(
              value: _customSoundSentinel,
              title: Text(customLabel),
              secondary: customSoundTrailing(),
            ),
        ],
      ),
    );
  }
}

/// ライセンス画面のローカル`Navigator`（パッケージ詳細をpushする）を返す。
/// 2026-11-06に標準の`LicensePage`をやめ自前の画面にしたため、入れ子の`Navigator`は
/// 無く、キーの`Navigator`自体が詳細の開閉を持つ。まだ無ければnull。
NavigatorState? _findLicenseDetailNavigator(GlobalKey<NavigatorState> key) =>
    key.currentState;

/// 設定の中に埋め込む居住地の変更（2026-10-17追加）。現在の回答を読み込んでから
/// 居住地アンケートの入力欄（[ResidenceSurveyScreen]の埋め込み表示）を出す。
class _ResidenceEditor extends ConsumerStatefulWidget {
  const _ResidenceEditor({required this.userId, required this.onCompleted});

  final String userId;
  final VoidCallback onCompleted;

  @override
  ConsumerState<_ResidenceEditor> createState() => _ResidenceEditorState();
}

class _ResidenceEditorState extends ConsumerState<_ResidenceEditor> {
  late final Future<Residence?> _future = ref
      .read(residenceRepositoryProvider)
      .getResidence(widget.userId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Residence?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return ResidenceSurveyScreen(
          userId: widget.userId,
          initial: snapshot.data,
          isEditing: true,
          embedded: true,
          onCompleted: widget.onCompleted,
        );
      },
    );
  }
}

/// 「アイコン＋寄合一覧」を左右反転するスイッチ（2026-11-01、標準オフ）。
/// レイアウトが「アイコン＋寄合一覧」の時だけ表示する（呼び出し側で出し分け）。
/// 区切り線の「幅を調整する」モードに入るボタン（2026-11-05、右寄せ）。語らいタブへ
/// 移って区切り線がつまみになる。
class _AdjustWidthButton extends ConsumerWidget {
  const _AdjustWidthButton({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void startAdjusting() {
      ref.read(iconSplitAdjustingProvider.notifier).set(true);
      ref.read(homeSelectedTabProvider.notifier).set(kTalksTabIndex);
    }

    // 見出し→説明→押せるブロック、の順に並べる（2026-11-06）。
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GekigaSectionHeader(strings.settingsIconSplitAdjustTitle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              strings.settingsIconSplitAdjustNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          SettingsTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(strings.settingsIconSplitAdjustButton),
            trailing: const Icon(Icons.chevron_right),
            onTap: startAdjusting,
          ),
        ],
      ),
    );
  }
}

/// 縦表示（スマホ）の「アイコン＋寄合一覧」で、寄合一覧の横スワイプに割り当てる動作
/// （メッセージ画面を開く／メニューのタブを切り替える、2026-11-08）。端末ごとに保存する。
class _RoomListSwipeSetting extends ConsumerWidget {
  const _RoomListSwipeSetting({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(roomListSwipeActionProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    void select(RoomListSwipeAction value) =>
        ref.read(roomListSwipeActionProvider.notifier).setAction(value);

    final options = [
      (
        value: RoomListSwipeAction.openRoom,
        title: strings.settingsRoomListSwipeOpenTitle,
        subtitle: strings.settingsRoomListSwipeOpenDescription,
      ),
      (
        value: RoomListSwipeAction.switchTab,
        title: strings.settingsRoomListSwipeTabTitle,
        subtitle: strings.settingsRoomListSwipeTabDescription,
      ),
    ];

    final control = isGekiga
        ? GekigaJointedTileList(
            seeds: [for (final option in options) option.value.hashCode],
            selectedFlags: [
              for (final option in options) action == option.value,
            ],
            children: [
              for (final option in options)
                GekigaTileContent(
                  selected: action == option.value,
                  leading: AppRadioMark(
                    selected: action == option.value,
                    color: (action == option.value)
                        ? GekigaColors.panel
                        : GekigaColors.onPanel,
                  ),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  onTap: () => select(option.value),
                ),
            ],
          )
        : RadioGroup<RoomListSwipeAction>(
            groupValue: action,
            onChanged: (value) {
              if (value != null) select(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  AppRadioListTile<RoomListSwipeAction>(
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GekigaSectionHeader(strings.settingsRoomListSwipeTitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsRoomListSwipeNote,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        control,
      ],
    );
  }
}

class _MirrorSwitch extends ConsumerWidget {
  const _MirrorSwitch({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mirrored = ref.watch(iconSplitMirroredProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    void setMirrored(bool value) =>
        ref.read(iconSplitMirroredProvider.notifier).setMirrored(value);

    if (isGekiga) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GekigaJointedTileList(
          seeds: const [1],
          selectedFlags: const [false],
          children: [
            GekigaTileContent(
              selected: false,
              title: Text(strings.settingsTalksListMirrorTitle),
              subtitle: Text(strings.settingsTalksListMirrorSubtitle),
              trailing: AppSwitch(
                value: mirrored,
                onChanged: setMirrored,
                onDarkSurface: true,
              ),
              onTap: () => setMirrored(!mirrored),
            ),
          ],
        ),
      );
    }
    return AppSwitchListTile(
      value: mirrored,
      title: Text(strings.settingsTalksListMirrorTitle),
      subtitle: Text(strings.settingsTalksListMirrorSubtitle),
      onChanged: setMirrored,
    );
  }
}

/// 「押したまま指を滑らせて選ぶ」のオン/オフ（2026-11-05、標準オン）。
class _SlidePickSwitch extends ConsumerWidget {
  const _SlidePickSwitch({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(slidePickEnabledProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    void setEnabled(bool value) =>
        ref.read(slidePickEnabledProvider.notifier).setEnabled(value);

    if (isGekiga) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GekigaJointedTileList(
          seeds: const [1],
          selectedFlags: const [false],
          children: [
            GekigaTileContent(
              selected: false,
              title: Text(strings.settingsSlidePickTitle),
              subtitle: Text(strings.settingsSlidePickSubtitle),
              trailing: AppSwitch(
                value: enabled,
                onChanged: setEnabled,
                onDarkSurface: true,
              ),
              onTap: () => setEnabled(!enabled),
            ),
          ],
        ),
      );
    }
    return AppSwitchListTile(
      value: enabled,
      title: Text(strings.settingsSlidePickTitle),
      subtitle: Text(strings.settingsSlidePickSubtitle),
      onChanged: setEnabled,
    );
  }
}

/// アクセントで塗った面（選択中のチップ・ボタンなど）の上に乗る文字・アイコンの色の入力欄
/// （2026-11-06）。空欄なら自動（ライトは黒・ダークは白）。6桁のRRGGBBだけ受け付ける。
class _OnAccentColorField extends ConsumerStatefulWidget {
  const _OnAccentColorField({required this.strings});

  final Strings strings;

  @override
  ConsumerState<_OnAccentColorField> createState() =>
      _OnAccentColorFieldState();
}

class _OnAccentColorFieldState extends ConsumerState<_OnAccentColorField> {
  late final TextEditingController _controller;

  String _hexOf(Color? color) => color == null
      ? ''
      : color.toHexString().replaceFirst('#', '').substring(0, 6);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _hexOf(ref.read(onAccentColorProvider)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String text) {
    final hex = text.replaceFirst('#', '');
    if (hex.isEmpty) {
      ref.read(onAccentColorProvider.notifier).setColor(null);
      return;
    }
    if (hex.length != 6) return;
    final color = tryParseHexColor(hex);
    if (color != null) {
      ref.read(onAccentColorProvider.notifier).setColor(color);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 端末間の同期などで値が変わったら、入力欄にも反映する。
    ref.listen<Color?>(onAccentColorProvider, (previous, next) {
      final text = _hexOf(next);
      if (_controller.text != text &&
          tryParseHexColor(_controller.text) != next) {
        _controller.text = text;
      }
    });
    final accent = Theme.of(context).colorScheme.primary;
    final current = ref.watch(onAccentColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effective = current ?? (isDark ? Colors.white : Colors.black);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // アクセントの面に、今の文字色で「Aa」を載せた見本。
        Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(top: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
          child: Text(
            'Aa',
            style: TextStyle(
              color: effective,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          // ライト用・ダーク用の欄と同じく、文字の長さに合わせて横幅を変える。
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, child) => Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: _colorFieldWidth(
                  context,
                  _controller.text,
                  widget.strings.settingsOnAccentColorLabel,
                ),
                child: child,
              ),
            ),
            child: BlockFieldFrame(
              label: widget.strings.settingsOnAccentColorLabel,
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: isBlockTheme(context)
                      ? null
                      : widget.strings.settingsOnAccentColorLabel,
                  prefixText: '#',
                  hintText: widget.strings.settingsOnAccentColorAuto,
                  counterText: '',
                  filled: !isBlockTheme(context),
                  fillColor:
                      (Theme.of(context).brightness == Brightness.dark
                              ? GlassColors.darkSurfaceBase
                              : GlassColors.lightSurfaceBase)
                          .withValues(alpha: 0.65),
                  border: isBlockTheme(context)
                      ? InputBorder.none
                      : OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: accent.withValues(alpha: 0.3),
                          ),
                        ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CopyIconButton(
                        textBuilder: () => _hexText(_controller.text),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '',
                        onPressed: () {
                          _controller.clear();
                          ref
                              .read(onAccentColorProvider.notifier)
                              .setColor(null);
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: _apply,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
