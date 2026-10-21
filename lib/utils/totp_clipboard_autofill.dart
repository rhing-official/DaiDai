import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fullwidth_digits_formatter.dart';

/// クリップボードの文字列から、認証アプリ（TOTP）の6桁コードを取り出す
/// （2026-10-21追加）。全角数字は半角にし、空白・ハイフンは取り除く
/// （認証アプリの「123 456」表記に対応）。ちょうど6桁の数字でなければnull。
String? parseTotpCode(String? clipboardText) {
  if (clipboardText == null) return null;
  final normalized = toHalfWidthDigits(
    clipboardText.trim(),
  ).replaceAll(RegExp(r'[\s\-]'), '');
  return RegExp(r'^\d{6}$').hasMatch(normalized) ? normalized : null;
}

/// クリップボードを1回読み、6桁のコードがあれば返す。Webのブラウザ権限の
/// 拒否などで読めない場合はnull（従来どおり手入力で使える）。
Future<String?> readClipboardTotpCode() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return parseTotpCode(data?.text);
  } catch (_) {
    return null;
  }
}

/// 2段階認証のコード入力欄で、認証アプリでコピーした6桁を自動で貼り付けて
/// 確定する（2026-10-21追加）。クリップボードを読むのは、入力欄が出ている間に
/// [checkTotpClipboard]が呼ばれた時と、アプリが前面に戻った時だけ。6桁の数字
/// 以外は無視し、保存も送信もしない。
///
/// 確定に失敗したコードで繰り返さないよう、直前に自動入力したコードと同じ
/// クリップボードの値では再度動かない。
mixin TotpClipboardAutofill<T extends StatefulWidget> on State<T> {
  /// 6桁を入れる入力欄のコントローラー。
  TextEditingController get totpCodeController;

  /// 入力欄が出ていて、確定処理中でない時だけtrue。
  bool get totpAutofillActive;

  /// 6桁を入力欄に入れた直後に呼ばれる（ここで確定する）。
  void onTotpAutofilled(String code);

  AppLifecycleListener? _totpLifecycleListener;
  String? _lastAutofilledTotp;
  bool _checkingTotpClipboard = false;

  @override
  void initState() {
    super.initState();
    _totpLifecycleListener = AppLifecycleListener(onResume: checkTotpClipboard);
  }

  @override
  void dispose() {
    _totpLifecycleListener?.dispose();
    super.dispose();
  }

  /// クリップボードを確認し、6桁なら入力欄に入れて確定する。
  Future<void> checkTotpClipboard() async {
    if (_checkingTotpClipboard || !mounted || !totpAutofillActive) return;
    _checkingTotpClipboard = true;
    try {
      final code = await readClipboardTotpCode();
      if (!mounted || !totpAutofillActive) return;
      if (code == null || code == _lastAutofilledTotp) return;
      _lastAutofilledTotp = code;
      totpCodeController.text = code;
      onTotpAutofilled(code);
    } finally {
      _checkingTotpClipboard = false;
    }
  }
}
