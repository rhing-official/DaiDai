import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/bot.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// AIエージェント連携（bot API、2026-11-09）の管理ダイアログ（設定>セキュリティ）。
/// 自分のAI（Claude Codeなど）が、自分の参加している全ての広場・一対を読み、返信する
/// ためのトークンを作る。会話ごとの追加・承認・相手の同意は無い（2026-11-09に会話ごとの
/// BOTから一本化）。トークンは作成・再発行の直後に**1度だけ**表示する（サーバーには
/// ハッシュしか残らず、再表示できない）。
class AiIntegrationDialog extends ConsumerWidget {
  const AiIntegrationDialog({
    super.key,
    required this.currentUser,
    required this.isGlass,
  });

  final AppUser currentUser;
  final bool isGlass;

  static Future<void> show(BuildContext context, WidgetRef ref, AppUser user) {
    return showAppDialog<void>(
      context: context,
      builder: (_) => AiIntegrationDialog(
        currentUser: user,
        isGlass: ref.read(appUiStyleProvider) == AppUiStyle.glass,
      ),
    );
  }

  Future<void> _showToken(BuildContext context, Strings strings, String token) {
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        // 横画面（広い画面）では、テーマの幅の上限（400）を外して画面いっぱいに使い、
        // AIエージェント用とAPI用の2列に分ける。
        final screenWidth = MediaQuery.sizeOf(dialogContext).width;
        final wide = screenWidth >= 760;
        final contentWidth = (screenWidth - 128).clamp(0.0, 1100.0);
        return _Dialog(
          isGlass: isGlass,
          title: Text(strings.botCreatedTitle),
          constraints: wide ? const BoxConstraints(maxWidth: 1200) : null,
          content: SizedBox(
            width: wide ? contentWidth : 360,
            child: _TokenBody(strings: strings, token: token, wide: wide),
          ),
          actions: const [],
        );
      },
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
  ) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => _NameDialog(strings: strings, isGlass: isGlass),
    );
    if (name == null || !context.mounted) return;
    try {
      final created = await ref.read(botRepositoryProvider).createBot(name);
      if (!context.mounted) return;
      await _showToken(context, strings, created.token);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  Future<void> _rotate(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Bot bot,
  ) async {
    try {
      final token = await ref
          .read(botRepositoryProvider)
          .rotateToken(bot.botId);
      if (!context.mounted) return;
      await _showToken(context, strings, token);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Bot bot,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => _Dialog(
        isGlass: isGlass,
        title: Text(strings.botDeleteTitle),
        content: Text(strings.botDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          // 後戻りしにくい確定ボタンは鮮やかな赤（CLAUDE.mdのボタン配色の規約）。
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.botDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(botRepositoryProvider).deleteBot(bot.botId);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return _Dialog(
      isGlass: isGlass,
      title: Text(strings.assistantTitle),
      content: SizedBox(
        width: 360,
        child: StreamBuilder<List<Bot>>(
          stream: ref
              .read(botRepositoryProvider)
              .watchMyBots(currentUser.userId),
          builder: (context, snapshot) {
            final bots = snapshot.data ?? const <Bot>[];
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    strings.assistantDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                for (final bot in bots)
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(bot.name),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.vpn_key_outlined),
                          tooltip: strings.botRotate,
                          onPressed: () => _rotate(context, ref, strings, bot),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: strings.botDelete,
                          onPressed: () => _delete(context, ref, strings, bot),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(strings.assistantCreate),
                  onTap: () => _create(context, ref, strings),
                ),
              ],
            );
          },
        ),
      ),
      actions: const [],
    );
  }
}

/// ガラス・それ以外で同じ見た目のダイアログを出す為の薄いラッパー。
class _Dialog extends StatelessWidget {
  const _Dialog({
    required this.isGlass,
    required this.title,
    required this.content,
    required this.actions,
    this.constraints,
  });

  final bool isGlass;
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  /// 幅の上限（テーマの既定は400）。広げたい時だけ渡す。
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return isGlass
        ? GlassAlertDialog(
            title: title,
            content: content,
            actions: actions,
            constraints: constraints,
          )
        : KeyboardAlertDialog(
            title: title,
            content: content,
            actions: actions,
            constraints: constraints,
          );
  }
}

