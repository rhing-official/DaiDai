import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import 'chat_screen.dart';

const _contactFormUrl = 'https://rhing.jp/contact?type=user';

Future<void> _openContactForm() async {
  final uri = Uri.tryParse(_contactFormUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 運営からのお便りを表示する読み取り専用画面（2026-08-12追加、2026-10-10に
/// データ源を`announcements`へ変更）。設定＞運営から開く。通常の一対と同じ
/// [ChatScreen]の見た目を使うが、[ChatScreen.onSend]をnullにして入力欄自体を
/// 出さない。お便りは住人ではなく`announcements`・`system/official`という
/// 「そこにある物」のため、各住人との一対は使わない。
class AnnouncementScreen extends ConsumerStatefulWidget {
  const AnnouncementScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends ConsumerState<AnnouncementScreen> {
  // ChatScreenが同じストリームを購読し続けられるよう、1度だけ作る。
  late final Stream<List<Message>> _messages = ref
      .read(announcementRepositoryProvider)
      .watchAnnouncementMessages();

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      key: const ValueKey('announcements'),
      title: '',
      currentUserId: widget.currentUser.userId,
      isDm: true,
      forceShowSenderInfo: true,
      conversationId: null,
      messagesStream: _messages,
      banner: const _ContactFormBanner(),
    );
  }
}

/// 質問フォームへの導線ブロック（2026-08-12、旧: AppBarの小さいアイコン
/// ボタンから、右寄せのタップ可能なブロックへ変更）。現在のUIスタイル
/// （劇画/フラット）の配色に合わせて分岐する。
class _ContactFormBanner extends ConsumerWidget {
  const _ContactFormBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final label = strings.announcementContactFormLabel;
    final button = isGekiga
        ? GekigaJointedTileList(
            seeds: const [0],
            selectedFlags: const [false],
            children: [
              GekigaButton(
                label: label,
                icon: Icons.contact_support_outlined,
                onPressed: _openContactForm,
                selected: false,
              ),
            ],
          )
        : _FlatContactFormButton(label: label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Align(alignment: Alignment.centerRight, child: button),
    );
  }
}

class _FlatContactFormButton extends StatelessWidget {
  const _FlatContactFormButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openContactForm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.contact_support_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
