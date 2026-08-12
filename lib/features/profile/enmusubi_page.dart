import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/web_link.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/qr_scan_screen.dart';

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

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
  }

  Future<void> _openScanner(BuildContext context) async {
    final title = ref.read(appStringsProvider).enmusubiScanScreenTitle;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => QrScanScreen(title: title)),
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
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GekigaSectionHeader(strings.enmusubiInviteLinkTitle),
            const SizedBox(height: 4),
            Text(strings.enmusubiInviteLinkDescription),
            const SizedBox(height: 12),
            isGekiga
                ? GekigaJointedTileList(
                    seeds: [link.hashCode],
                    selectedFlags: const [true],
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                link,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: GekigaColors.panel,
                                ),
                              ),
                            ),
                            GekigaIconButton(
                              icon: Icons.copy_outlined,
                              onPressed: () => _copyLink(link),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: SelectableText(link, maxLines: 1)),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () => _copyLink(link),
                        ),
                      ],
                    ),
                  ),
            const SizedBox(height: 32),
            GekigaSectionHeader(strings.enmusubiQrTitle),
            const SizedBox(height: 4),
            Text(strings.enmusubiQrDescription),
            const SizedBox(height: 16),
            Center(
              child: isGekiga
                  ? GekigaJointedTileList(
                      seeds: [link.hashCode + 1],
                      selectedFlags: const [true],
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: QrImageView(data: link, size: 200),
                        ),
                      ],
                    )
                  : Container(
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
              child: isGekiga
                  ? GekigaJointedTileList(
                      seeds: [strings.enmusubiScanButton.hashCode],
                      selectedFlags: const [true],
                      children: [
                        GekigaButton(
                          label: strings.enmusubiScanButton,
                          icon: Icons.qr_code_scanner,
                          onPressed: () => _openScanner(context),
                        ),
                      ],
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(strings.enmusubiScanButton),
                      onPressed: () => _openScanner(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