/// 名前の入力。コントローラはこの`State`が持つ（ダイアログが閉じた後に破棄）。
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.strings, required this.isGlass});

  final Strings strings;
  final bool isGlass;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return _Dialog(
      isGlass: widget.isGlass,
      title: Text(strings.assistantCreate),
      content: TextField(
        controller: _controller,
        maxLength: 40,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.botNameLabel),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(strings.botCreate),
        ),
      ],
    );
  }
}

/// 読み取り専用の欄に値を入れ、右端のアイコンでコピーできる部品。
class _CopyField extends StatefulWidget {
  const _CopyField({
    required this.value,
    required this.tooltip,
    required this.copiedMessage,
    this.fontSize = 12,
  });

  final String value;
  final String tooltip;
  final String copiedMessage;
  final double fontSize;

  @override
  State<_CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<_CopyField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: true,
      minLines: 1,
      maxLines: 4,
      style: TextStyle(fontSize: widget.fontSize),
      onTap: () => _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: widget.tooltip,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.value));
            if (context.mounted) {
              showAutoDismissBanner(context, message: widget.copiedMessage);
            }
          },
        ),
      ),
    );
  }
}

/// トークン表示ポップアップの中身（トークン欄・使い方の手順）。
class _TokenBody extends StatelessWidget {
  const _TokenBody({
    required this.strings,
    required this.token,
    required this.wide,
  });

  final Strings strings;
  final String token;

  /// 広い画面では、AIエージェントで使う手順（1〜3）を左、直接APIを呼ぶ場合を右の2列に分ける。
  final bool wide;

  static const _guideUrl =
      'https://github.com/rhing-official/DaiDai/tree/main/tools/daidai-mcp';

  @override
  Widget build(BuildContext context) {
    final command =
        'claude mcp add daidai -e DAIDAI_BOT_TOKEN=$token -- npx -y daidai-mcp';
    final curl =
        "curl -H 'Authorization: Bot $token' "
        "'https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1/conversations'";
    const bold = TextStyle(fontWeight: FontWeight.bold);
    const small = TextStyle(fontSize: 13);
    final step1 = <Widget>[
      Text(strings.botUsageStep1, style: small),
      const SizedBox(height: 6),
      _CopyField(
        value: token,
        tooltip: strings.botCopyToken,
        copiedMessage: strings.botCopied,
      ),
    ];
    final step2 = <Widget>[
      Text(strings.botUsageStep2, style: small),
      const SizedBox(height: 6),
      _CopyField(
        value: command,
        tooltip: strings.botCopyToken,
        copiedMessage: strings.botCopied,
        fontSize: 11,
      ),
    ];
    final step3 = <Widget>[
      Text(strings.botUsageStep3, style: small),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(strings.botUsageMore),
          onPressed: () => launchUrl(
            Uri.parse(_guideUrl),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    ];
    final advanced = ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(strings.botUsageAdvanced, style: bold),
      children: [
        _CopyField(
          value: curl,
          tooltip: strings.botCopyToken,
          copiedMessage: strings.botCopied,
          fontSize: 11,
        ),
      ],
    );
    const gap = SizedBox(height: 14);
    final Widget body;
    if (wide) {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Heading(strings.botUsageTitle),
                  const SizedBox(height: 8),
                  ...step1,
                  gap,
                  ...step2,
                  gap,
                  ...step3,
                ],
              ),
            ),
            const SizedBox(width: 14),
            const VerticalDivider(width: 1),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Heading(strings.botUsageAdvanced),
                  const SizedBox(height: 8),
                  _CopyField(
                    value: curl,
                    tooltip: strings.botCopyToken,
                    copiedMessage: strings.botCopied,
                    fontSize: 11,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(strings.botUsageTitle),
          const SizedBox(height: 8),
          ...step1,
          gap,
          ...step2,
          gap,
          ...step3,
          const SizedBox(height: 16),
          advanced,
        ],
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [body],
      ),
    );
  }
}

/// 折り返さない見出し。
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontWeight: FontWeight.bold),
  );
}
