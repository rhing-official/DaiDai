import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../l10n/terminology_style.dart';
import '../../models/app_user.dart';
import '../../models/send_key_mode.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/terminology_style_provider.dart';
import '../../utils/color_hex.dart';

/// 画面幅がこれ以上あれば、階層を「列（カラム）」として左詰めで並べる
/// マルチカラム表示にする（macOSの設定／Finderのカラム表示と同様、項目の
/// 中に更に項目がある場合は右に新しい列が増えていく）。これ未満の狭い画面
/// では、従来通り1画面ずつ潜っていくドリルダウン表示にする。
const _kSettingsSplitBreakpoint = 760.0;

/// マルチカラム表示での1列あたりの幅。用語スタイル・表示言語によっては
/// 項目名が長くなる（例:「マテリアルボックス」「Terminology & display」）ため、
/// 折り返しではなく列幅そのものに余裕を持たせている。列数が増えて画面に
/// 収まらない場合は、列の並び全体を横スクロールさせる（[_SplitSettingsView]参照）。
const _kSettingsColumnWidth = 280.0;

/// マルチカラム表示で、右端の内容ペインに最低限確保する幅。
const _kSettingsMinContentWidth = 320.0;

/// 設定タブ。`docs/マップ.md`のサイトマップ（アカウント／アプリケーション／
/// 入力／通知）に沿って項目を[_Node]の木構造として表示する。
/// 広い画面では選んだ階層ごとに列を追加していくマルチカラム表示、
/// 狭い画面では1画面ずつ置き換わるドリルダウン表示になる。
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  /// マルチカラム表示でのみ使う、選択中ノードのタイトルの連なり
  /// （例: ["アカウント", "セキュリティ", "パスワード"]）。
  /// ノードオブジェクト自体はビルドごとに作り直される（[_rootNodes]参照）ため
  /// 参照の同一性ではなくタイトルで選択状態・列内容を復元する。
  List<String> _path = [];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isSplit =
        MediaQuery.sizeOf(context).width >= _kSettingsSplitBreakpoint;
    final rootNodes = _rootNodes(context, ref, strings, widget.currentUser);

    if (isSplit) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _SplitSettingsView(
          rootNodes: rootNodes,
          path: _path,
          onSelect: (columnIndex, node) {
            if (node.onTap != null) {
              node.onTap!();
              return;
            }
            setState(() => _path = [..._path.take(columnIndex), node.title]);
          },
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: _NodeListDetail(
            key: const ValueKey('settings-root'),
            nodes: rootNodes,
          ),
        ),
      ),
    );
  }
}

