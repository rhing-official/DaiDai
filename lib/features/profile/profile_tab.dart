import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/profile_card.dart';
import '../../models/profile_material.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../repositories/user_repository.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/motion.dart';
import '../../utils/text_truncate.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/profile_card_picker.dart';
import '../../widgets/profile_card_view.dart';
import '../../widgets/swipe_gestures.dart';
import '../chat/conversation_profile_card_dialog.dart';
import 'enmusubi_page.dart';

enum _ProfileSection { kura, koubou, enmusubi }

/// 画面幅がこれ以上あれば、左にカテゴリ一覧（サイドバー）、右にそのカテゴリの
/// 内容を表示する2ペイン表示にする。設定タブ（`settings_tab.dart`）と同じ
/// 考え方・同じ閾値。これ未満の狭い画面では、カテゴリ一覧→内容の1段だけ
/// ドリルダウンする。
const _kProfileSplitBreakpoint = 760.0;

/// サイドバーの幅。
// 設定・運営タブのサイドバー（`_kSettingsSidebarWidth`/`_kSupportSidebarWidth`）
// と幅をそろえる（以前は220でわずかにずれていた）。
const _kProfileSidebarWidth = 240.0;

/// ニックネーム・ステメ・プロフィールカードのローカル採番id。
/// 以前は`Random().nextInt(1 << 32)`だったが、`1 << 32`はDart VM（ウィジェット
/// テストの実行環境）では4294967296になる一方、Web（dart2js/DDC）では
/// JSのビット演算が32bit符号あり整数に切り詰められるため0になり、
/// `Random().nextInt(0)`が即座にRangeErrorを投げてsetStateの手前で
/// 処理が止まっていた（「ダイアログは閉じるが何も起こらない」の実体）。
/// 画像素材はFirestoreの`doc().id`でidを採番しておりこの経路を通らないため、
/// 影響は文字系の項目（ニックネーム・ステメ・工房カード）だけに出ていた。
/// ビット演算を経由しない10進リテラルにすることでVM・Web両方で正しく動く。
String _newLocalId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(4294967296)}';

