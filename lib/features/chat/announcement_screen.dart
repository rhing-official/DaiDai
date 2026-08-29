import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/official_account.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import 'chat_screen.dart';

const _contactFormUrl = 'https://rhing.jp/contact?type=user';

Future<void> _openContactForm() async {
  final uri = Uri.tryParse(_contactFormUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 運営からのお知らせ（便り）を表示する読み取り専用画面（2026-08-12追加）。
/// 設定＞運営から開く。通常の一対と同じ[ChatScreen]の見た目を使うが、
/// [ChatScreen.onSend]をnullにして入力欄自体を出さない。
class AnnouncementScreen extends ConsumerWidget {
  const AnnouncementScreen({
    required this.currentUser,
    this.onSwipeBack,
    super.key,
  });

  final AppUser currentUser;

  /// 縦表示（`/announcements`ルート）で、吹き出しの上を右スワイプした時に
  /// 前の画面へ戻る処理。`DmChatPane.onSwipeBack`と同じく、設定の広い画面
  /// （サイドバーを残したまま内容ペインに埋め込む表示）からはnullのまま
  /// 渡す（戻る概念が無く、他のカテゴリを選ぶだけのため）。
  final VoidCallback? onSwipeBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final dmId = DirectMessage.idFor(currentUser.userId, officialAccountUid);

    return StreamBuilder<List<DirectMessage>>(
      stream: dmRepository.watchDirectMessages(currentUser.userId),
      builder: (context, snapshot) {
        final dm = (snapshot.data ?? const []).firstWhereOrNull(
          (d) => d.dmId == dmId,
        );
        // まだ一度も配信を受け取っていない場合は便りとの一対自体が
        // 存在しないため、空の会話として表示する（通常の一対と同じ挙動）。
        return ChatScreen(
          key: ValueKey('announcements-${dm?.defaultRoomId ?? 'none'}'),
          title: '',
          currentUserId: currentUser.userId,
          isDm: true,
          forceShowSenderInfo: true,
          conversationId: dm?.dmId,
          messagesStream: dm == null
              ? const Stream.empty()
              : dmRepository
                    .watchMessages(dm.dmId, dm.defaultRoomId)
                    .map(
                      (messages) => messages
                          .where(
                            (m) => !m.hiddenFor.contains(currentUser.userId),
                          )
                          .toList(),
                    ),
          banner: const _ContactFormBanner(),
          onSwipeBack: onSwipeBack,
        );
      },
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