/// 設定のルート階層（アカウント／アプリケーション／入力／通知）。
/// アカウント・アプリケーションはさらに内部にサブ項目を持つフォルダ、
/// 入力・通知はこの階層自体が末端の内容を持つ（[_Node.isFolder]参照）。
List<_Node> _rootNodes(
  BuildContext context,
  WidgetRef ref,
  Strings strings,
  AppUser currentUser,
) {
  return [
    _Node(
      icon: Icons.person_outline,
      title: strings.settingsFolderAccount,
      children: _accountNodes(context, ref, strings, currentUser),
    ),
    _Node(
      icon: Icons.tune,
      title: strings.settingsFolderApplication,
      children: _applicationNodes(context, ref, strings),
    ),
    _Node(
      icon: Icons.keyboard_outlined,
      title: strings.settingsFolderInput,
      builder: (context) => _InputFolder(strings: strings),
    ),
    _Node(
      icon: Icons.notifications_outlined,
      title: strings.settingsFolderNotifications,
      builder: (context) => _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
  ];
}

/// アカウント配下のサブ項目ツリー。`docs/マップ.md`のサイトマップに沿う。
/// バックアップコード・メールアドレスはCLAUDE.mdの明記された不採用方針
/// （バックアップコードの代わりに秘密の質問3つを採用／プライバシー方針上
/// メールアドレスを収集しない）に合わせ、意図的に含めていない。
List<_Node> _accountNodes(
  BuildContext context,
  WidgetRef ref,
  Strings strings,
  AppUser currentUser,
) {
  return [
    _Node(
      icon: Icons.badge_outlined,
      title: strings.settingsRhingIdLabel,
      builder: (context) => _InfoLeaf(
        title: strings.settingsRhingIdLabel,
        value: '@${currentUser.rhingId}',
      ),
    ),
    _Node(
      icon: Icons.person_outline,
      title: strings.settingsProfileName,
      builder: (context) => _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
    _Node(
      icon: Icons.security_outlined,
      title: strings.settingsSecurity,
      children: [
        _Node(
          icon: Icons.password_outlined,
          title: strings.settingsPassword,
          builder: (context) =>
              _ComingSoonFolder(message: strings.settingsComingSoon),
        ),
        _Node(
          icon: Icons.verified_user_outlined,
          title: strings.settingsTwoFactor,
          builder: (context) =>
              _ComingSoonFolder(message: strings.settingsComingSoon),
        ),
        _Node(
          icon: Icons.key_outlined,
          title: strings.settingsPasskey,
          builder: (context) =>
              _ComingSoonFolder(message: strings.settingsComingSoon),
        ),
      ],
    ),
    _Node(
      icon: Icons.qr_code_outlined,
      title: strings.settingsQrLogin,
      builder: (context) => _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
    _Node(
      icon: Icons.logout,
      title: strings.settingsLogout,
      onTap: () => ref.read(authRepositoryProvider).signOut(),
    ),
    _Node(
      icon: Icons.delete_outline,
      title: strings.settingsDeleteAccount,
      destructive: true,
      builder: (context) => _ComingSoonFolder(message: strings.settingsComingSoon),
    ),
  ];
}

/// アプリケーション配下のサブ項目ツリー（色／UI／文字／言語）。
List<_Node> _applicationNodes(
  BuildContext context,
  WidgetRef ref,
  Strings strings,
) {
  return [
    _Node(
      icon: Icons.palette_outlined,
      title: strings.settingsFolderDesign,
      builder: (context) => _DesignFolder(strings: strings),
    ),
    _Node(
      icon: Icons.widgets_outlined,
      title: strings.settingsSubUI,
      builder: (context) => _InfoLeaf(
        title: strings.settingsSubUI,
        value: strings.settingsUIDescription,
      ),
    ),
    _Node(
      icon: Icons.text_fields_outlined,
      title: strings.settingsSubTypography,
      children: [
        _Node(
          icon: Icons.font_download_outlined,
          title: strings.settingsFontDesign,
          builder: (context) =>
              _ComingSoonFolder(message: strings.settingsComingSoon),
        ),
        _Node(
          icon: Icons.format_size,
          title: strings.settingsFontSize,
          builder: (context) =>
              _ComingSoonFolder(message: strings.settingsComingSoon),
        ),
      ],
    ),
    _Node(
      icon: Icons.language_outlined,
      title: strings.settingsFolderLanguage,
      builder: (context) => _LanguageFolder(strings: strings),
    ),
  ];
}

/// 設定サイトマップの1ノード。[children]があればフォルダ、[builder]があれば
/// 詳細コンテンツを持つ末端項目、[onTap]があれば（ログアウトのように）
/// 遷移せずその場で実行するアクション項目になる。
class _Node {
  const _Node({
    required this.icon,
    required this.title,
    this.builder,
    this.children,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder? builder;
  final List<_Node>? children;
  final VoidCallback? onTap;
  final bool destructive;

  bool get isFolder => children != null;
}

/// [nodes]の中から[title]に一致するノードを探す。ノードはビルドごとに
/// 作り直されるため、階層をたどるときは常にタイトルで照合する
/// （[_computeColumns] / [_resolveSelectedNode]参照）。
_Node? _findNodeByTitle(List<_Node> nodes, String title) {
  for (final node in nodes) {
    if (node.title == title) return node;
  }
  return null;
}

/// [path]をルートからたどり、マルチカラム表示で左から並べる列（それぞれが
/// 1つのフォルダの中身）を計算する。末端（フォルダではない項目）に達したら
/// それ以上列は増えない。
List<List<_Node>> _computeColumns(List<_Node> rootNodes, List<String> path) {
  final columns = <List<_Node>>[rootNodes];
  var currentNodes = rootNodes;
  for (final title in path) {
    final match = _findNodeByTitle(currentNodes, title);
    if (match == null || !match.isFolder) break;
    columns.add(match.children!);
    currentNodes = match.children!;
  }
  return columns;
}

/// [path]がたどり着いた先のノード（内容ペインに表示すべきノード）を返す。
/// フォルダの場合は列としてすでに表示されているため、内容ペインには
/// 表示しない（呼び出し側で[_Node.isFolder]を見て判定する）。
_Node? _resolveSelectedNode(List<_Node> rootNodes, List<String> path) {
  if (path.isEmpty) return null;
  var currentNodes = rootNodes;
  _Node? node;
  for (final title in path) {
    node = _findNodeByTitle(currentNodes, title);
    if (node == null) return null;
    if (node.isFolder) currentNodes = node.children!;
  }
  return node;
}

/// 広い画面向けのマルチカラム表示。ルート階層を一番左の列に、選んだ項目に
/// 子項目があればその右にもう1列追加していく。末端項目を選ぶと、一番右の
/// 内容ペインにその中身を表示する。列がすべて画面幅に収まらない場合は、
/// 列の並び全体（内容ペインを除く）を横スクロールさせ、内容ペインの幅は
/// 常に[_kSettingsMinContentWidth]以上を確保する。
class _SplitSettingsView extends StatelessWidget {
  const _SplitSettingsView({
    required this.rootNodes,
    required this.path,
    required this.onSelect,
  });

  final List<_Node> rootNodes;
  final List<String> path;
  final void Function(int columnIndex, _Node node) onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = _computeColumns(rootNodes, path);
    final selectedNode = _resolveSelectedNode(rootNodes, path);
    final contentPane = selectedNode == null ||
            selectedNode.isFolder ||
            selectedNode.builder == null
        ? const _EmptyFolderPlaceholder()
        : Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: Builder(builder: selectedNode.builder!),
              ),
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 列の間に挟むVerticalDivider（幅1）の分も含めないと、この幅で
        // SizedBoxに収めたRowが必ず列数×1pxだけ右端をはみ出してしまう。
        const columnSlotWidth = _kSettingsColumnWidth + 1;
        final sidebarAreaWidth = columns.length * columnSlotWidth;
        final availableForSidebars =
            (constraints.maxWidth - _kSettingsMinContentWidth)
                .clamp(_kSettingsColumnWidth, double.infinity);
        final needsScroll = sidebarAreaWidth > availableForSidebars;

        final columnsRow = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              SizedBox(
                width: _kSettingsColumnWidth,
                child: _NodeColumnList(
                  nodes: columns[i],
                  selectedTitle: path.length > i ? path[i] : null,
                  onSelect: (node) => onSelect(i, node),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
          ],
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: needsScroll ? availableForSidebars : sidebarAreaWidth,
              child: needsScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: sidebarAreaWidth,
                        child: columnsRow,
                      ),
                    )
                  : columnsRow,
            ),
            Expanded(child: contentPane),
          ],
        );
      },
    );
  }
}