/// 身だしなみタブ。「蔵」（素材の登録・管理）と「工房」（蔵の素材を組み合わせた
/// プロフィールカードの作成）をボタンで切り替えて表示する。
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({required this.currentUser, this.resetSignal, super.key});

  final AppUser currentUser;

  /// 発火すると、ドリルダウン中のカテゴリ詳細をカテゴリ一覧トップへ戻す
  /// （2026-08-10追加、`home_screen.dart`のナビゲーションチップ再タップから
  /// 渡される）。
  final Listenable? resetSignal;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  late AppUser _user;
  bool _uploadingIcon = false;
  bool _uploadingBackground = false;

  /// 狭い画面のドリルダウンでのみ使う、選択中カテゴリ。
  /// 広い画面では常に先頭（蔵）を既定選択として表示する。
  _ProfileSection? _selectedSection;

  /// 工房の空き枠タップでカード編集画面を開く処理は、Hero遷移のフェード時間
  /// （300ms）の間にInkWellへの反応が一瞬遅れて見えることがあり、その間に
  /// 連打・ダブルタップされると[_openCardZoom]が多重に呼ばれ、同じ枠に対して
  /// 別々のidを持つカードが2件作られてしまう不具合があった。開いている間は
  /// 再入をブロックして防ぐ。
  bool _cardZoomOpening = false;

  /// 起動時（ログイン時）に一度だけ取得したスナップショットのまま
  /// `_user`を保持し続けていたため、他端末・他セッションでの変更が
  /// 画面に反映されず、しかもローカルが把握している「削除すべき古い値」が
  /// サーバーの実データと食い違うことで工房カードの重複が起きる一因にも
  /// なっていた。Firestoreの変更をリアルタイムに購読し、`_user`を
  /// 常に最新へ追従させる。
  StreamSubscription<AppUser?>? _userSub;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _userSub = _repository.watchUser(widget.currentUser.userId).listen((user) {
      if (user != null && mounted) setState(() => _user = user);
    });
    widget.resetSignal?.addListener(_handleResetSignal);
  }

  @override
  void didUpdateWidget(ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      oldWidget.resetSignal?.removeListener(_handleResetSignal);
      widget.resetSignal?.addListener(_handleResetSignal);
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    widget.resetSignal?.removeListener(_handleResetSignal);
    super.dispose();
  }

  void _handleResetSignal() {
    if (_selectedSection != null) setState(() => _selectedSection = null);
  }

  UserRepository get _repository => ref.read(userRepositoryProvider);

  // 蔵の各セクション（アイコン・背景画像・ステメ・ニックネーム）は、追加操作が
  // それぞれ独立して非同期に走る（特にアップロード系はStorage往復で数秒かかる）。
  // 以前はローカルで組み立てたAppUser全体を`.set()`で丸ごと上書きしていたため、
  // 「アイコンのアップロード中にニックネームを追加する」のように複数の操作が
  // 重なると、後から完了した書き込みが先に完了した書き込みを消してしまう
  // 競合（lost update）が起きていた（activeIconIdが存在しないicon idを指す、
  // 追加したはずのニックネームがFirestore上には一切残っていない、といった形で
  // 実際に確認された）。[_addToList]/[_removeFromList]/[_setField]は
  // Firestoreの`arrayUnion`/`arrayRemove`とフィールド単位の`update()`を使い、
  // サーバー側で原子的にマージされるようにすることでこの競合を解消する。

  Future<void> _addToList(String field, Map<String, dynamic> value) async {
    try {
      await _repository.addToProfileList(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _removeFromList(String field, Map<String, dynamic> value) async {
    try {
      await _repository.removeFromProfileList(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _setField(String field, String? value) async {
    try {
      await _repository.setProfileField(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndUploadIcon() async {
    if (_user.icons.length >= kMaxIcons) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      final material = await _repository.uploadIcon(_user.userId, bytes);
      final shouldActivate = _user.activeIconId == null;
      setState(() {
        _user = _user.copyWith(
          icons: [..._user.icons, material],
          activeIconId: _user.activeIconId ?? material.id,
        );
      });
      await _addToList('icons', material.toJson());
      if (shouldActivate) await _setField('activeIconId', material.id);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileIconUploadError}: $e');
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  Future<void> _pickAndUploadBackground() async {
    if (_user.backgroundImages.length >= kMaxBackgroundImages) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingBackground = true);
    try {
      final bytes = await picked.readAsBytes();
      final material = await _repository.uploadBackgroundImage(
        _user.userId,
        bytes,
      );
      final shouldActivate = _user.activeBackgroundImageId == null;
      setState(() {
        _user = _user.copyWith(
          backgroundImages: [..._user.backgroundImages, material],
          activeBackgroundImageId: _user.activeBackgroundImageId ?? material.id,
        );
      });
      await _addToList('backgroundImages', material.toJson());
      if (shouldActivate) {
        await _setField('activeBackgroundImageId', material.id);
      }
    } catch (e) {
      _showError(
        '${ref.read(appStringsProvider).profileBackgroundUploadError}: $e',
      );
    } finally {
      if (mounted) setState(() => _uploadingBackground = false);
    }
  }

  Future<void> _deleteIcon(ProfileMaterial material) async {
    final remaining = _user.icons.where((m) => m.id != material.id).toList();
    final wasActive = _user.activeIconId == material.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeIconId;
    setState(() {
      _user = _user.copyWith(icons: remaining, activeIconId: nextActiveId);
    });
    await _removeFromList('icons', material.toJson());
    if (wasActive) await _setField('activeIconId', nextActiveId);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileIconUploadError}: $e');
    }
  }

  Future<void> _deleteBackground(ProfileMaterial material) async {
    final remaining = _user.backgroundImages
        .where((m) => m.id != material.id)
        .toList();
    final wasActive = _user.activeBackgroundImageId == material.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeBackgroundImageId;
    setState(() {
      _user = _user.copyWith(
        backgroundImages: remaining,
        activeBackgroundImageId: nextActiveId,
      );
    });
    await _removeFromList('backgroundImages', material.toJson());
    if (wasActive) await _setField('activeBackgroundImageId', nextActiveId);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError(
        '${ref.read(appStringsProvider).profileBackgroundUploadError}: $e',
      );
    }
  }

  Future<void> _addStatusMessage() async {
    if (_user.statusMessages.length >= kMaxStatusMessages) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => const _StatusMessageDialog(),
    );
    final text = result?.text?.trim();
    if (text == null || text.isEmpty) return;

    final message = StatusMessage(id: _newLocalId(), text: text);
    final shouldActivate = _user.activeStatusMessageId == null;
    setState(() {
      _user = _user.copyWith(
        statusMessages: [..._user.statusMessages, message],
        activeStatusMessageId: _user.activeStatusMessageId ?? message.id,
      );
    });
    await _addToList('statusMessages', message.toJson());
    if (shouldActivate) await _setField('activeStatusMessageId', message.id);
  }

  Future<void> _editStatusMessage(StatusMessage message) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _StatusMessageDialog(initialText: message.text),
    );
    if (result == null) return;
    if (result.isDelete) {
      await _deleteStatusMessage(message);
      return;
    }

    final text = result.text?.trim();
    if (text == null || text.isEmpty || text == message.text) return;

    // id自体は変えず本文だけ差し替える。activeStatusMessageIdは
    // idで参照しているため、id維持であれば選択状態は自動的に保たれる。
    final updated = StatusMessage(id: message.id, text: text);
    setState(() {
      _user = _user.copyWith(
        statusMessages: [
          for (final m in _user.statusMessages)
            if (m.id == message.id) updated else m,
        ],
      );
    });
    await _removeFromList('statusMessages', message.toJson());
    await _addToList('statusMessages', updated.toJson());
  }

  Future<void> _deleteStatusMessage(StatusMessage message) async {
    final remaining = _user.statusMessages
        .where((m) => m.id != message.id)
        .toList();
    final wasActive = _user.activeStatusMessageId == message.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeStatusMessageId;
    setState(() {
      _user = _user.copyWith(
        statusMessages: remaining,
        activeStatusMessageId: nextActiveId,
      );
    });
    await _removeFromList('statusMessages', message.toJson());
    if (wasActive) await _setField('activeStatusMessageId', nextActiveId);
  }

  Future<void> _addNickname() async {
    if (_user.nicknames.length >= kMaxNicknames) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => const _NicknameDialog(),
    );
    final text = result?.text?.trim();
    if (text == null || text.isEmpty) return;

    final nickname = Nickname(id: _newLocalId(), text: text);
    final shouldActivate = _user.activeNicknameId == null;
    setState(() {
      _user = _user.copyWith(
        nicknames: [..._user.nicknames, nickname],
        activeNicknameId: _user.activeNicknameId ?? nickname.id,
      );
    });
    await _addToList('nicknames', nickname.toJson());
    if (shouldActivate) await _setField('activeNicknameId', nickname.id);
  }

  Future<void> _editNickname(Nickname nickname) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _NicknameDialog(initialText: nickname.text),
    );
    if (result == null) return;
    if (result.isDelete) {
      await _deleteNickname(nickname);
      return;
    }

    final text = result.text?.trim();
    if (text == null || text.isEmpty || text == nickname.text) return;

    final updated = Nickname(id: nickname.id, text: text);
    setState(() {
      _user = _user.copyWith(
        nicknames: [
          for (final n in _user.nicknames)
            if (n.id == nickname.id) updated else n,
        ],
      );
    });
    await _removeFromList('nicknames', nickname.toJson());
    await _addToList('nicknames', updated.toJson());
  }

  Future<void> _deleteNickname(Nickname nickname) async {
    final remaining = _user.nicknames
        .where((n) => n.id != nickname.id)
        .toList();
    final wasActive = _user.activeNicknameId == nickname.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeNicknameId;
    setState(() {
      _user = _user.copyWith(
        nicknames: remaining,
        activeNicknameId: nextActiveId,
      );
    });
    await _removeFromList('nicknames', nickname.toJson());
    if (wasActive) await _setField('activeNicknameId', nextActiveId);
  }

  Future<void> _addSnsLink() async {
    if (_user.snsLinks.length >= kMaxSnsLinks) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => const _SnsLinkDialog(),
    );
    final url = result?.text?.trim();
    if (url == null || url.isEmpty) return;

    final link = SnsLink(id: _newLocalId(), url: url);
    setState(() {
      _user = _user.copyWith(snsLinks: [..._user.snsLinks, link]);
    });
    await _addToList('snsLinks', link.toJson());
  }

  Future<void> _editSnsLink(SnsLink link) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _SnsLinkDialog(initialText: link.url),
    );
    if (result == null) return;
    if (result.isDelete) {
      await _deleteSnsLink(link);
      return;
    }

    final url = result.text?.trim();
    if (url == null || url.isEmpty || url == link.url) return;

    final updated = SnsLink(id: link.id, url: url);
    setState(() {
      _user = _user.copyWith(
        snsLinks: [
          for (final s in _user.snsLinks)
            if (s.id == link.id) updated else s,
        ],
      );
    });
    await _removeFromList('snsLinks', link.toJson());
    await _addToList('snsLinks', updated.toJson());
  }

  Future<void> _deleteSnsLink(SnsLink link) async {
    final remaining = _user.snsLinks.where((s) => s.id != link.id).toList();
    setState(() {
      _user = _user.copyWith(snsLinks: remaining);
    });
    await _removeFromList('snsLinks', link.toJson());
    // カードに掲載中だったURLが削除された場合、そのカード側の参照も外す。
    for (final card in _user.profileCards) {
      if (!card.snsLinkIds.contains(link.id)) continue;
      final updatedCard = card.copyWith(
        snsLinkIds: card.snsLinkIds.where((id) => id != link.id).toList(),
      );
      setState(() {
        _user = _user.copyWith(
          profileCards: [
            for (final c in _user.profileCards)
              if (c.id == card.id) updatedCard else c,
          ],
        );
      });
      await _saveCardToServer(updatedCard);
    }
  }

  Future<void> _saveCard(ProfileCard card, {required bool isNew}) async {
    if (isNew) {
      setState(() {
        _user = _user.copyWith(profileCards: [..._user.profileCards, card]);
      });
    } else {
      setState(() {
        _user = _user.copyWith(
          profileCards: [
            for (final c in _user.profileCards)
              if (c.id == card.id) card else c,
          ],
        );
      });
    }
    await _saveCardToServer(card);
  }

  /// [UserRepository.saveProfileCard]はFirestoreのトランザクションでidを
  /// キーに置き換え/追加するため、新規作成・既存編集どちらも同じ呼び出しで
  /// 済む（以前は編集時だけ「削除→追加」の2手順が必要で、これが非原子的な
  /// ことに起因する重複作成バグの原因になっていた）。
  Future<void> _saveCardToServer(ProfileCard card) async {
    try {
      await _repository.saveProfileCard(_user.userId, card);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _deleteCard(ProfileCard card) async {
    final wasActive = _user.activeProfileCardId == card.id;
    final remaining = _user.profileCards.where((c) => c.id != card.id).toList();
    setState(() {
      _user = _user.copyWith(
        profileCards: remaining,
        clearActiveProfileCardId: wasActive,
      );
    });
    try {
      await _repository.deleteProfileCard(_user.userId, card.id);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _setActiveCard(String cardId) async {
    setState(() {
      _user = _user.copyWith(activeProfileCardId: cardId);
    });
    await _setField('activeProfileCardId', cardId);
  }

  /// カードをタップした位置からズームインさせる形でカード編集画面を開く。
  /// Heroタグはカードの中身ではなく枠の位置（[index]）に紐づけている。
  /// 空き枠→作成後は同じ枠が実カードに置き換わるだけで、開いている最中の
  /// このルート自体は同一タグのHeroを使い続けるため問題ない。
  Future<void> _openCardZoom(int index, ProfileCard? existing) async {
    if (_cardZoomOpening) return;
    _cardZoomOpening = true;
    final strings = ref.read(appStringsProvider);
    final vocab = ref.read(vocabularyProvider);
    try {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: true,
          // カード名入力欄は常にこのバリアの上に表示される（下記
          // _CardZoomEditorのTextField参照）。バリアの不透明度が低いと、下に
          // 見えているページの背景色（ライト/ダークモードで大きく変わる）が
          // 透けて背景の明るさが安定せず、固定色の文字が片方のモードで見えなく
          // なっていた（2026-07-29修正）。不透明度を上げて背景を常に暗く保つ
          // ことで、白文字をライト/ダーク両方で安定して読める状態にした。
          barrierColor: Colors.black87,
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          pageBuilder: (_, animation, secondaryAnimation) => Center(
            // このルートは`opaque: false`のポップアップ的な表示のため、下の
            // ページのScaffoldが提供するMaterial祖先を引き継がない。カード名の
            // `TextField`は開いた瞬間から常に表示されるため、Material祖先が無いと
            // "No Material widget found"で即座にクラッシュしていた。
            // MaterialType.transparencyで見た目（半透明の背景）を変えずに
            // Material祖先だけを補う。
            child: Material(
              type: MaterialType.transparency,
              child: _CardZoomEditor(
                heroTag: 'profile-card-slot-$index',
                user: _user,
                strings: strings,
                vocab: vocab,
                initialCard: existing,
                onCreate: (card) => _saveCard(card, isNew: true),
                onUpdate: (card) => _saveCard(card, isNew: false),
                onDelete: _deleteCard,
              ),
            ),
          ),
        ),
      );
    } finally {
      _cardZoomOpening = false;
    }
  }

  List<_ProfileCategory> _categories(Vocabulary vocab) => [
    _ProfileCategory(
      section: _ProfileSection.kura,
      icon: Icons.inventory_2_outlined,
      title: vocab.profileStorage,
    ),
    _ProfileCategory(
      section: _ProfileSection.koubou,
      icon: Icons.gavel,
      title: vocab.profileCreator,
    ),
    _ProfileCategory(
      section: _ProfileSection.enmusubi,
      icon: Icons.handshake_outlined,
      title: vocab.friendConnect,
    ),
  ];

  Widget _buildContent(
    _ProfileSection section,
    Strings strings,
    Vocabulary vocab,
  ) {
    switch (section) {
      case _ProfileSection.kura:
        return _KuraView(
          user: _user,
          strings: strings,
          vocab: vocab,
          uploadingIcon: _uploadingIcon,
          uploadingBackground: _uploadingBackground,
          onAddIcon: _pickAndUploadIcon,
          onDeleteIcon: _deleteIcon,
          onAddBackground: _pickAndUploadBackground,
          onDeleteBackground: _deleteBackground,
          onAddNickname: _addNickname,
          onEditNickname: _editNickname,
          onAddStatusMessage: _addStatusMessage,
          onEditStatusMessage: _editStatusMessage,
          onAddSnsLink: _addSnsLink,
          onEditSnsLink: _editSnsLink,
        );
      case _ProfileSection.koubou:
        return _WorkshopView(
          user: _user,
          strings: strings,
          vocab: vocab,
          onTapSlot: _openCardZoom,
          onSetActive: _setActiveCard,
        );
      case _ProfileSection.enmusubi:
        return EnmusubiPage(currentUser: _user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final categories = _categories(vocab);
    final isWide = MediaQuery.sizeOf(context).width >= _kProfileSplitBreakpoint;

    if (isWide) {
      final selected =
          _findCategory(categories, _selectedSection) ?? categories.first;
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _kProfileSidebarWidth,
              child: _ProfileCategoryList(
                categories: categories,
                selectedSection: selected.section,
                onSelect: (category) =>
                    setState(() => _selectedSection = category.section),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildContent(selected.section, strings, vocab)),
          ],
        ),
      );
    }

    final selected = _findCategory(categories, _selectedSection);
    final selectedIndex = selected == null
        ? -1
        : categories.indexWhere((c) => c.section == selected.section);
    final nextCategory =
        selectedIndex >= 0 && selectedIndex < categories.length - 1
        ? categories[selectedIndex + 1]
        : null;
    // 狭い画面での上端位置は設定タブ（settings_tab.dartの`_SettingsTabState`）
    // と揃える（Align+ConstrainedBox(maxWidth:480)+Padding(top:56)）。
    // カテゴリ一覧⇔詳細の切り替えは設定タブと同じAnimatedSwitcher+
    // buildPopSlideTransitionでポップ演出を付ける（2026-08-10追加、
    // 以前はアニメーション無しの即時切り替えだった）。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: AnimatedSwitcher(
            duration: popSlideDuration,
            transitionBuilder: (child, animation) =>
                buildPopSlideTransition(animation, child),
            child: selected == null
                ? _ProfileCategoryList(
                    key: const ValueKey('profile-categories'),
                    categories: categories,
                    selectedSection: null,
                    onSelect: (category) =>
                        setState(() => _selectedSection = category.section),
                  )
                : KeyedSubtree(
                    key: ValueKey(selected.section),
                    // 右スワイプは常に一覧へ戻る（onPreviousを渡さないことで
                    // SwipeBackDetectorの既定フォールバック=onBackを使う）。
                    // 戻る導線がスワイプに一本化されたため、以前あった
                    // 「←＋セクション名」の見出し行は表示しない。
                    child: SwipeBackDetector(
                      onBack: () => setState(() => _selectedSection = null),
                      onNext: nextCategory == null
                          ? null
                          : () => setState(
                              () => _selectedSection = nextCategory.section,
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildContent(
                              selected.section,
                              strings,
                              vocab,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 身だしなみの最上位カテゴリ1つ分（蔵／工房／縁結び）。
class _ProfileCategory {
  const _ProfileCategory({
    required this.section,
    required this.icon,
    required this.title,
  });

  final _ProfileSection section;
  final IconData icon;
  final String title;
}

_ProfileCategory? _findCategory(
  List<_ProfileCategory> categories,
  _ProfileSection? section,
) {
  if (section == null) return null;
  for (final category in categories) {
    if (category.section == section) return category;
  }
  return null;
}

/// カテゴリ一覧（サイドバー、または狭い画面での一覧画面）。設定タブの
/// `_CategoryList`/`_FolderTile`と同じ見た目にしている。
class _ProfileCategoryList extends ConsumerWidget {
  const _ProfileCategoryList({
    required this.categories,
    required this.selectedSection,
    required this.onSelect,
    super.key,
  });

  final List<_ProfileCategory> categories;
  final _ProfileSection? selectedSection;
  final ValueChanged<_ProfileCategory> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GekigaJointedTileList(
          seeds: [for (final category in categories) category.title.hashCode],
          selectedFlags: [
            for (final category in categories)
              category.section == selectedSection,
          ],
          children: [
            for (final category in categories)
              _ProfileCategoryTile(
                icon: category.icon,
                title: category.title,
                selected: category.section == selectedSection,
                onTap: () => onSelect(category),
              ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final category in categories)
          _ProfileCategoryTile(
            icon: category.icon,
            title: category.title,
            selected: category.section == selectedSection,
            onTap: () => onSelect(category),
          ),
      ],
    );
  }
}

class _ProfileCategoryTile extends ConsumerWidget {
  const _ProfileCategoryTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    if (isGekiga) {
      // 外枠は呼び出し側（`_ProfileCategoryList`の`GekigaJointedTileList`）が
      // まとめて描くため、ここでは内容だけを返す（2026-08-04変更）。
      return GekigaTileContent(
        selected: selected,
        leading: Icon(icon),
        title: Text(title),
        onTap: onTap,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: selected ? colorScheme.primary.withValues(alpha: 0.1) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        selected: selected,
        selectedColor: colorScheme.primary,
        leading: Icon(icon),
        title: Text(title),
        onTap: onTap,
      ),
    );
  }
}

/// 蔵タブ: プレビュー＋アイコン・背景画像・ニックネーム・ステメの登録セクション。
class _KuraView extends StatelessWidget {
  const _KuraView({
    required this.user,
    required this.strings,
    required this.vocab,
    required this.uploadingIcon,
    required this.uploadingBackground,
    required this.onAddIcon,
    required this.onDeleteIcon,
    required this.onAddBackground,
    required this.onDeleteBackground,
    required this.onAddNickname,
    required this.onEditNickname,
    required this.onAddStatusMessage,
    required this.onEditStatusMessage,
    required this.onAddSnsLink,
    required this.onEditSnsLink,
  });

  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;
  final bool uploadingIcon;
  final bool uploadingBackground;
  final VoidCallback onAddIcon;
  final ValueChanged<ProfileMaterial> onDeleteIcon;
  final VoidCallback onAddBackground;
  final ValueChanged<ProfileMaterial> onDeleteBackground;
  final VoidCallback onAddNickname;
  final ValueChanged<Nickname> onEditNickname;
  final VoidCallback onAddStatusMessage;
  final ValueChanged<StatusMessage> onEditStatusMessage;
  final VoidCallback onAddSnsLink;
  final ValueChanged<SnsLink> onEditSnsLink;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaterialSection(
          title: strings.profileIconSection,
          count: user.icons.length,
          max: kMaxIcons,
          uploading: uploadingIcon,
          onAdd: onAddIcon,
          children: [
            for (final icon in user.icons)
              _CircleMaterialThumb(
                url: icon.url,
                onDelete: () => onDeleteIcon(icon),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _MaterialSection(
          title: strings.profileBackgroundSection,
          count: user.backgroundImages.length,
          max: kMaxBackgroundImages,
          uploading: uploadingBackground,
          onAdd: onAddBackground,
          children: [
            for (final bg in user.backgroundImages)
              _RectMaterialThumb(
                url: bg.url,
                onDelete: () => onDeleteBackground(bg),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _NicknameSection(
          strings: strings,
          vocab: vocab,
          nicknames: user.nicknames,
          onAdd: onAddNickname,
          onEdit: onEditNickname,
        ),
        const SizedBox(height: 24),
        _StatusMessageSection(
          strings: strings,
          vocab: vocab,
          messages: user.statusMessages,
          onAdd: onAddStatusMessage,
          onEdit: onEditStatusMessage,
        ),
        const SizedBox(height: 24),
        _SnsLinkSection(
          strings: strings,
          links: user.snsLinks,
          onAdd: onAddSnsLink,
          onEdit: onEditSnsLink,
        ),
      ],
    );
  }
}

/// 工房タブ: 蔵の素材を組み合わせた最大[kMaxProfileCards]枚のプロフィールカード。
/// 常に[kMaxProfileCards]枠を表示し、未作成の枠は「+」付きの白紙カードとして
/// 表示する。どの枠をタップしても選択画面（[_ProfileCardEditorDialog]）が開く。
/// 実際のカード数が[kMaxProfileCards]を超えている場合（過去の不具合等による
/// 残留データ）は、超過分を隠さず全て表示する（隠れたまま削除できなくなる
/// ことを防ぐため）。
class _WorkshopView extends StatelessWidget {
  const _WorkshopView({
    required this.user,
    required this.strings,
    required this.vocab,
    required this.onTapSlot,
    required this.onSetActive,
  });

  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;

  /// 枠番号（Heroタグ用）とその枠の現在のカード（未作成ならnull）を渡す。
  final void Function(int index, ProfileCard? card) onTapSlot;

  /// 縁結びの招待リンク等に適用するカードとして選択する（ラジオボタン）。
  final void Function(String cardId) onSetActive;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user.profileCards.isNotEmpty) ...[
          Text(
            '右上の丸いボタンで選んだカードがデフォルトになります。'
            '友達申請や広場参加など、指定していない場面では'
            'デフォルトのカードが使われます',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 以前は固定サイズ（160x200）のカードを画面左端に詰めて表示していたため、
        // 広い画面では余白ばかりが目立っていた。3枠固定という前提を活かし、
        // 画面幅いっぱいを3等分してカード自体を大きく表示する（上限は
        // 超ワイド画面でカードが際限なく巨大化しないための保険程度に留める）。
        // ただしモバイル幅では3等分すると最小幅（160）を下回り、Rowが画面外に
        // はみ出して右端の枠が途切れて見えていた。3等分した幅が最小幅を
        // 下回る場合は1枠ずつ縦に並べ、カード自体を画面幅いっぱいまで
        // 大きく表示する（結果的にズーム編集画面に近い大きさになる）。
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 24.0;
            const minCardWidth = 160.0;
            const maxCardWidth = 640.0;
            // 通常は常に[kMaxProfileCards]枠だが、過去の不具合等で配列が
            // それを超えて残っている場合に超過分を画面から隠してしまうと、
            // ユーザーが気付いて削除する手段が無くなってしまう。表示枠数
            // 自体は実際のカード数に合わせて広げ、全てのカードを必ず
            // 表示・削除できるようにする（新規作成用の白紙枠は
            // [kMaxProfileCards]までしか出さない）。
            final slotCount = max(kMaxProfileCards, user.profileCards.length);
            final rawWidth =
                (constraints.maxWidth - gap * (slotCount - 1)) / slotCount;
            if (rawWidth < minCardWidth) {
              final cardWidth = constraints.maxWidth.clamp(
                minCardWidth,
                maxCardWidth,
              );
              final cardHeight = cardWidth * 1.25;
              return Column(
                children: [
                  for (var i = 0; i < slotCount; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    if (i < user.profileCards.length)
                      _WorkshopCardSlot(
                        index: i,
                        card: user.profileCards[i],
                        user: user,
                        strings: strings,
                        vocab: vocab,
                        width: cardWidth,
                        height: cardHeight,
                        isActive:
                            user.activeProfileCardId == user.profileCards[i].id,
                        onTap: () => onTapSlot(i, user.profileCards[i]),
                        onSetActive: () => onSetActive(user.profileCards[i].id),
                      )
                    else
                      _WorkshopBlankSlot(
                        index: i,
                        width: cardWidth,
                        height: cardHeight,
                        onTap: () => onTapSlot(i, null),
                      ),
                  ],
                ],
              );
            }
            final cardWidth = rawWidth.clamp(minCardWidth, maxCardWidth);
            final cardHeight = cardWidth * 1.25;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              // 作成済みの枠はカード本体の下にカード名を表示する分だけ全体の
              // 高さが白紙の枠（カード本体のみ）より高くなる。Rowの既定
              // （center）のままだと高さが違う枠同士でカード本体の上端が
              // ずれて見えてしまうため、上端をそろえる。
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < slotCount; i++)
                  if (i < user.profileCards.length)
                    _WorkshopCardSlot(
                      index: i,
                      card: user.profileCards[i],
                      user: user,
                      strings: strings,
                      vocab: vocab,
                      width: cardWidth,
                      height: cardHeight,
                      isActive:
                          user.activeProfileCardId == user.profileCards[i].id,
                      onTap: () => onTapSlot(i, user.profileCards[i]),
                      onSetActive: () => onSetActive(user.profileCards[i].id),
                    )
                  else
                    _WorkshopBlankSlot(
                      index: i,
                      width: cardWidth,
                      height: cardHeight,
                      onTap: () => onTapSlot(i, null),
                    ),
              ],
            );
          },
        ),
        const Divider(height: 32),
        _WorkshopConversationCardSection(user: user, strings: strings),
      ],
    );
  }
}

