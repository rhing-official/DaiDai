import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/profile_card.dart';
import '../../models/saved_account.dart';
import '../../providers/account_switcher_providers.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../repositories/switch_session_repository.dart';
import '../../services/account_switcher.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/kiwami.dart';
import '../../widgets/account_avatar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/kiwami_only_dialog.dart';

/// 画面に出す、切り替えの失敗の説明（表示言語に合わせる。サーバーの文言は使わない）。
String switchAccountFailureMessage(
  Strings strings,
  SwitchAccountException error, {
  required String fallback,
}) => switch (error.kind) {
  SwitchAccountFailure.kiwamiRequired => strings.switchAccountsKiwamiLapsed,
  SwitchAccountFailure.reloginNeeded => strings.switchAccountsReloginNeeded,
  SwitchAccountFailure.limitReached => strings.switchAccountsLimit,
  SwitchAccountFailure.other => fallback,
};

/// アカウントの切り替えスイッチ（2026-11-11）。保存したアカウントの数だけ区画を並べ、
/// 各区画はアイコンの下に`@seed`を出す。押すとそのアカウントへ切り替える。保存数が上限
/// （[AccountSwitcher.maxAccounts]）に満たなければ、末尾に「追加」の区画を出す。取り外しは
/// 下の「管理」から行う。設計は`文書/複数アカウント.md`。
class AccountToggle extends ConsumerStatefulWidget {
  const AccountToggle({
    required this.strings,
    required this.currentUser,
    super.key,
  });

  final Strings strings;
  final AppUser currentUser;

  @override
  ConsumerState<AccountToggle> createState() => _AccountToggleState();
}

class _AccountToggleState extends ConsumerState<AccountToggle> {
  /// 切り替え中のアカウントのuid（再読み込みまでの1〜数秒、他の区画を押せなくする）。
  String? _switchingUid;

  Strings get _strings => widget.strings;

  void _banner(String message) {
    if (mounted) showAutoDismissBanner(context, message: message);
  }

