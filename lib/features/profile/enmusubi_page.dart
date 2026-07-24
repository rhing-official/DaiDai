import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../utils/web_link.dart';

String _inviteLinkFor(String rhingId) => buildWebLink('/invite/$rhingId');

/// QRコードや招待リンクとして共有された文字列から、招待元のRhing IDを
/// 取り出す。`https://.../invite/<rhingId>`の形式であれば platform/host を
/// 問わず解決できる。
String? parseInviteRhingId(String data) {
  final uri = Uri.tryParse(data.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final index = segments.indexOf('invite');
  if (index == -1 || index + 1 >= segments.length) return null;
  final rhingId = segments[index + 1];
  return rhingId.isEmpty ? null : rhingId;
}

/// 縁結びページ: 自分の招待リンク・QRコードの表示と、相手のQRコードを
/// 読み取って仲間申請を送る導線。
class EnmusubiPage extends ConsumerStatefulWidget {
  const EnmusubiPage({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<EnmusubiPage> createState() => _EnmusubiPageState();
}

class _EnmusubiPageState extends ConsumerState<EnmusubiPage> {
  AppUser get currentUser => widget.currentUser;

  @override
  void initState() {
    super.initState();
    // この画面を開くたびに公開プレビュー（userInvites）を最新化する。
    // 蔵の更新時にも自動同期されるが、この機能追加より前から使っている
    // ユーザーはまだ一度も同期が走っていないため、ここでバックフィルする。
    ref.read(userRepositoryProvider).syncInvitePreview(currentUser.userId);
  }

  Future<void> _copyLink(BuildContext context, Strings strings, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.enmusubiLinkCopied)),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _QrScanScreen()),
    );
    if (scanned == null || !context.mounted) return;
    final rhingId = parseInviteRhingId(scanned);
    if (rhingId == null) return;
    context.push('/invite/$rhingId');
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final link = _inviteLinkFor(currentUser.rhingId);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.enmusubiInviteLinkTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(strings.enmusubiInviteLinkDescription),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(link, maxLines: 1),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: strings.enmusubiCopyLink,
                onPressed: () => _copyLink(context, strings, link),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          strings.enmusubiQrTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(strings.enmusubiQrDescription),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: QrImageView(data: link, size: 200),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(strings.enmusubiScanButton),
            onPressed: () => _openScanner(context),
          ),
        ),
      ],
    );
  }
}

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null) return;
    _handled = true;
    Navigator.of(context).pop(rawValue);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final strings = ref.watch(appStringsProvider);
        return Scaffold(
          appBar: AppBar(title: Text(strings.enmusubiScanScreenTitle)),
          body: MobileScanner(onDetect: _onDetect),
        );
      },
    );
  }
}