final _dmListProvider = StreamProvider.family<List<DirectMessage>, String>(
  (ref, userId) =>
      ref.watch(directMessageRepositoryProvider).watchDirectMessages(userId),
);

final _groupListProvider = StreamProvider.family<List<Group>, String>(
  (ref, userId) => ref.watch(groupRepositoryProvider).watchGroups(userId),
);

/// 工房内、会話（一対・広場）ごとに使うプロフィールカード
/// （`AppUser.conversationProfileCardId`、2026-07-29追加）の一覧・追加UI。
/// 以前は設定＞語らいにあったが、2026-08-02に工房へ移動した。全ての語らいを
/// 並べると標準カードのままの語らいに埋もれてしまうため、既に個別のカードを
/// 設定した語らいだけを表示する。まだ設定していない語らいに新しく設定したい
/// ときは＋ボタンから対象を選ぶ（[_showAddDialog]）。選んだ後は
/// `ConversationProfileCardDialog`（ハンバーガーメニュー・広場の全体設定と
/// 共通）を再利用してカードを選ばせる。標準に戻す（`ProfileCardPicker`で
/// 「標準」を選ぶ）と、この一覧からは自動的に消える。
class _WorkshopConversationCardSection extends ConsumerWidget {
  const _WorkshopConversationCardSection({
    required this.user,
    required this.strings,
  });

