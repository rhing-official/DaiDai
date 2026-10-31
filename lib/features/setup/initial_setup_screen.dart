import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../utils/platform_info.dart';
import '../../widgets/fixed_font_theme.dart';
import '../guide/tutorial/practice_home.dart';
import '../settings/settings_tab.dart';
import 'setup_presets.dart';

/// 初期設定の1ステップ分（2026-10-31追加）。
enum SetupStep {
  preset(PracticeFocus.talksList),
  appearance(PracticeFocus.chat),
  accent(PracticeFocus.chat),
  font(PracticeFocus.chat),
  message(PracticeFocus.chat),
  talksList(PracticeFocus.talksList),
  sendKey(PracticeFocus.chat);

  const SetupStep(this.focus);

  /// このステップで、背景のプレビューに見せる画面。
  final PracticeFocus focus;
}

/// この端末で表示するステップの並び。語らい一覧のレイアウトは、コンピューターでは
/// 反映されない（`talks_tab.dart`参照）ため飛ばす。
List<SetupStep> setupStepsFor(DeviceClass deviceClass) => [
  for (final step in SetupStep.values)
    if (step != SetupStep.talksList || deviceClass != DeviceClass.computer)
      step,
];

/// 初回の初期設定（2026-10-31追加）。居住地アンケートの後、使い方ガイドの前に出す。
/// 背景に練習用のホーム（[PracticeHome]、操作不可）を見せ、パネルで選んだ設定が
/// そのまま背景に反映される。選ぶたびに端末とFirestoreへ保存されるため、途中で
/// やめても、そこまでの設定は残る。
class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({
    required this.onCompleted,
    this.previewBuilder,
    super.key,
  });

  /// 最後まで進んだ時、または「あとで」を押した時に、1回だけ呼ぶ。
  final VoidCallback onCompleted;

  /// テスト用。背景のプレビューの作り方（既定は[PracticeHome]）。
  final Widget Function(PracticeFocus focus)? previewBuilder;

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  int _index = 0;
  int? _selectedPreset;
  bool _finished = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final steps = setupStepsFor(classifyDevice(context));
    final step = steps[_index.clamp(0, steps.length - 1)];
    final isLast = _index >= steps.length - 1;

    final preview = IgnorePointer(
      child: ClipRect(
        child:
            widget.previewBuilder?.call(step.focus) ??
            PracticeHome(focus: step.focus, topPadding: 0),
      ),
    );
    final panel = FixedFontTheme(
      child: _SetupPanel(
        strings: strings,
        step: step,
        index: _index,
        total: steps.length,
        isLast: isLast,
        selectedPreset: _selectedPreset,
        onSelectPreset: (i) {
          setState(() => _selectedPreset = i);
          applySetupPreset(ref, kSetupPresets[i]);
        },
        onBack: _index > 0 ? () => setState(() => _index--) : null,
        onNext: isLast ? _finish : () => setState(() => _index++),
        onSkip: _finish,
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 600) {
              return Row(
                children: [
                  Expanded(child: preview),
                  SizedBox(width: 380, child: panel),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: preview),
                SizedBox(height: constraints.maxHeight * 0.5, child: panel),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.strings,
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.selectedPreset,
    required this.onSelectPreset,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final Strings strings;
  final SetupStep step;
  final int index;
  final int total;
  final bool isLast;
  final int? selectedPreset;
  final ValueChanged<int> onSelectPreset;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  String get _title => switch (step) {
    SetupStep.preset => strings.setupPresetTitle,
    SetupStep.appearance => strings.setupAppearanceTitle,
    SetupStep.accent => strings.setupAccentTitle,
    SetupStep.font => strings.setupFontTitle,
    SetupStep.message => strings.setupMessageTitle,
    SetupStep.talksList => strings.setupTalksListTitle,
    SetupStep.sendKey => strings.setupSendKeyTitle,
  };

  String get _description => switch (step) {
    SetupStep.preset => strings.setupPresetDescription,
    SetupStep.appearance => strings.setupAppearanceDescription,
    SetupStep.accent => strings.setupAccentDescription,
    SetupStep.font => strings.setupFontDescription,
    SetupStep.message => strings.setupMessageDescription,
    SetupStep.talksList => strings.setupTalksListDescription,
    SetupStep.sendKey => strings.setupSendKeyDescription,
  };

  Widget _body() => switch (step) {
    SetupStep.preset => _PresetList(
      strings: strings,
      selected: selectedPreset,
      onSelect: onSelectPreset,
    ),
    SetupStep.appearance => Column(
      children: [
        UiStyleFolder(strings: strings),
        AppearanceFolder(strings: strings),
      ],
    ),
    SetupStep.accent => AccentColorFolder(strings: strings),
    SetupStep.font => FontDesignFolder(strings: strings),
    SetupStep.message => Column(
      children: [
        ChatLayoutFolder(strings: strings),
        TimeFormatFolder(strings: strings),
      ],
    ),
    SetupStep.talksList => TalksListLayoutFolder(strings: strings),
    SetupStep.sendKey => SendKeyFolder(strings: strings),
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
            left: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    strings.setupProgress(index + 1, total),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(onPressed: onSkip, child: Text(strings.setupSkip)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _description,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(child: SingleChildScrollView(child: _body())),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton(onPressed: onBack, child: Text(strings.setupBack)),
                  const Spacer(),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(isLast ? strings.setupDone : strings.setupNext),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetList extends StatelessWidget {
  const _PresetList({
    required this.strings,
    required this.selected,
    required this.onSelect,
  });

  final Strings strings;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      (strings.setupPresetStandardName, strings.setupPresetStandardDescription),
      (strings.setupPresetCrispName, strings.setupPresetCrispDescription),
      (strings.setupPresetPlayfulName, strings.setupPresetPlayfulDescription),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected == i
                        ? colorScheme.onSurface
                        : colorScheme.outlineVariant,
                    width: selected == i ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$1,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$2,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
