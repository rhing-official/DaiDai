import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../l10n/terminology_style.dart';
import '../../models/app_user.dart';
import '../../models/message_time_format.dart';
import '../../models/send_key_mode.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/terminology_style_provider.dart';
import '../../utils/color_hex.dart';
import '../../widgets/swipe_gestures.dart';

/// 画面幅がこれ以上あれば、左にカテゴリ一覧（サイドバー）、右にそのカテゴリの
/// 内容を1ページにまとめて表示するDiscord設定風の2ペイン表示にする。
/// これ未満の狭い画面では、カテゴリ一覧→内容ページの1段だけドリルダウンする。
const _kSettingsSplitBreakpoint = 760.0;

/// サイドバーの幅。
const _kSettingsSidebarWidth = 240.0;

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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final categories = _categories(strings, ref, widget.currentUser);
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;

    if (isWide) {
      final selected = _findCategoryById(categories, _selectedId) ??
          categories.first;
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
                onSelect: (category) =>
                    setState(() => _selectedId = category.id),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _SettingsPage(
                title: selected.title,
                child: Builder(builder: selected.pageBuilder),
              ),
            ),
          ],
        ),
      );
    }

    final selected = _findCategoryById(categories, _selectedId);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: selected == null
                ? _CategoryList(
                    key: const ValueKey('settings-categories'),
                    categories: categories,
                    selectedId: null,
                    onSelect: (category) =>
                        setState(() => _selectedId = category.id),
                  )
                : _NarrowSettingsPage(
                    key: ValueKey(selected.id),
                    category: selected,
                    onBack: () => setState(() => _selectedId = null),
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
      id: 'input',
      icon: Icons.keyboard_outlined,
      title: strings.settingsFolderInput,
      pageBuilder: (context) => _InputFolder(strings: strings),
    ),
    _SettingsCategory(
      id: 'notifications',
      icon: Icons.notifications_outlined,
      title: strings.settingsFolderNotifications,
      pageBuilder: (context) =>
          _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
  ];
}

/// カテゴリ一覧（サイドバー、または狭い画面での一覧画面）。
class _CategoryList extends StatelessWidget {
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
  Widget build(BuildContext context) {
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

class _FolderTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: selected ? colorScheme.primary.withValues(alpha: 0.1) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        selected: selected,
        selectedColor: colorScheme.primary,
        leading: Icon(icon),
        title: Text(title),
        trailing: trailingChevron ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}

/// 広い画面での内容ペイン。タイトルの下に、カテゴリの中身を1ページで表示する。
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 内容ペインが余った横幅いっぱいに広がると、ラベルと値の間の余白ばかりが
    // 目立ってしまう（項目が横に広がりすぎる）ため、読みやすい幅で頭打ちにする。
    // ConstrainedBoxは、親（Expanded）から渡されるtight制約をそのまま
    // enforce()すると自分のmaxWidthが無視される（tightな下限に引き上げられる）
    // ため、先にAlignでtight制約をloose制約に変換してから渡す必要がある。
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
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
  });

  final _SettingsCategory category;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // mainAxisSizeをmin指定にすると、内側のListView（例: _AccountPage）が
    // 無限の高さ制約を受けてクラッシュする。既定（max）のままExpandedで包む。
    return SwipeBackDetector(
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.arrow_back),
            title: Text(
              category.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: onBack,
          ),
          const Divider(height: 1),
          Expanded(child: Builder(builder: category.pageBuilder)),
        ],
      ),
    );
  }
}

/// セクションの見出し。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