  final AppUser user;
  final Strings strings;

  Future<void> _select(
    WidgetRef ref,
    String conversationId,
    String? profileCardId,
  ) {
    return ref
        .read(userRepositoryProvider)
        .setConversationProfileCard(
          userId: user.userId,
          conversationId: conversationId,
          profileCardId: profileCardId,
        );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    WidgetRef ref,
    List<DirectMessage> unassignedDms,
    List<Group> unassignedGroups,
  ) async {
    if (unassignedDms.isEmpty && unassignedGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.workshopConversationCardAddEmpty)),
      );
      return;
    }

    final selectedIds = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _AddConversationCardDialog(
        userId: user.userId,
        unassignedDms: unassignedDms,
        unassignedGroups: unassignedGroups,
      ),
    );
    if (selectedIds == null || selectedIds.isEmpty || !context.mounted) {
      return;
    }

    if (selectedIds.length == 1) {
      await ConversationProfileCardDialog.show(
        context,
        currentUserId: user.userId,
        conversationId: selectedIds.first,
      );
      return;
    }

    // 複数選択時は、既存の1件専用ConversationProfileCardDialogでは対応
    // できないため、ProfileCardPickerだけを載せた軽量ダイアログでカードを
    // 1つ選ばせ、選んだ全ての会話へ一括適用する（2026-08-05追加）。
    final cardId = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.conversationProfileCardMenuLabel),
        content: ProfileCardPicker(
          strings: strings,
          cards: user.profileCards,
          selectedCardId: null,
          activeCardName: user.activeProfileCard?.name,
          onSelected: (id) => Navigator.of(context).pop(id),
        ),
      ),
    );
    if (!context.mounted) return;
    await Future.wait([for (final id in selectedIds) _select(ref, id, cardId)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dms = ref.watch(_dmListProvider(user.userId)).value;
    final groups = ref.watch(_groupListProvider(user.userId)).value;

    if (dms == null || groups == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final assignedDms = dms
        .where((dm) => user.conversationProfileCardId[dm.dmId] != null)
        .toList();
    final assignedGroups = groups
        .where((group) => user.conversationProfileCardId[group.groupId] != null)
        .toList();
    final unassignedDms = dms
        .where((dm) => user.conversationProfileCardId[dm.dmId] == null)
        .toList();
    final unassignedGroups = groups
        .where((group) => user.conversationProfileCardId[group.groupId] == null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GekigaSectionHeader(strings.settingsProfileCardAssignmentTitle),
            const SizedBox(width: 4),
            ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
                ? GekigaIconButton(
                    icon: Icons.add,
                    size: 40,
                    tooltip: strings.workshopConversationCardAddTooltip,
                    onPressed: () => _showAddDialog(
                      context,
                      ref,
                      unassignedDms,
                      unassignedGroups,
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: strings.workshopConversationCardAddTooltip,
                    onPressed: () => _showAddDialog(
                      context,
                      ref,
                      unassignedDms,
                      unassignedGroups,
                    ),
                  ),
          ],
        ),
        Text(
          strings.settingsProfileCardAssignmentHint,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (assignedDms.isEmpty && assignedGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              strings.settingsProfileCardAssignmentEmpty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          for (final dm in assignedDms)
            _ProfileCardAssignmentRow(
              strings: strings,
              title: '@${dm.otherRhingId(user.userId)}',
              cards: user.profileCards,
              selectedCardId: user.conversationProfileCardId[dm.dmId],
              activeCardName: user.activeProfileCard?.name,
              onSelected: (id) => _select(ref, dm.dmId, id),
            ),
          for (final group in assignedGroups)
            _ProfileCardAssignmentRow(
              strings: strings,
              title: group.name,
              cards: user.profileCards,
              selectedCardId: user.conversationProfileCardId[group.groupId],
              activeCardName: user.activeProfileCard?.name,
              onSelected: (id) => _select(ref, group.groupId, id),
            ),
        ],
      ],
    );
  }
}

/// [_WorkshopConversationCardSection]の「＋」から開く追加先選択ポップアップ。
/// チェックボックスで一対・広場を複数選択できる（2026-08-05変更。以前は
/// `SimpleDialog`のテキストのみの単一選択で、一対はRhing IDそのまま表示
/// だった）。一対の行は呼び名（無ければ@Rhing ID、`talks_tab.dart`の
/// `_buildDmDetailWithRooms`と同じフォールバック順序）、広場の行は
/// `Group.profileCard`のアイコンをそれぞれ左端に表示する。
class _AddConversationCardDialog extends ConsumerStatefulWidget {
  const _AddConversationCardDialog({
    required this.userId,
    required this.unassignedDms,
    required this.unassignedGroups,
  });

  final String userId;
  final List<DirectMessage> unassignedDms;
  final List<Group> unassignedGroups;

  @override
  ConsumerState<_AddConversationCardDialog> createState() =>
      _AddConversationCardDialogState();
}