  Future<void> _add() async {
    final switcher = ref.read(accountSwitcherProvider);
    final user = widget.currentUser;
    if (!isKiwami(user)) {
      await showKiwamiOnlyDialog(
        context,
        _strings,
        body: _strings.switchAccountsKiwamiBody,
      );
      return;
    }
    if (!await switcher.canAdd(user)) {
      _banner(_strings.switchAccountsLimit);
      return;
    }
    if (!mounted) return;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_strings.switchAccountsTrustTitle),
        content: Text(_strings.switchAccountsTrustBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_strings.switchAccountsTrustConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await switcher.startAdd(user);
      ref.invalidate(hasPendingAccountAddProvider);
    } on SwitchAccountException catch (error) {
      _banner(
        switchAccountFailureMessage(
          _strings,
          error,
          fallback: _strings.switchAccountsAddFailed,
        ),
      );
    }
  }

  Future<void> _switch(SavedAccount account) async {
    if (_switchingUid != null) return;
    setState(() => _switchingUid = account.uid);
    try {
      await ref.read(accountSwitcherProvider).switchTo(account);
      // 成功すると再読み込みされる。再読み込みまでは押せないままにしておく。
    } on SwitchAccountException catch (error) {
      if (mounted) setState(() => _switchingUid = null);
      _banner(
        switchAccountFailureMessage(
          _strings,
          error,
          fallback: _strings.switchAccountsFailed,
        ),
      );
    } on Object {
      if (mounted) setState(() => _switchingUid = null);
      _banner(_strings.switchAccountsFailed);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 他のアカウントの区画を長押しした時。保存の取り外しを確認する。
  Future<void> _confirmRemove(SavedAccount account) async {
    if (_switchingUid != null) return;
    if (!await _confirm(
      title: _strings.switchAccountsRemoveTitle,
      body: _strings.switchAccountsRemoveBody,
      action: _strings.switchAccountsRemove,
    )) {
      return;
    }
    await ref.read(accountSwitcherProvider).forget(account.uid);
    ref.invalidate(savedAccountsProvider);
  }

  /// 今のアカウントの区画を長押しした時。ログアウトを確認し、保存した別のアカウント
  /// （先頭）へ自動で切り替える。他に保存したアカウントが無ければ何もしない。
  Future<void> _confirmLogoutCurrent(List<SavedAccount> others) async {
    if (_switchingUid != null || others.isEmpty) return;
    if (!await _confirm(
      title: _strings.switchAccountsLogoutTitle,
      body: _strings.switchAccountsLogoutBody,
      action: _strings.switchAccountsLogout,
    )) {
      return;
    }
    await _logoutCurrent(others.first);
  }

  /// 今使っているアカウントを取り外す（ログアウト）。保存した別のアカウントへ自動で切り替える。
  Future<void> _logoutCurrent(SavedAccount next) async {
    setState(() => _switchingUid = next.uid);
    try {
      await ref
          .read(accountSwitcherProvider)
          .switchTo(next, forgetUid: widget.currentUser.userId);
    } on SwitchAccountException catch (error) {
      if (mounted) setState(() => _switchingUid = null);
      _banner(
        switchAccountFailureMessage(
          _strings,
          error,
          fallback: _strings.switchAccountsFailed,
        ),
      );
    } on Object {
      if (mounted) setState(() => _switchingUid = null);
      _banner(_strings.switchAccountsFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedAccountsProvider).value ?? const [];
    final current = widget.currentUser;
    final others = [
      for (final a in saved)
        if (a.uid != current.userId) a,
    ];
    final segments = <_Segment>[
      _Segment(
        uid: current.userId,
        rhingSeed: current.rhingSeed,
        iconUrl: current.effectiveIcon?.url,
        iconFocal: current.effectiveIconFocalFor(null),
        selected: true,
        onLongPress: others.isEmpty
            ? null
            : () => _confirmLogoutCurrent(others),
      ),
      for (final a in others)
        _Segment(
          uid: a.uid,
          rhingSeed: a.rhingSeed,
          iconUrl: a.iconUrl,
          iconFocal: a.iconFocal,
          onTap: () => _switch(a),
          onLongPress: () => _confirmRemove(a),
        ),
      if (others.length + 1 < AccountSwitcher.maxAccounts)
        _Segment.add(label: _strings.switchAccountsAdd, onTap: _add),
    ];
    final busy = _switchingUid != null;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final scheme = Theme.of(context).colorScheme;
    // 区画の外の説明文の色。劇画は赤い背景に白、ガラスは面の上の中立色、
    // それ以外はテーマの既定（CLAUDE.mdの方針: アクセントカラーにしない）。
    final noteStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: isGekiga
          ? GekigaColors.onPanel
          : (uiStyle == AppUiStyle.glass ? scheme.onSurfaceVariant : null),
    );

    Widget tile(_Segment segment) => _SegmentTile(
      segment: segment,
      switching: _switchingUid == segment.uid,
      disabled: busy && _switchingUid != segment.uid,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: isGekiga
              // 劇画: 他の一覧と同じ、ギザギザの太線の箱（選択中=白地黒字、非選択=黒地白字）。
              // 箱は中身の幅になるため、区画の数で均等に割った幅を与える。
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final count = segments.length;
                    final width =
                        (constraints.maxWidth -
                            GekigaJointedTileList.gap * (count - 1)) /
                        count;
                    return GekigaJointedTileList(
                      axis: Axis.horizontal,
                      seeds: [for (final s in segments) s.uid.hashCode],
                      selectedFlags: [for (final s in segments) s.selected],
                      children: [
                        for (final s in segments)
                          SizedBox(width: width, child: tile(s)),
                      ],
                    );
                  },
                )
              // 区画の高さをそろえる（`stretch`は縦が無限だと使えないので`IntrinsicHeight`）。
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: tile(segments[i])),
                      ],
                    ],
                  ),
                ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _strings.switchAccountsSwitching,
              textAlign: TextAlign.center,
              style: noteStyle,
            ),
          ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _strings.switchAccountsLongPressHint,
              textAlign: TextAlign.center,
              style: noteStyle,
            ),
          ),
      ],
    );
  }
}

