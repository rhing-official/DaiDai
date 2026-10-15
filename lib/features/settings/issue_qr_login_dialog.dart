import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// ログイン済み端末がQRコードを表示し、ログインしたい端末が読み取ってログインする
/// 方式（2026-10-15）の表示側。開くと`createIssuedQrLoginSession`でセッションを作って
/// `daidai:qrissue:{sessionId}`のQRを出し、読み取られたら（status=requested）「ログインを
/// 許可しますか？」を出す。許可すると読み取った端末がログインできる。QRは2分で失効。
class IssueQrLoginDialog extends ConsumerStatefulWidget {
  const IssueQrLoginDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const IssueQrLoginDialog(),
    );
  }

  @override
  ConsumerState<IssueQrLoginDialog> createState() => _IssueQrLoginDialogState();
}

class _IssueQrLoginDialogState extends ConsumerState<IssueQrLoginDialog> {
  static const _ttl = Duration(minutes: 2);

  String? _sessionId;
  String _status = 'pending';
  bool _expired = false;
  bool _failed = false;
  bool _responding = false;
  StreamSubscription<String>? _subscription;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _sessionId = null;
      _status = 'pending';
      _expired = false;
      _failed = false;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      final id = await repo.createIssuedQrLoginSession();
      if (!mounted) return;
      setState(() => _sessionId = id);
      _subscription?.cancel();
      _subscription = repo.watchQrLoginSessionStatus(id).listen((status) {
        if (!mounted) return;
        setState(() => _status = status);
        if (status == 'claimed') Navigator.of(context).pop();
      });
      _expiryTimer?.cancel();
      _expiryTimer = Timer(_ttl, () {
        if (!mounted) return;
        _subscription?.cancel();
        setState(() => _expired = true);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _respond(bool approve) async {
    final id = _sessionId;
    if (id == null || _responding) return;
    setState(() => _responding = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .respondIssuedQrLogin(id, approve: approve);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _responding = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final requested = _status == 'requested' && !_expired;
    final title = Text(
      requested ? strings.qrIssueRequestTitle : strings.qrIssueDialogTitle,
    );
    final content = SizedBox(width: 280, child: _body(context, strings));
    final actions = requested
        ? [
            TextButton(
              onPressed: _responding ? null : () => _respond(false),
              child: Text(strings.qrIssueDeny),
            ),
            FilledButton(
              onPressed: _responding ? null : () => _respond(true),
              child: Text(strings.qrIssueAllow),
            ),
          ]
        : [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.cancel),
            ),
          ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }

  Widget _body(BuildContext context, Strings strings) {
    if (_failed) {
      return Text(strings.qrIssueError);
    }
    final id = _sessionId;
    if (id == null) return const SizedBox(height: 200);
    if (_expired) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.qrLoginExpiredMessage),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _start,
            child: Text(strings.qrLoginRefreshButton),
          ),
        ],
      );
    }
    if (_status == 'requested') {
      return Text(strings.qrIssueRequestMessage);
    }
    if (_status == 'approved') {
      return Text(strings.qrIssueApproved);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.qrIssueDialogDescription),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: QrImageView(data: 'daidai:qrissue:$id', size: 200),
        ),
        const SizedBox(height: 8),
        Text(
          strings.qrIssueExpiresHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