class _AddConversationCardDialogState
    extends ConsumerState<_AddConversationCardDialog> {
  final _selectedIds = <String>{};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _dmTitle(DirectMessage dm) {
    final otherUserId = dm.otherUserId(widget.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final nickname = otherUser?.effectiveNicknameFor(dm.dmId)?.text;
    return (nickname != null && nickname.isNotEmpty)
        ? nickname
        : '@${dm.otherRhingId(widget.userId)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final query = _searchController.text.trim().toLowerCase();
    final filteredDms = widget.unassignedDms
        .where(
          (dm) => query.isEmpty || _dmTitle(dm).toLowerCase().contains(query),
        )
        .toList();
    final filteredGroups = widget.unassignedGroups
        .where((g) => query.isEmpty || g.name.toLowerCase().contains(query))
        .toList();

    return AlertDialog(
      title: Text(strings.workshopConversationCardAddDialogTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.workshopConversationCardSearchHint,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_searchController.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final dm in filteredDms) _buildDmTile(dm),
                  for (final group in filteredGroups) _buildGroupTile(group),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedIds),
          child: Text(strings.add),
        ),
      ],
    );
  }

  Widget _buildDmTile(DirectMessage dm) {
    final title = _dmTitle(dm);
    final otherUserId = dm.otherUserId(widget.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final iconUrl = otherUser?.effectiveIconFor(dm.dmId)?.url;
    return CheckboxListTile(
      value: _selectedIds.contains(dm.dmId),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        child: iconUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(
        truncateName(title, 8),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (checked) => setState(() {
        if (checked ?? false) {
          _selectedIds.add(dm.dmId);
        } else {
          _selectedIds.remove(dm.dmId);
        }
      }),
    );
  }

  Widget _buildGroupTile(Group group) {
    final iconUrl = group.profileCard?.iconUrl;
    return CheckboxListTile(
      value: _selectedIds.contains(group.groupId),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        child: iconUrl == null ? const Icon(Icons.groups) : null,
      ),
      title: Text(
        truncateName(group.name, 8),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (checked) => setState(() {
        if (checked ?? false) {
          _selectedIds.add(group.groupId);
        } else {
          _selectedIds.remove(group.groupId);
        }
      }),
    );
  }
}

class _ProfileCardAssignmentRow extends StatelessWidget {
  const _ProfileCardAssignmentRow({
    required this.strings,
    required this.title,
    required this.cards,
    required this.selectedCardId,
    required this.activeCardName,
    required this.onSelected,
  });

  final Strings strings;
  final String title;
  final List<ProfileCard> cards;
  final String? selectedCardId;
  final String? activeCardName;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            truncateName(title, 8),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ProfileCardPicker(
            strings: strings,
            cards: cards,
            selectedCardId: selectedCardId,
            activeCardName: activeCardName,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

class _WorkshopBlankSlot extends StatelessWidget {
  const _WorkshopBlankSlot({
    required this.index,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final int index;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Hero(
        tag: 'profile-card-slot-$index',
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: (width * 0.2).clamp(32.0, 64.0),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkshopCardSlot extends StatelessWidget {
  const _WorkshopCardSlot({
    required this.index,
    required this.card,
    required this.user,
    required this.strings,
    required this.vocab,
    required this.width,
    required this.height,
    required this.isActive,
    required this.onTap,
    required this.onSetActive,
  });

  final int index;
  final ProfileCard card;
  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;
  final double width;
  final double height;

  /// このカードが縁結びの招待リンク等に適用中かどうか。
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onSetActive;

  @override
  Widget build(BuildContext context) {
    final icon = _findById(user.icons, card.iconId);
    final background = _findById(user.backgroundImages, card.backgroundImageId);
    final nickname = _findById(user.nicknames, card.nicknameId)?.text;
    final statusMessage = _findById(
      user.statusMessages,
      card.statusMessageId,
    )?.text;
    final selectedSnsLinks = _selectedSnsLinksFor(user, card.snsLinkIds);

    // 右上バッジの位置合わせにだけ使う（他のサイズ計算はProfileCardView内で
    // 行う。ズーム編集画面[_CardZoomEditor]と全く同じ比率）。
    final padding = (width * 0.08).clamp(12.0, 32.0);
    // ズーム編集画面のカード名表示と同じ比率（幅の6%）で揃える。
    final nameFontSize = (width * 0.06).clamp(16.0, 22.0);

    // カード名がズーム時に取り残されて見えないよう、カード本体とカード名を
    // まとめて1つのHeroにし、一緒に移動・拡大するモーションにする
    // （削除ボタンだけはズーム編集画面側の[Stack]で外側に置き、Heroには含めない）。
    return Hero(
      tag: 'profile-card-slot-$index',
      // Hero飛行中はこのchild（FittedBox以下）がOverlay直下へ一時的に
      // 付け替えられ、外側のScaffold等が持つMaterial祖先から切り離される。
      // 中の`InkWell`がMaterial祖先を必要とするため、飛行中も自前で
      // Material祖先を持たせておく（[_CardZoomEditor]のHeroで同じ理由から
      // 既に対応済みだったが、こちら側は対応漏れがあり、カードをタップして
      // 開く/閉じる瞬間に「No Material widget found」が出ていた。2026-08-05
      // 修正）。
      //
      // Hero飛行はMaterialRectArcTweenで両端の矩形を対角の2頂点それぞれ独立の
      // 円弧で補間するため、飛行の途中で矩形の幅・高さが始点・終点どちらより
      // 一瞬小さくなることがある（単純な直線補間ではない）。カード＋カード名の
      // 固定サイズレイアウトはその一瞬だけ収まりきらずオーバーフロー警告が
      // 出ていた。ClipRectは「はみ出た描画を切り取る」だけでRenderFlex自体が
      // 出す「BOTTOM OVERFLOWED」の警告バナーは吸収できないため
      // （[_CardZoomEditor]側と同じ理由）、オーバーフローそのものが起きない
      // FittedBoxに変更した。
      child: Material(
        type: MaterialType.transparency,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onTap,
                      child: ProfileCardView(
                        width: width,
                        height: height,
                        icon: icon,
                        background: background,
                        nickname: nickname ?? vocab.nickname,
                        statusMessage: statusMessage ?? vocab.statusMessage,
                        snsLinks: selectedSnsLinks,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    Positioned(
                      top: padding * 0.4,
                      right: padding * 0.4,
                      child: _ActiveCardBadge(
                        isActive: isActive,
                        onTap: onSetActive,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: width,
                child: Text(
                  card.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: nameFontSize,
                    // 以前は黒固定にしていたが、ダークモードで見えなくなって
                    // いた（2026-07-29修正）。色指定なし（テーマの既定色任せ）
                    // に戻すとHero飛行中に既定色の解決結果がずれる問題が
                    // あったため、Theme.of(context)で明示的にライト/ダーク
                    // 双方に追従する色を計算する（ズームイン編集画面側の
                    // TextFieldと同じ理由・同じ対応）。
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// カード名・ニックネーム・ステメなど、`id`フィールドを持つ蔵の素材から
/// idで1件だけ検索する（[_WorkshopCardSlot]・[_CardZoomEditor]で共用）。
T? _findById<T>(List<T> items, String? id) {
  if (id == null) return null;
  for (final item in items) {
    final dynamic d = item;
    if (d.id == id) return item;
  }
  return null;
}

/// カードに掲載するSNSのURL（[ProfileCard.snsLinkIds]）を、蔵の[SnsLink]一覧から
/// 解決する（[_WorkshopCardSlot]・[_CardZoomEditor]で共用）。
List<SnsLink> _selectedSnsLinksFor(AppUser user, List<String> snsLinkIds) => [
  for (final link in user.snsLinks)
    if (snsLinkIds.contains(link.id)) link,
];

/// アイコン・背景画像それぞれの蔵セクション（見出し＋件数＋サムネ一覧＋追加ボタン）。
class _MaterialSection extends StatelessWidget {
  const _MaterialSection({
    required this.title,
    required this.count,
    required this.max,
    required this.uploading,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final int count;
  final int max;
  final bool uploading;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 上限まで登録済みなら、これ以上追加できないことが一目でわかるよう
    // 追加ボタン自体を非表示にする（無効化して残すだけだと分かりにくいため）。
    final showAddButton = count < max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GekigaSectionHeader('$title（$count/$max）'),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...children.map(
                (child) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: child,
                ),
              ),
              if (showAddButton)
                Center(
                  child: _AddThumbButton(
                    enabled: !uploading,
                    loading: uploading,
                    onTap: onAdd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddThumbButton extends ConsumerWidget {
  const _AddThumbButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      // 40px: サムネイル（72px）と同じ大きさだと目立ちすぎるとの指摘を受け、
      // 縮小した（2026-08-05変更、以前は72）。
      if (loading) {
        return const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: GekigaColors.onPanel,
              ),
            ),
          ),
        );
      }
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: GekigaIconButton(icon: Icons.add, size: 40, onPressed: onTap),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.add,
                    color: enabled
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
          ),
        ),
      ),
    );
  }
}

/// アップロード直後の画像がまだCDNに伝播していない、あるいは
/// ブラウザがデコードできない形式（HEICなど）だった場合に、
/// 何も表示されない「真っ白」な状態のまま気づけないことがあったため、
/// 読み込み中はスピナー、失敗時は壊れた画像アイコンを明示的に表示する。
class _NetworkThumbImage extends StatelessWidget {
  const _NetworkThumbImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CircleMaterialThumb extends StatelessWidget {
  const _CircleMaterialThumb({required this.url, required this.onDelete});

  final String url;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: ClipOval(child: _NetworkThumbImage(url: url)),
        ),
        Positioned(right: -4, top: -4, child: _DeleteBadge(onTap: onDelete)),
      ],
    );
  }
}

class _RectMaterialThumb extends StatelessWidget {
  const _RectMaterialThumb({required this.url, required this.onDelete});

  final String url;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 128,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _NetworkThumbImage(url: url),
          ),
        ),
        Positioned(right: -4, top: -4, child: _DeleteBadge(onTap: onDelete)),
      ],
    );
  }
}

/// 工房カードの右上に置く、縁結びの招待リンク等に適用するカードを選ぶための
/// ラジオボタン風バッジ。[_DeleteBadge]と同じ円形オーバーレイの見た目に揃える。
class _ActiveCardBadge extends StatelessWidget {
  const _ActiveCardBadge({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isActive
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  const _DeleteBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

/// 呼び名/一言/SNSリンクの登録済み一覧＋（上限未満なら）追加ボタンを、
/// 劇画スタイルならジグザグ枠のブロックで、そうでなければ従来のプレーンな
/// 行/`TextButton.icon`で描画する共通処理（2026-08-04追加、3セクションで
/// 完全に同じ構造だったため切り出した）。一覧行同士は隣接接合するが、
/// 追加ボタンは一覧行とは別の単体ジグザグ枠として、少し間隔を空けて置く。
Widget _registeredItemsSection<T>({
  required WidgetRef ref,
  required List<T> items,
  required String Function(T) idOf,
  required String Function(T) textOf,
  required ValueChanged<T> onEdit,
  required bool canAdd,
  required VoidCallback onAdd,
  required String addLabel,
}) {
  if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          GekigaJointedTileList(
            seeds: [for (final item in items) idOf(item).hashCode],
            selectedFlags: [for (final _ in items) false],
            children: [
              for (final item in items)
                _RegisteredItemRow(
                  text: textOf(item),
                  onEdit: () => onEdit(item),
                ),
            ],
          ),
        if (canAdd) ...[
          const SizedBox(height: 8),
          GekigaJointedTileList(
            seeds: [addLabel.hashCode],
            selectedFlags: const [true],
            children: [
              GekigaButton(label: addLabel, icon: Icons.add, onPressed: onAdd),
            ],
          ),
        ],
      ],
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in items)
        _RegisteredItemRow(text: textOf(item), onEdit: () => onEdit(item)),
      if (canAdd)
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
    ],
  );
}

class _StatusMessageSection extends ConsumerWidget {
  const _StatusMessageSection({
    required this.strings,
    required this.vocab,
    required this.messages,
    required this.onAdd,
    required this.onEdit,
  });

  final Strings strings;
  final Vocabulary vocab;
  final List<StatusMessage> messages;
  final VoidCallback onAdd;
  final ValueChanged<StatusMessage> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GekigaSectionHeader(
          '${vocab.statusMessage}（${messages.length}/$kMaxStatusMessages）',
        ),
        const SizedBox(height: 4),
        _registeredItemsSection(
          ref: ref,
          items: messages,
          idOf: (m) => m.id,
          textOf: (m) => m.text,
          onEdit: onEdit,
          canAdd: messages.length < kMaxStatusMessages,
          onAdd: onAdd,
          addLabel: strings.profileAddStatusMessage(vocab.statusMessage),
        ),
      ],
    );
  }
}

