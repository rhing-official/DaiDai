import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';

const _channel = MethodChannel('jp.rhing.daidai/call_action');

/// 緊急の着信を、おやすみモード中も鳴らす許可の項目（Androidのみ、2026-11-25）。相手が通話ボタンを
/// 長押しして発信した着信だけが貫通する。端末の「おやすみモードの許可」が要るため、許可の状態を出し、
/// 無ければ端末の設定画面へ案内する。設定画面から戻ったら、状態を読み直す。
class UrgentCallAccessTile extends ConsumerStatefulWidget {
  const UrgentCallAccessTile({super.key});

  @override
  ConsumerState<UrgentCallAccessTile> createState() =>
      _UrgentCallAccessTileState();
}

class _UrgentCallAccessTileState extends ConsumerState<UrgentCallAccessTile>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    bool granted;
    try {
      granted = await _channel.invokeMethod<bool>('hasDndAccess') ?? false;
    } on MissingPluginException {
      granted = false;
    } on PlatformException {
      granted = false;
    }
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _openSettings() async {
    try {
      await _channel.invokeMethod<void>('openDndAccessSettings');
    } on MissingPluginException {
      // 想定外の環境。何もしない。
    } on PlatformException {
      // 同上。
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final granted = _granted ?? false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(strings.settingsUrgentCallTitle),
      subtitle: Text(
        '${strings.settingsUrgentCallDescription}\n'
        '${granted ? strings.settingsUrgentCallAllowed : strings.settingsUrgentCallNotAllowed}',
      ),
      isThreeLine: true,
      trailing: granted
          ? null
          : TextButton(
              onPressed: _openSettings,
              child: Text(strings.settingsUrgentCallOpenSettings),
            ),
    );
  }
}
