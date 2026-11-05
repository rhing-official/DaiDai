import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// QRコードログイン（未ログイン端末側）のQRコード表示部分（2026-11-06、
/// `QrLoginDialog`から切り出し）。表示されるとすぐ`qrLoginSessions`にpendingな
/// セッションを作ってQRコードを出し、ログイン済みの別端末が承認するのを待つ。承認を
/// 検知したらカスタムトークンでサインインし、[onClaimed]を呼ぶ（以降は`AuthGate`が
/// 認証状態の変化で画面を遷移する）。ダイアログ（`QrLoginDialog`）と、コンピューター
/// のログイン画面の右側（`SignInScreen`）の両方で使う。
class QrLoginPanel extends ConsumerStatefulWidget {
  const QrLoginPanel({
    super.key,
    this.onClaimed,
    this.qrSize = 200,
    this.autoRefresh = false,
    this.showDescription = true,
  });

  /// サインインが完了した時に呼ぶ。
  final VoidCallback? onClaimed;
  final double qrSize;

  /// trueなら、期限が切れたら押さなくても新しいQRコードに作り直す
  /// （ログイン画面に出しっぱなしにする場合）。
  final bool autoRefresh;

  /// QRコードの上に説明文を出すか。
  final bool showDescription;

  @override
  ConsumerState<QrLoginPanel> createState() => _QrLoginPanelState();
}

class _QrLoginPanelState extends ConsumerState<QrLoginPanel> {
  static const _sessionTtl = Duration(minutes: 3);

  String? _sessionId;
  StreamSubscription<String>? _statusSubscription;
  Timer? _expiryTimer;
  bool _isExpired = false;
  bool _isClaiming = false;
  bool _failed = false;
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
      _failed = false;
      _errorMessage = null;
    });
    try {
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
        if (widget.autoRefresh) {
          _startSession();
        } else {
          setState(() => _isExpired = true);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
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
      widget.onClaimed?.call();
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
    final size = widget.qrSize;
    if (_failed) {
      return _retry(strings, strings.qrLoginSignInError);
    }
    if (sessionId == null) {
      return SizedBox(height: size + 32, width: size + 32);
    }
    if (_isExpired) {
      return _retry(strings, strings.qrLoginExpiredMessage);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showDescription) ...[
          Text(strings.qrLoginDialogDescription),
          const SizedBox(height: 16),
        ],
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
              QrImageView(data: 'daidai:qrlogin:$sessionId', size: size),
              if (_isClaiming)
                Container(
                  width: size,
                  height: size,
                  color: Colors.white70,
                  child: const SizedBox.shrink(),
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

  Widget _retry(Strings strings, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 60),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _startSession,
          child: Text(strings.qrLoginRefreshButton),
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}