class _NicknameSection extends ConsumerWidget {
  const _NicknameSection({
    required this.strings,
    required this.vocab,
    required this.nicknames,
    required this.onAdd,
    required this.onEdit,
  });

  final Strings strings;
  final Vocabulary vocab;
  final List<Nickname> nicknames;
  final VoidCallback onAdd;
  final ValueChanged<Nickname> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GekigaSectionHeader(
          '${vocab.nickname}（${nicknames.length}/$kMaxNicknames）',
        ),
        Text(
          strings.profileNicknameHint(vocab.nickname),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        _registeredItemsSection(
          ref: ref,
          items: nicknames,
          idOf: (n) => n.id,
          textOf: (n) => n.text,
          onEdit: onEdit,
          canAdd: nicknames.length < kMaxNicknames,
          onAdd: onAdd,
          addLabel: strings.profileAddNickname(vocab.nickname),
        ),
      ],
    );
  }
}

/// 蔵に登録する他のSNSのURL。最大[kMaxSnsLinks]件まで登録でき、そのうち
/// 工房のプロフィールカードに掲載できるのは最大[kMaxProfileCardSnsLinks]件
/// （カード側の選択は`_CardZoomEditor._pickSnsLinks`で行う）。
class _SnsLinkSection extends ConsumerWidget {
  const _SnsLinkSection({
    required this.strings,
    required this.links,
    required this.onAdd,
    required this.onEdit,
  });

  final Strings strings;
  final List<SnsLink> links;
  final VoidCallback onAdd;
  final ValueChanged<SnsLink> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GekigaSectionHeader(
          '${strings.profileSnsLinkSectionTitle}（${links.length}/$kMaxSnsLinks）',
        ),
        const SizedBox(height: 4),
        _registeredItemsSection(
          ref: ref,
          items: links,
          idOf: (l) => l.id,
          textOf: (l) => l.url,
          onEdit: onEdit,
          canAdd: links.length < kMaxSnsLinks,
          onAdd: onAdd,
          addLabel: strings.profileAddSnsLink,
        ),
      ],
    );
  }
}

/// ニックネーム・ステメの1行。テキスト部分をタップすると編集ポップアップ
/// （[_NicknameDialog]/[_StatusMessageDialog]）が開き、編集・削除の両方を
/// そこで行う。「使うものを選ぶ」機能は蔵では不要なため持たない
/// （表示にどれを使うかは登録順で自動的に決まる）。
class _RegisteredItemRow extends ConsumerWidget {
  const _RegisteredItemRow({required this.text, required this.onEdit});

  final String text;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return GekigaTileContent(
        leading: const Icon(Icons.edit_outlined),
        title: Text(text, overflow: TextOverflow.ellipsis),
        onTap: onEdit,
      );
    }
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// ニックネーム／ステメ編集ポップアップの結果。テキストの確定（[save]）と
/// 削除（[delete]）の両方を、ポップアップの中の完了・削除ボタンだけで
/// 完結させるため、単なる`String?`ではなくどちらの操作だったかを区別する。
class _EditResult {
  const _EditResult._({this.text, required this.isDelete});
  const _EditResult.save(String text) : this._(text: text, isDelete: false);
  const _EditResult.delete() : this._(isDelete: true);

  final String? text;
  final bool isDelete;
}

/// ニックネーム/ステメ/SNSリンクの各編集ダイアログで共通の、削除・保存
/// ボタンの行。劇画スタイルなら[GekigaButton]（単体ジグザグ枠）、
/// そうでなければ通常の[OutlinedButton]/[FilledButton]にする
/// （2026-08-04追加、3ダイアログで完全に同じ構造だったため切り出した）。
class _DialogActionRow extends ConsumerWidget {
  const _DialogActionRow({
    required this.showDelete,
    required this.onDelete,
    required this.onSubmit,
    required this.submitLabel,
    required this.deleteLabel,
  });

  final bool showDelete;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;
  final String submitLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showDelete) ...[
          isGekiga
              ? GekigaJointedTileList(
                  seeds: [deleteLabel.hashCode],
                  selectedFlags: const [false],
                  children: [
                    GekigaButton(
                      label: deleteLabel,
                      selected: false,
                      onPressed: onDelete,
                    ),
                  ],
                )
              : OutlinedButton(onPressed: onDelete, child: Text(deleteLabel)),
          const SizedBox(width: 8),
        ],
        isGekiga
            ? GekigaJointedTileList(
                seeds: [submitLabel.hashCode],
                selectedFlags: const [true],
                children: [
                  GekigaButton(label: submitLabel, onPressed: onSubmit),
                ],
              )
            : FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
      ],
    );
  }
}

class _NicknameDialog extends ConsumerStatefulWidget {
  const _NicknameDialog({this.initialText});

  /// 編集時は既存のテキストを渡す。nullなら新規追加。
  final String? initialText;

  @override
  ConsumerState<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends ConsumerState<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _errorText;

  bool get _isEdit => widget.initialText != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 未入力のまま完了ボタンを押しても、以前は何も起きたように見えなかった
  // （呼び出し元が空文字を無言でreturnしていたため）。押した結果が必ず
  // 見えるよう、ここでエラー表示してから閉じないようにする。
  void _submit() {
    if (_controller.text.trim().isEmpty) {
      setState(
        () => _errorText = ref.read(appStringsProvider).fieldRequiredError,
      );
      return;
    }
    Navigator.of(context).pop(_EditResult.save(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    return AlertDialog(
      title: Text(
        _isEdit
            ? strings.profileNicknameDialogEditTitle(vocab.nickname)
            : strings.profileNicknameDialogTitle(vocab.nickname),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kMaxNicknameLength,
            decoration: InputDecoration(
              hintText: strings.profileNicknameDialogHint(vocab.nickname),
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(),
          ),
          _DialogActionRow(
            showDelete: _isEdit,
            onDelete: () =>
                Navigator.of(context).pop(const _EditResult.delete()),
            onSubmit: _submit,
            submitLabel: _isEdit ? strings.done : strings.add,
            deleteLabel: strings.delete,
          ),
        ],
      ),
    );
  }
}

class _StatusMessageDialog extends ConsumerStatefulWidget {
  const _StatusMessageDialog({this.initialText});

  /// 編集時は既存のテキストを渡す。nullなら新規追加。
  final String? initialText;

  @override
  ConsumerState<_StatusMessageDialog> createState() =>
      _StatusMessageDialogState();
}

class _StatusMessageDialogState extends ConsumerState<_StatusMessageDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _errorText;

  bool get _isEdit => widget.initialText != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) {
      setState(
        () => _errorText = ref.read(appStringsProvider).fieldRequiredError,
      );
      return;
    }
    Navigator.of(context).pop(_EditResult.save(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    return AlertDialog(
      title: Text(
        _isEdit
            ? strings.profileStatusMessageDialogEditTitle(vocab.statusMessage)
            : strings.profileStatusMessageDialogTitle(vocab.statusMessage),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kMaxStatusMessageLength,
            decoration: InputDecoration(
              hintText: strings.profileStatusMessageDialogHint(
                vocab.statusMessage,
              ),
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(),
          ),
          _DialogActionRow(
            showDelete: _isEdit,
            onDelete: () =>
                Navigator.of(context).pop(const _EditResult.delete()),
            onSubmit: _submit,
            submitLabel: _isEdit ? strings.done : strings.add,
            deleteLabel: strings.delete,
          ),
        ],
      ),
    );
  }
}