class _Segment {
  const _Segment({
    required this.uid,
    required this.rhingSeed,
    this.iconUrl,
    this.iconFocal,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  }) : addLabel = null;

  const _Segment.add({required String label, required this.onTap})
    : uid = '',
      rhingSeed = '',
      iconUrl = null,
      iconFocal = null,
      selected = false,
      onLongPress = null,
      addLabel = label;

  final String uid;
  final String rhingSeed;
  final String? iconUrl;
  final ImageFocal? iconFocal;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 「追加」の区画の時だけ非null。
  final String? addLabel;

  bool get isAdd => addLabel != null;
}

class _SegmentTile extends ConsumerWidget {
  const _SegmentTile({
    required this.segment,
    required this.switching,
    required this.disabled,
  });

  final _Segment segment;
  final bool switching;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    final selected = segment.selected;

    // 選択中の区画だけ塗る。文字はアクセントカラーにせず、塗りの上は`onPrimary`、
    // 塗りの無い所は中立色（CLAUDE.mdの方針）。
    final Color foreground;
    final Color? fill;
    switch (uiStyle) {
      case AppUiStyle.gekiga:
        // 箱は親（`GekigaJointedTileList`）が描く。選択中=白地黒字、非選択=黒地白字。
        foreground = selected ? GekigaColors.panel : GekigaColors.onPanel;
        fill = null;
      case AppUiStyle.glass:
        // ナビチップと同じ: 文字色は選択で変えず、塗りだけで選択を表す。
        foreground = scheme.onSurfaceVariant;
        fill = selected ? scheme.primary.withValues(alpha: 0.45) : null;
      case AppUiStyle.block:
        foreground = selected ? scheme.onPrimary : scheme.onSurface;
        fill = selected ? scheme.primary : null;
      case AppUiStyle.flat:
        foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
        fill = selected ? scheme.primary : scheme.surface;
    }

    final avatar = segment.isAdd
        ? SizedBox(
            height: 40,
            child: Icon(Icons.person_add_alt_1_outlined, color: foreground),
          )
        : SizedBox(
            height: 40,
            width: 40,
            child: switching
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : AccountAvatar(
                    uid: segment.uid,
                    rhingSeed: segment.rhingSeed,
                    iconUrl: segment.iconUrl,
                    iconFocal: segment.iconFocal,
                    size: 40,
                  ),
          );
    final label = Text(
      segment.isAdd ? segment.addLabel! : '@${segment.rhingSeed}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(color: foreground, fontSize: 12),
    );
    final content = Padding(
      // 劇画は、箱の太い枠が内側へ食い込む分だけ余白を広げる。
      padding: uiStyle == AppUiStyle.gekiga
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [avatar, const SizedBox(height: 6), label],
      ),
    );
    final tappable = InkWell(
      onTap: disabled || switching ? null : segment.onTap,
      onLongPress: disabled || switching ? null : segment.onLongPress,
      child: Opacity(opacity: disabled ? 0.5 : 1, child: content),
    );

    switch (uiStyle) {
      case AppUiStyle.glass:
        // ナビチップと同じ、ぼかしのあるすりガラス（`chrome`）。選択中はアクセントカラーが
        // 縁の光彩として出て、面の塗りもアクセントカラーが透ける。
        return GlassSurface(
          variant: GlassVariant.chrome,
          borderRadius: BorderRadius.circular(16),
          accentColorOverride: selected ? scheme.primary : null,
          child: Material(
            color: fill ?? Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: tappable,
          ),
        );
      case AppUiStyle.gekiga:
        // 外枠は`GekigaJointedTileList`が描くので、ここでは中身（タップ領域）だけ。
        return Material(color: Colors.transparent, child: tappable);
      case AppUiStyle.block:
        return blockMaterialBox(
          context,
          color:
              fill ??
              (Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : scheme.surface),
          child: Material(color: Colors.transparent, child: tappable),
        );
      case AppUiStyle.flat:
        return Material(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: tappable,
        );
    }
  }
}