/// マルチカラム表示の1列分。フォルダ項目にはさらに右へ列を増やす合図として
/// 山括弧を付け、末端項目（内容ペインに直接表示される）には付けない。
class _NodeColumnList extends StatelessWidget {
  const _NodeColumnList({
    required this.nodes,
    required this.selectedTitle,
    required this.onSelect,
  });

  final List<_Node> nodes;
  final String? selectedTitle;
  final ValueChanged<_Node> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final node in nodes)
          _FolderTile(
            icon: node.icon,
            title: node.title,
            selected: node.title == selectedTitle,
            destructive: node.destructive,
            trailingChevron: node.isFolder,
            onTap: () => onSelect(node),
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
    this.destructive = false,
    this.trailingChevron = true,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final bool destructive;
  final bool trailingChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destructiveColor = colorScheme.error;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: selected ? colorScheme.primary.withValues(alpha: 0.1) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        selected: selected,
        selectedColor: colorScheme.primary,
        leading: Icon(icon, color: destructive ? destructiveColor : null),
        title: Text(
          title,
          style: destructive ? TextStyle(color: destructiveColor) : null,
        ),
        trailing: destructive || !trailingChevron
            ? null
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// [_Node]の木構造を、フォルダ一覧⇔詳細のその場切り替えで表示する汎用ウィジェット。
/// 狭い画面のドリルダウン表示で使う。フォルダを選ぶと再帰的に同じ仕組みで
/// その子ノードを表示するため、アカウント＞セキュリティ＞パスワードのような
/// 多段階層にもそのまま対応する。
class _NodeListDetail extends StatefulWidget {
  const _NodeListDetail({super.key, required this.nodes});

  final List<_Node> nodes;

  @override
  State<_NodeListDetail> createState() => _NodeListDetailState();
}

class _NodeListDetailState extends State<_NodeListDetail> {
  _Node? _selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _selected == null
          ? _NodeList(
              key: const ValueKey('node-list'),
              nodes: widget.nodes,
              onOpen: (node) {
                if (node.onTap != null) {
                  node.onTap!();
                  return;
                }
                setState(() => _selected = node);
              },
            )
          : _NodeDetail(
              key: ValueKey(_selected!.title),
              node: _selected!,
              onBack: () => setState(() => _selected = null),
            ),
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({super.key, required this.nodes, required this.onOpen});

  final List<_Node> nodes;
  final ValueChanged<_Node> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shrinkWrap: true,
      children: [
        for (final node in nodes)
          _FolderTile(
            icon: node.icon,
            title: node.title,
            destructive: node.destructive,
            onTap: () => onOpen(node),
          ),
      ],
    );
  }
}

class _NodeDetail extends StatelessWidget {
  const _NodeDetail({super.key, required this.node, required this.onBack});

  final _Node node;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // mainAxisSizeをmin指定にすると、内側のListView（例: _DesignFolder）が
    // 無限の高さ制約を受けてクラッシュする。祖先から渡された高さ制約が
    // 再帰的に子へも伝わるよう、既定（max）のままExpandedで本文を包む。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.arrow_back),
          title: Text(node.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: onBack,
        ),
        const Divider(height: 1),
        Expanded(
          child: node.isFolder
              ? _NodeListDetail(nodes: node.children!)
              : Builder(builder: node.builder!),
        ),
      ],
    );
  }
}

/// ラベル＋値（または説明文）だけを表示する、読み取り専用の項目。
/// 例: Rhing IDの表示、現在のUIスタイルの説明。
class _InfoLeaf extends StatelessWidget {
  const _InfoLeaf({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
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

    return ListView(
      shrinkWrap: true,
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
                      tooltip: '適用',
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
    return Tooltip(
      message: '#$hex',
      child: InkWell(
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

    return ListView(
      shrinkWrap: true,
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

/// マルチカラム表示で、末端項目がまだ選ばれていないときに内容ペインに表示する。
class _EmptyFolderPlaceholder extends StatelessWidget {
  const _EmptyFolderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.settings_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
