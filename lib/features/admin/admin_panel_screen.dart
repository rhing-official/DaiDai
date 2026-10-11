import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../models/message.dart';
import '../../models/official_profile.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../router/back_stack.dart';
import '../../widgets/nav_chip.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_tab.dart';
import 'admin_user_list.dart';

/// 運営向け管理画面本体（2026-08-12新設）。住人一覧・お便り・お便りの
/// 身だしなみ・設定の4タブを、利用者画面のホームと同じ丸いナビチップで
/// 切り替える（2026-10-10、以前は`AppBar`と`NavigationRail`の独自UI・
/// モノクロ固定テーマだったが、利用者画面と同じ見た目・操作感に揃えた。
/// 見た目はユーザー設定のUIスタイル・アクセントカラー・フォントに従う）。
/// [AdminGate]経由でのみ到達する（管理者クレームを確認済み）。
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  int _selectedIndex = 0;

  static const _icons = [
    Icons.people_outline,
    Icons.campaign_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
  ];

  /// [_icons]の各グリフの見た目の密度差を補正する表示サイズ
  /// （ホーム画面の`_iconSizes`と同じ考え方）。
  static const _iconSizes = [24.0, 24.0, 28.0, 28.0];

  static const _labels = ['住人一覧', 'お便り', '身だしなみ', '設定'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ChipNavShell(
          icons: _icons,
          iconSizes: _iconSizes,
          labels: _labels,
          selectedIndex: _selectedIndex,
          onSelected: (i) => setState(() => _selectedIndex = i),
          isSwipeBlocked: () =>
              ref.read(backStackControllerProvider).hasOpenOverlay,
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              AdminUserListSection(currentUserId: widget.currentUser.userId),
              _AnnouncementSection(currentUser: widget.currentUser),
              const _OfficialProfileSection(),
              const ApplicationSettingsView(),
            ],
          ),
        ),
      ),
    );
  }
}

/// お便りセクション本体。配信済みのお便りを、住人が見るのと同じ[ChatScreen]
/// （発信元の名前・アイコン付き）で一覧し、入力欄から送ると
/// `broadcastAnnouncement`で全住人へ配信する（2026-08-12追加、2026-10-10に
/// 一対ではなく`announcements`をデータ源に変更。お便りは住人ではないため、
/// 管理者自身との一対は無い）。
class _AnnouncementSection extends ConsumerStatefulWidget {
  const _AnnouncementSection({required this.currentUser});

  final AppUser currentUser;

  @override
  ConsumerState<_AnnouncementSection> createState() =>
      _AnnouncementSectionState();
}

class _AnnouncementSectionState extends ConsumerState<_AnnouncementSection> {
  late final Stream<List<Message>> _messages = ref
      .read(announcementRepositoryProvider)
      .watchAnnouncementMessages();

  Future<void> _send(
    String content, {
    bool silent = false,
    Message? replyTo,
    MessageMentions mentions = MessageMentions.none,
  }) => ref.read(announcementRepositoryProvider).broadcast(content);

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      key: const ValueKey('admin-broadcast'),
      title: '',
      currentUserId: widget.currentUser.userId,
      isDm: true,
      forceShowSenderInfo: true,
      conversationId: null,
      messagesStream: _messages,
      onSend: _send,
    );
  }
}

/// お便り（運営の発信元）の身だしなみ（名前・アイコン）セクション
/// （2026-08-12追加、2026-10-10に`system/official`の編集へ変更）。お便りは
/// 住人（`users`）ではないため、蔵・工房は使わず、名前とアイコン1枚だけを
/// 管理者が直接編集する。書き込みはfirestore.rules・storage.rulesの
/// 管理者限定の許可（`system/official`・`officialAssets/**`）による。
class _OfficialProfileSection extends ConsumerStatefulWidget {
  const _OfficialProfileSection();

  @override
  ConsumerState<_OfficialProfileSection> createState() =>
      _OfficialProfileSectionState();
}

class _OfficialProfileSectionState
    extends ConsumerState<_OfficialProfileSection> {
  late final Stream<OfficialProfile> _profileStream = ref
      .read(announcementRepositoryProvider)
      .watchOfficialProfile();
  final _nameController = TextEditingController();
  bool _nameInitialized = false;
  bool _uploadingIcon = false;
  bool _savingName = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _nameController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _showBanner(String message) {
    if (!mounted) return;
    _bannerTimer = showAutoDismissBanner(
      context,
      message: message,
      previousTimer: _bannerTimer,
    );
  }

  Future<void> _pickAndUploadIcon() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      await ref.read(announcementRepositoryProvider).updateOfficialIcon(bytes);
    } catch (e) {
      _showBanner('アイコンの更新に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  Future<void> _saveName(OfficialProfile profile) async {
    final text = _nameController.text.trim();
    if (text.isEmpty || text == profile.name) return;
    setState(() => _savingName = true);
    try {
      await ref.read(announcementRepositoryProvider).updateOfficialName(text);
    } catch (e) {
      _showBanner('名前の更新に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OfficialProfile>(
      stream: _profileStream,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();
        if (!_nameInitialized) {
          _nameInitialized = true;
          _nameController.text = profile.name;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('アイコン', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _OfficialIconButton(
                  iconUrl: profile.iconUrl,
                  uploading: _uploadingIcon,
                  onTap: _pickAndUploadIcon,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  enabled: !_savingName,
                  decoration: const InputDecoration(labelText: '名前'),
                  onSubmitted: (_) => _saveName(profile),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 蔵（身だしなみ）のアイコン登録UIと同じ「丸に+」の見た目を再現する
/// アイコン変更ボタン（2026-08-26追加）。未登録時は`Icons.add`、登録済みなら
/// アイコン画像を丸の中に表示し、タップで[onTap]を呼ぶ。
class _OfficialIconButton extends StatelessWidget {
  const _OfficialIconButton({
    required this.iconUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? iconUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        shape: const CircleBorder(),
        color: colorScheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: uploading ? null : onTap,
          child: Center(
            child: uploading
                ? const SizedBox.shrink()
                : iconUrl == null
                ? Icon(Icons.add, color: colorScheme.onSurfaceVariant, size: 28)
                : Image.network(
                    iconUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}
