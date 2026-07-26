final urlPattern = RegExp(r'(https?://[^\s]+)');

/// 本文中で最初に見つかったURLを返す（無ければnull）。
/// リンクプレビューカードを1メッセージにつき1件だけ出すために使う。
String? firstUrlIn(String text) => urlPattern.firstMatch(text)?.group(0);
