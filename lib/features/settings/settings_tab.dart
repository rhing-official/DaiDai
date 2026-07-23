import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../models/send_key_mode.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../utils/color_hex.dart';

enum _SettingsFolder { account, design, displayLanguage, input, notifications }

/// 設定タブ。項目をフォルダ単位に階層化して表示する。
/// フォルダを開くとその中身、閉じると一覧に戻る。
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  _SettingsFolder? _openFolder;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _openFolder == null
                ? _FolderList(
                    key: const ValueKey('folder-list'),
                    strings: strings,
                    onOpen: (folder) => setState(() => _openFolder = folder),
                  )
                : _FolderDetail(
                    key: ValueKey(_openFolder),
                    folder: _openFolder!,
                    strings: strings,
                    onBack: () => setState(() => _openFolder = null),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FolderList extends StatelessWidget {
  const _FolderList({super.key, required this.strings, required this.onOpen});

  final Strings strings;
  final void Function(_SettingsFolder folder) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _FolderTile(
          icon: Icons.person_outline,
          title: strings.settingsFolderAccount,
          onTap: () => onOpen(_SettingsFolder.account),
        ),
        _FolderTile(
          icon: Icons.palette_outlined,
          title: strings.settingsFolderDesign,
          onTap: () => onOpen(_SettingsFolder.design),
        ),
        _FolderTile(
          icon: Icons.language_outlined,
          title: strings.settingsFolderDisplayLanguage,
          onTap: () => onOpen(_SettingsFolder.displayLanguage),
        ),
        _FolderTile(
          icon: Icons.keyboard_outlined,
          title: strings.settingsFolderInput,
          onTap: () => onOpen(_SettingsFolder.input),
        ),
        _FolderTile(
          icon: Icons.notifications_outlined,
          title: strings.settingsFolderNotifications,
          onTap: () => onOpen(_SettingsFolder.notifications),
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
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _FolderDetail extends ConsumerWidget {
  const _FolderDetail({
    super.key,
    required this.folder,
    required this.strings,
    required this.onBack,
  });

  final _SettingsFolder folder;
  final Strings strings;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.arrow_back),
          title: Text(
            switch (folder) {
              _SettingsFolder.account => strings.settingsFolderAccount,
              _SettingsFolder.design => strings.settingsFolderDesign,
              _SettingsFolder.displayLanguage =>
                strings.settingsFolderDisplayLanguage,
              _SettingsFolder.input => strings.settingsFolderInput,
              _SettingsFolder.notifications =>
                strings.settingsFolderNotifications,
            },
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onTap: onBack,
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (folder) {
            _SettingsFolder.account => _AccountFolder(strings: strings),
            _SettingsFolder.design => _DesignFolder(strings: strings),
            _SettingsFolder.displayLanguage => _DisplayLanguageFolder(
              strings: strings,
            ),
            _SettingsFolder.input => _InputFolder(strings: strings),
            _SettingsFolder.notifications => _ComingSoonFolder(
              message: strings.settingsComingSoon,
            ),
          },
        ),
      ],
    );
  }
}

class _AccountFolder extends ConsumerWidget {
  const _AccountFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: Text(
            strings.settingsLogout,
            style: const TextStyle(color: Colors.red),
          ),
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
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

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);

    return ListView(
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
      ],
    );
  }
}

class _DisplayLanguageFolder extends ConsumerWidget {
  const _DisplayLanguageFolder({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(appLocaleProvider);

    return ListView(
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
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(strings.settingsTerminology),
          subtitle: Text(strings.settingsComingSoon),
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
              ),
              RadioListTile<SendKeyMode>(
                value: SendKeyMode.ctrlEnterToSend,
                title: Text(strings.settingsSendKeyCtrlEnterToSend),
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
    return Center(
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