/// URLの形式チェック。schemeとhostの両方を備えたURLのみ有効とする。
bool _isValidUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}

class _SnsLinkDialog extends ConsumerStatefulWidget {
  const _SnsLinkDialog({this.initialText});

  /// 編集時は既存のURLを渡す。nullなら新規追加。
  final String? initialText;

  @override
  ConsumerState<_SnsLinkDialog> createState() => _SnsLinkDialogState();
}

class _SnsLinkDialogState extends ConsumerState<_SnsLinkDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _errorText;

  bool get _isEdit => widget.initialText != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final strings = ref.read(appStringsProvider);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = strings.fieldRequiredError);
      return;
    }
    if (!_isValidUrl(text)) {
      setState(() => _errorText = strings.profileSnsLinkInvalidError);
      return;
    }
    Navigator.of(context).pop(_EditResult.save(text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(
        _isEdit
            ? strings.profileSnsLinkDialogEditTitle
            : strings.profileSnsLinkDialogTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: strings.profileSnsLinkDialogHint,
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(),
          ),
          _DialogActionRow(
            showDelete: _isEdit,
            onDelete: () =>
                Navigator.of(context).pop(const _EditResult.delete()),
            onSubmit: _submit,
            submitLabel: _isEdit ? strings.done : strings.add,
            deleteLabel: strings.delete,
          ),
        ],
      ),
    );
  }
}

/// 工房: プロフィールカードの編集画面。カードそのものをズームインした形で表示し、
/// カード上の各素材（背景画像・アイコン・ニックネーム・ステメ）を直接タップすると、
/// その種類だけの登録済み素材一覧がポップアップし、選ぶとその場で即時保存される。
/// カード名だけは自由入力のためポップの対象外（編集アイコンから編集する）。
class _CardZoomEditor extends StatefulWidget {
  const _CardZoomEditor({
    required this.heroTag,
    required this.user,
    required this.strings,
    required this.vocab,
    required this.initialCard,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });

  final String heroTag;
  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;

  /// nullなら空き枠（まだFirestoreに存在しないカード）。
  final ProfileCard? initialCard;

  /// 新規カードで名前・素材のいずれかを初めて変更した時点で1回だけ呼ばれる
  /// （名前を確定する前でも素材を選べるため、どちらが先になるかは決まっていない）。
  final Future<void> Function(ProfileCard card) onCreate;

  /// 既存カードのフィールドを1つ変更するたびに呼ばれる。
  final Future<void> Function(ProfileCard card) onUpdate;
  final Future<void> Function(ProfileCard card) onDelete;

  @override
  State<_CardZoomEditor> createState() => _CardZoomEditorState();
}

class _CardZoomEditorState extends State<_CardZoomEditor> {
  // 名前を確定するまで素材（アイコン・背景・ニックネーム・ステメ）を
  // 選べないと、初めて使う人が「まず名前を決めないと何も触れない」と
  // 戸惑うため、空き枠でも最初からローカルの下書きカードを持たせ、
  // 名前確定前から全項目を編集可能にする。Firestoreへの実際の保存
  // （[widget.onCreate]の呼び出し）は、名前・素材のいずれかを初めて
  // 変更したタイミングまで遅らせる（[_persisted]で管理）。
  late ProfileCard _card;
  bool _persisted = false;

  // 更新の保存（[widget.onUpdate]）は「古い値をarrayRemoveで消す→新しい値を
  // arrayUnionで足す」という2手順で、この2手順セット自体はFirestore側で
  // 原子的にまとまっていない。[_persist]を待たずに連続で呼ぶと（例:
  // カードに載せるURLのチェックボックスを立て続けに2つチェックした場合）、
  // 後発の呼び出しのarrayRemoveが「先発の呼び出しのarrayUnionがまだ反映されて
  // いない古い値」を狙ってしまい何もマッチせず素通りし、結果として先発の
  // 中間状態と後発の最終状態の両方がprofileCards配列に残ってしまう
  // （ページをリロードしても消えない、本物のデータ重複）不具合があった。
  // [_persist]呼び出しをこのFutureチェーンで直列化し、常に前回の保存が
  // 完全に完了してから次を始めるようにして解消する。
  Future<void> _pendingPersist = Future<void>.value();
  late final TextEditingController _nameController;
  // 新規カードは開いた瞬間から名前を入力してほしいのでキーボードを出す。
  // 既存カードは開くたびに勝手にキーボードが出ると煩わしいので出さない。
  late final bool _isNewCard;
  Offset? _lastTapPosition;

  @override
  void initState() {
    super.initState();
    final existing = widget.initialCard;
    _card = existing ?? ProfileCard(id: _newLocalId(), name: '');
    _persisted = existing != null;
    _nameController = TextEditingController(text: existing?.name);
    _isNewCard = existing == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// まだ一度もFirestoreに保存していなければ[widget.onCreate]で新規作成、
  /// 既に保存済みなら[widget.onUpdate]でフィールド更新する。
  /// 直前の保存が完了するまで待ってから実行する（[_pendingPersist]参照）。
  Future<void> _persist() {
    final card = _card;
    final next = _pendingPersist.then((_) async {
      if (_persisted) {
        await widget.onUpdate(card);
      } else {
        _persisted = true;
        await widget.onCreate(card);
      }
    });
    _pendingPersist = next;
    return next;
  }

  Future<void> _confirmName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name == _card.name) return;

