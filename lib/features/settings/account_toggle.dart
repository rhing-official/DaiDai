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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // 区画の高さをそろえる（`stretch`は縦が無限だと使えないので`IntrinsicHeight`）。
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _SegmentTile(
                      segment: segments[i],
                      switching: _switchingUid == segments[i].uid,
                      disabled: busy && _switchingUid != segments[i].uid,
                    ),
                  ),
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
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _strings.switchAccountsLongPressHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
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
        foreground = selected ? GekigaColors.onPanel : GekigaColors.panel;
        fill = selected ? GekigaColors.panel : null;
      case AppUiStyle.glass:
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
        return GlassSurface(
          borderRadius: BorderRadius.circular(12),
          accentColorOverride: selected ? scheme.primary : null,
          child: Material(color: fill ?? Colors.transparent, child: tappable),
        );
      case AppUiStyle.gekiga:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: GekigaColors.panel, width: 2.5),
          ),
          child: Material(color: Colors.transparent, child: tappable),
        );
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