/// ラベル＋値（読み取り専用、または「準備中」）の1行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.destructive = false,
  });

  final String label;
  final String value;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: destructive ? TextStyle(color: colorScheme.error) : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
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
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label),
      onTap: onTap,
    );
  }
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
        _InfoRow(
          label: strings.settingsTwoFactor,
          value: strings.settingsComingSoon,
        ),
        _InfoRow(
          label: strings.settingsPasskey,
          value: strings.settingsComingSoon,
        ),
        _InfoRow(
          label: strings.settingsQrLogin,
          value: strings.settingsComingSoon,
        ),
        const Divider(height: 24),
        _ActionRow(
          label: strings.settingsLogout,
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
        _InfoRow(
          label: strings.settingsDeleteAccount,
          value: strings.settingsComingSoon,
          destructive: true,
        ),
      ],
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
        const Divider(height: 24),
        _SectionHeader(strings.settingsSubTypography),
        _InfoRow(
          label: strings.settingsFontDesign,
          value: strings.settingsComingSoon,
        ),
        _InfoRow(
          label: strings.settingsFontSize,
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
    ref.read(accentColorProvider.notifier).setColor(color);
  }

  void _applyPreset(String hex) {
    final color = tryParseHexColor(hex);
    if (color == null) return;
    setState(() {
      _errorText = null;
      _hexController.text = hex.toUpperCase();
    });
    ref.read(accentColorProvider.notifier).setColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            widget.strings.settingsAccentColor,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
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
                ),
              ),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final hex in _kAccentColorPresets)
                    _PresetColorSwatch(
                      hex: hex,
                      selected: tryParseHexColor(hex) == accentColor,
                      onTap: () => _applyPreset(hex),
                    ),
                ],
              ),
            ],
          ),
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

/// 表示言語（日本語／English）と、DaiDai独自用語の言い換えスタイル
/// （世界観重視／利便性重視）の両方をここで切り替える。2軸は独立しており、
/// 組み合わせは`docs/マップ.md`の対訳表（[Vocabulary]）に対応する。
class _LanguageFolder extends ConsumerWidget {
  const _LanguageFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(appLocaleProvider);
    final currentStyle = ref.watch(terminologyStyleProvider);

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
          child: SegmentedButton<AppLocale>(
            segments: [
              for (final locale in AppLocale.values)
                ButtonSegment(value: locale, label: Text(locale.label)),
            ],
            selected: {currentLocale},
            onSelectionChanged: (selection) {
              ref
                  .read(appLocaleProvider.notifier)
                  .setLocale(selection.first);
            },
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.settingsTerminology,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // 用語は言語によって長さがまちまち（例:
          // 「マテリアルボックス」「Terminology & display」）なため、
          // 横に並べたセグメントボタンが窮屈にならないよう、
          // 折り返し可能なWrapで選択肢を並べる。
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in TerminologyStyle.values)
                ChoiceChip(
                  label: Text(
                    style == TerminologyStyle.worldview
                        ? strings.settingsTerminologyWorldview
                        : strings.settingsTerminologyConvenience,
                  ),
                  selected: currentStyle == style,
                  onSelected: (_) =>
                      ref.read(terminologyStyleProvider.notifier).setStyle(style),
                ),
            ],
          ),
        ),
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
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in MessageTimeFormat.values)
                ChoiceChip(
                  label: Text(
                    format == MessageTimeFormat.h24
                        ? strings.settingsTimeFormat24h
                        : strings.settingsTimeFormat12h,
                  ),
                  selected: currentFormat == format,
                  onSelected: (_) =>
                      ref.read(messageTimeFormatProvider.notifier).setFormat(format),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InputFolder extends ConsumerWidget {
  const _InputFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(sendKeyModeProvider);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            strings.settingsSendKeyTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        RadioGroup<SendKeyMode>(
          groupValue: mode,
          onChanged: (value) {
            if (value != null) {
              ref.read(sendKeyModeProvider.notifier).setMode(value);
            }
          },
          child: Column(
            children: [
              RadioListTile<SendKeyMode>(
                value: SendKeyMode.enterToSend,
                title: Text(strings.settingsSendKeyEnterToSend),
                subtitle: Text(strings.settingsSendKeySilentEnterToSend),
              ),
              RadioListTile<SendKeyMode>(
                value: SendKeyMode.ctrlEnterToSend,
                title: Text(strings.settingsSendKeyCtrlEnterToSend),
                subtitle: Text(strings.settingsSendKeySilentCtrlEnterToSend),
              ),
            ],
          ),
        ),
      ],
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