    setState(() {
      _card = _card.copyWith(name: name);
    });
    await _persist();
  }

  Future<void> _pickMaterial(String field) async {
    final card = _card;

    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final tapPosition = _lastTapPosition ?? overlayBox.size.center(Offset.zero);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(tapPosition, tapPosition),
      Offset.zero & overlayBox.size,
    );
    final strings = widget.strings;

    String? result;
    switch (field) {
      case 'icon':
        result = await _showImageMaterialMenu(
          context,
          position,
          widget.user.icons,
          card.iconId,
          strings,
        );
      case 'background':
        result = await _showImageMaterialMenu(
          context,
          position,
          widget.user.backgroundImages,
          card.backgroundImageId,
          strings,
        );
      case 'nickname':
        result = await _showTextMaterialMenu(
          context,
          position,
          [for (final n in widget.user.nicknames) (n.id, n.text)],
          card.nicknameId,
          strings,
        );
      case 'statusMessage':
        result = await _showTextMaterialMenu(
          context,
          position,
          [for (final m in widget.user.statusMessages) (m.id, m.text)],
          card.statusMessageId,
          strings,
        );
    }
    if (result == null || !mounted) return;

    final id = result.isEmpty ? null : result;
    final updated = switch (field) {
      'icon' => card.copyWith(iconId: id, clearIconId: id == null),
      'background' => card.copyWith(
        backgroundImageId: id,
        clearBackgroundImageId: id == null,
      ),
      'nickname' => card.copyWith(nicknameId: id, clearNicknameId: id == null),
      _ => card.copyWith(statusMessageId: id, clearStatusMessageId: id == null),
    };
    setState(() => _card = updated);
    await _persist();
  }

  /// カードに掲載するSNSのURLを選ぶ。アイコン・ニックネーム等（[_pickMaterial]、
  /// showMenuベースの単一選択）と同じくタップ位置にポップアップを出すが、
  /// こちらは最大[kMaxProfileCardSnsLinks]件までのチェックボックス選択のため、
  /// 1件選ぶたびに閉じさせず、外側タップで閉じるまで複数選べるようにする。
  Future<void> _pickSnsLinks() async {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final tapPosition = _lastTapPosition ?? overlayBox.size.center(Offset.zero);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(tapPosition, tapPosition),
      Offset.zero & overlayBox.size,
    );
    final strings = widget.strings;
    final selected = List<String>.of(_card.snsLinkIds);

    await showMenu<void>(
      context: context,
      position: position,
      items: [
        if (widget.user.snsLinks.isEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: Text(strings.workshopEmptyMaterialHint),
          ),
        for (final link in widget.user.snsLinks)
          PopupMenuItem<void>(
            child: StatefulBuilder(
              builder: (context, setMenuState) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(link.id),
                title: Text(
                  displaySnsLinkUrl(link.url),
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (checked) {
                  setMenuState(() {
                    if (checked ?? false) {
                      if (selected.length < kMaxProfileCardSnsLinks) {
                        selected.add(link.id);
                      }
                    } else {
                      selected.remove(link.id);
                    }
                  });
                  setState(
                    () => _card = _card.copyWith(snsLinkIds: List.of(selected)),
                  );
                  _persist();
                },
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleDelete() async {
    if (_persisted) await widget.onDelete(_card);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(240.0, 420.0);
    final height = width * 1.25;
    final strings = widget.strings;
    final vocab = widget.vocab;
    final card = _card;
    final colorScheme = Theme.of(context).colorScheme;

    final icon = _findById(widget.user.icons, card.iconId);
    final background = _findById(
      widget.user.backgroundImages,
      card.backgroundImageId,
    );
    final nickname = _findById(widget.user.nicknames, card.nicknameId);
    final statusMessage = _findById(
      widget.user.statusMessages,
      card.statusMessageId,
    );
    final selectedSnsLinks = _selectedSnsLinksFor(widget.user, card.snsLinkIds);
    // ニックネーム・ステメはカード内（背景画像や暗いオーバーレイの上）に
    // 表示するため、背景の有無で見やすい色を切り替える。カード名はカードの
    // 外（下、暗転した背景の上）に表示するため常に白系の固定色にする。
    final nicknameColor = background != null ? Colors.white : null;
    final statusColor = background != null
        ? Colors.white70
        : colorScheme.onSurfaceVariant;
    // カード内のニックネーム（width*0.075）に近い比率で、カードの主見出しとして
    // 十分読める大きさにする（以前の「既定サイズの8割」だと逆に小さすぎた）。
    final nameFontSize = (width * 0.06).clamp(16.0, 22.0);

    // カード名がズーム中も取り残されず一緒に移動して見えるよう、カード本体と
    // カード名（下の[SizedBox]）をまとめて1つのHeroにする
    // （[_WorkshopCardSlot]側も同じtagで同じ構成にしてある）。削除ボタンだけは
    // Heroの外側の[Stack]に置き、始点/終点でツリーが変わらないようにする。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Hero(
          tag: widget.heroTag,
          // Hero飛行中はこのchild（Column以下）がOverlay直下へ一時的に
          // 付け替えられ、外側の`_openCardZoom`で用意したMaterial祖先から
          // 切り離される。中のTextFieldがMaterial祖先を必要とするため、
          // 飛行中も自前でMaterial祖先を持たせておく（"No Material widget
          // found"が一瞬だけ出ていた不具合の原因）。
          // また、Hero飛行はMaterialRectArcTweenで対角2頂点をそれぞれ独立の
          // 円弧で補間するため、矩形の幅・高さが始点・終点どちらより一瞬
          // 小さくなることがある（単純な直線補間ではない）。カード＋名前欄の
          // 固定サイズレイアウトはその一瞬だけ収まりきらずオーバーフロー警告が
          // 出ていたため、ClipRectで見た目上だけ吸収する。
          child: Material(
            type: MaterialType.transparency,
            // 以前はClipRectで視覚的にオーバーフローを吸収していたが、
            // ClipRectは「はみ出た描画を切り取る」だけで、RenderFlex自体が
            // 出す「BOTTOM OVERFLOWED」の警告バナーは吸収できず、Hero飛行が
            // 一瞬小さいサイズを取った際に警告が出てしまっていた
            // （カードを閉じる時にエラーが出る不具合として報告された）。
            // FittedBoxならオーバーフローそのものが起きないため、こちらに変更。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(24),
                    color: colorScheme.surfaceContainerHighest,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            // 背景レイヤーはStack(fit: expand)でカード全面を覆っており、
                            // アイコン・ニックネーム・ステメの各タップ領域以外（＝
                            // カードの何も無い箇所）はすべてここに落ちてくる。
                            // behavior: opaqueで、子（ColoredBox等）の描画内容に
                            // 関わらず領域全体を確実にタップ可能にする。
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) =>
                                _lastTapPosition = details.globalPosition,
                            onTap: () => _pickMaterial('background'),
                            child: background != null
                                ? Image.network(
                                    background.url,
                                    fit: BoxFit.cover,
                                  )
                                : ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                  ),
                          ),
                          if (background != null)
                            // 単なる装飾のグラデーションのはずが、子を持たない
                            // DecoratedBoxが背景タップより上のStack層で
                            // ヒットテストを奪ってしまい、背景を一度設定すると
                            // 以降タップしても何も起きない不具合になっていた
                            // （ウィジェットテストで再現・特定）。IgnorePointerで
                            // ヒットテストの対象から明示的に外す。
                            const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black54,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: EdgeInsets.all(width * 0.08),
                            // アイコン・ニックネーム・ステメ・URLの4行を常に
                            // 収めるため、内容をFittedBoxで包み必要なら縮小する。
                            // Hero飛行中は矩形が対角2頂点それぞれ独立の円弧で
                            // 補間されるため、一瞬だけ両端点より小さいサイズを
                            // 取ることがあり、固定サイズのColumnのままだと
                            // その瞬間だけ収まりきらずオーバーフロー警告が出ていた
                            // （4行目のURL行追加でこの問題が顕在化した）。
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTapDown: (details) => _lastTapPosition =
                                        details.globalPosition,
                                    onTap: () => _pickMaterial('icon'),
                                    child: CircleAvatar(
                                      radius: width * 0.13,
                                      backgroundImage: icon != null
                                          ? NetworkImage(icon.url)
                                          : null,
                                      child: icon == null
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                  ),
                                  SizedBox(height: width * 0.05),
                                  // カード内はニックネームを主役として表示し、
                                  // その下にステメを補足として表示する。
                                  GestureDetector(
                                    onTapDown: (details) => _lastTapPosition =
                                        details.globalPosition,
                                    onTap: () => _pickMaterial('nickname'),
                                    child: Text(
                                      nickname?.text ?? vocab.nickname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: width * 0.075,
                                        fontWeight: FontWeight.bold,
                                        color: nicknameColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: width * 0.02),
                                  GestureDetector(
                                    onTapDown: (details) => _lastTapPosition =
                                        details.globalPosition,
                                    onTap: () => _pickMaterial('statusMessage'),
                                    child: Text(
                                      statusMessage?.text ??
                                          vocab.statusMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: width * 0.045,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: width * 0.02),
                                  SnsLinksInline(
                                    links: selectedSnsLinks,
                                    iconSize: width * 0.045,
                                    fontSize: width * 0.04,
                                    color: statusColor,
                                    placeholder:
                                        strings.workshopSnsLinkFieldLabel,
                                    onTap: _pickSnsLinks,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // カード名はカードの直下、半透明の暗転バリアの上に表示する。
                  // 以前は白系→黒系と切り替えたが、バリアの不透明度が低いままだと
                  // 下に見えるページの背景色（ライト/ダークモードで大きく異なる）が
                  // 透けるため、どちらの固定色でも片方のモードで読みづらくなって
                  // いた（2026-07-29修正）。バリア自体を常に暗く保つ
                  // （barrierColor: Colors.black87、上記_openCardZoom参照）ことで
                  // 背景の明るさをモードに依存させず安定させ、白系の文字色に
                  // 統一した。編集ボタンは置かず、最初から常にTextFieldを表示する
                  // （新規カードは自動でフォーカスする）。
                  SizedBox(
                    width: width,
                    child: TextField(
                      controller: _nameController,
                      autofocus: _isNewCard,
                      maxLength: kMaxWorkshopCardNameLength,
                      textAlign: TextAlign.center,
                      // 指定しないとWeb版でブラウザが「名前欄」と誤認識し、
                      // 独自のオートフィル黄色ハイライトを重ねてくることが
                      // あったため、明示的に空にしてブラウザ側の自動補完
                      // 候補付けそのものを無効化する。
                      autofillHints: const [],
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: nameFontSize,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        hintText: strings.workshopCardNameLabel,
                        hintStyle: TextStyle(
                          color: Colors.white70,
                          fontSize: nameFontSize,
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white54,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _confirmName(),
                      onTapOutside: (_) => _confirmName(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 閉じるボタンは置かず、外側（黒い半透明のバリア部分）をタップして
        // 閉じる（`_openCardZoom`の`barrierDismissible: true`）。
        if (_persisted)
          Positioned(
            left: -12,
            top: -12,
            child: _RoundIconButton(onTap: _handleDelete),
          ),
      ],
    );
  }
}

/// ズームイン編集画面左上の削除ボタンに使う丸ボタン。
/// Hero対象の外側に置くため、[_CardZoomEditor]の独自ウィジェットとして分離している。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // タップ範囲が狭いという指摘を受け、アイコン本体（18px）より
        // 一回り大きい余白（14px）を確保し、実質46px角の押しやすさにする。
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(Icons.delete_outline, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// アイコン・背景画像用のポップアップ（同じ種類の素材だけを一覧表示する）。
/// 戻り値は素材id、空文字列は「なし」の選択、nullはポップを閉じただけ（変更なし）。
Future<String?> _showImageMaterialMenu(
  BuildContext context,
  RelativeRect position,
  List<ProfileMaterial> materials,
  String? selectedId,
  Strings strings,
) {
  return showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: '',
        child: _MaterialMenuRow(
          selected: selectedId == null,
          label: strings.workshopChoiceNone,
        ),
      ),
      if (materials.isEmpty)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(strings.workshopEmptyMaterialHint),
        ),
      for (final material in materials)
        PopupMenuItem<String>(
          value: material.id,
          child: _MaterialMenuRow(
            selected: selectedId == material.id,
            label: '',
            thumbnail: _NetworkThumbImage(url: material.url),
          ),
        ),
    ],
  );
}

/// ニックネーム・ステメ用のポップアップ（同じ種類の素材だけを一覧表示する）。
/// 戻り値の意味は[_showImageMaterialMenu]と同じ。
Future<String?> _showTextMaterialMenu(
  BuildContext context,
  RelativeRect position,
  List<(String, String)> items,
  String? selectedId,
  Strings strings,
) {
  return showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: '',
        child: _MaterialMenuRow(
          selected: selectedId == null,
          label: strings.workshopChoiceNone,
        ),
      ),
      if (items.isEmpty)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(strings.workshopEmptyMaterialHint),
        ),
      for (final (id, text) in items)
        PopupMenuItem<String>(
          value: id,
          child: _MaterialMenuRow(selected: selectedId == id, label: text),
        ),
    ],
  );
}

class _MaterialMenuRow extends StatelessWidget {
  const _MaterialMenuRow({
    required this.selected,
    required this.label,
    this.thumbnail,
  });

  final bool selected;
  final String label;
  final Widget? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: selected ? const Icon(Icons.check, size: 18) : null,
        ),
        if (thumbnail != null) ...[
          SizedBox(width: 28, height: 28, child: ClipOval(child: thumbnail)),
          const SizedBox(width: 8),
        ],
        if (label.isNotEmpty) Text(label),
      ],
    );
  }
}
