import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/qr_scan_screen.dart';

/// ログイン済み端末が表示したQRを、ログインしたい（未ログインの）端末が読み取って
/// ログインする方式（2026-10-15）のログイン側。QRの文字列の接頭辞。
const kQrIssuePrefix = 'daidai:qrissue:';

/// 読み取り開始の説明 → カメラ → [ScanQrLoginDialog]の一連の流れ。ログイン画面の
/// 「QRコードを読み取ってログイン」ボタンから呼ぶ。
Future<void> startScanQrLogin(BuildContext context, Strings strings) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => _InstructionDialog(strings: strings),
  );
  if (go != true || !context.mounted) return;
  final scanned = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => QrScanScreen(title: strings.qrScanLoginButton),
    ),
  );
  if (scanned == null || !context.mounted) return;
  if (!scanned.startsWith(kQrIssuePrefix)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.qrLoginInvalidQrError)));
    return;
  }
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        ScanQrLoginDialog(sessionId: scanned.substring(kQrIssuePrefix.length)),
  );
}

class _InstructionDialog extends ConsumerWidget {
  const _InstructionDialog({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(strings.qrScanLoginButton);
    final content = Text(strings.qrScanLoginInstructionMessage);
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
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}

/// 読み取ったQRのセッションにログインを要求し、ログイン済み端末の許可を待って
/// サインインする。拒否・期限切れ・エラーは文言を出して閉じられる。
class ScanQrLoginDialog extends ConsumerStatefulWidget {
  const ScanQrLoginDialog({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<ScanQrLoginDialog> createState() => _ScanQrLoginDialogState();
}

class _ScanQrLoginDialogState extends ConsumerState<ScanQrLoginDialog> {
  static const _timeout = Duration(minutes: 3);

  String? _message;
  bool _claiming = false;
  StreamSubscription<String>? _subscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final repo = ref.read(authRepositoryProvider);
    final strings = ref.read(appStringsProvider);
    try {
      await repo.requestIssuedQrLogin(widget.sessionId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = strings.qrScanLoginRequestError);
      return;
    }
    if (!mounted) return;
    _subscription = repo.watchQrLoginSessionStatus(widget.sessionId).listen((
      status,
    ) {
      if (status == 'approved' && !_claiming) {
        _claim();
      } else if (status == 'denied') {
        setState(() => _message = strings.qrScanLoginDenied);
      } else if (status == 'expired') {
        setState(() => _message = strings.qrLoginExpiredMessage);
      }
    });
    _timer = Timer(_timeout, () {
      if (!mounted || _claiming) return;
      setState(
        () => _message = ref.read(appStringsProvider).qrLoginExpiredMessage,
      );
    });
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .claimQrLoginSession(widget.sessionId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _message = ref.read(appStringsProvider).qrLoginSignInError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(strings.qrScanLoginWaitingTitle);
    final content = _message != null
        ? Text(_message!)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.qrScanLoginWaitingMessage),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
