import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// QRコードログイン（未ログイン端末側、2026-08-09追加）。開くとすぐに
/// `qrLoginSessions`にpendingなセッションを作成してQRコードを表示し、
/// ログイン済みの別端末（設定＞アカウント＞セキュリティ＞QRコードによる
/// ログインからスキャン）が承認するのを待つ。承認を検知したら自動的に
/// カスタムトークンでサインインし、ダイアログを閉じる（以降は`AuthGate`が
/// 認証状態の変化を検知して自動的に画面遷移する）。
class QrLoginDialog extends ConsumerStatefulWidget {
  const QrLoginDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const QrLoginDialog(),
    );
  }

  @override
  ConsumerState<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends ConsumerState<QrLoginDialog> {
  static const _sessionTtl = Duration(minutes: 3);

  String? _sessionId;
  StreamSubscription<String>? _statusSubscription;
  Timer? _expiryTimer;
  bool _isExpired = false;
  bool _isClaiming = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() {
      _sessionId = null;
      _isExpired = false;
      _errorMessage = null;
    });
    final sessionId = await ref
        .read(authRepositoryProvider)
        .createQrLoginSession();
    if (!mounted) return;
    setState(() => _sessionId = sessionId);

    _statusSubscription?.cancel();
    _statusSubscription = ref
        .read(authRepositoryProvider)
        .watchQrLoginSessionStatus(sessionId)
        .listen(_onStatusChange);

    _expiryTimer?.cancel();
    _expiryTimer = Timer(_sessionTtl, () {
      if (!mounted) return;
      _statusSubscription?.cancel();
      setState(() => _isExpired = true);
    });
  }

  void _onStatusChange(String status) {
    if (status == 'approved' && !_isClaiming) {
      _claim();
    }
  }

  Future<void> _claim() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() {
      _isClaiming = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).claimQrLoginSession(sessionId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _errorMessage = ref.read(appStringsProvider).qrLoginSignInError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final sessionId = _sessionId;
    return AlertDialog(
      title: Text(strings.qrLoginDialogTitle),
      content: SizedBox(
        width: 280,
        child: _buildBody(context, strings, sessionId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Strings strings, String? sessionId) {
    if (sessionId == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isExpired) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 60),
          Text(strings.qrLoginExpiredMessage),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _startSession,
            child: Text(strings.qrLoginRefreshButton),
          ),
          const SizedBox(height: 60),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.qrLoginDialogDescription),
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(data: 'daidai:qrlogin:$sessionId', size: 200),
              if (_isClaiming)
                Container(
                  width: 200,
                  height: 200,
                  color: Colors.white70,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
