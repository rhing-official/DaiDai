final urlPattern = RegExp(r'(https?://[^\s]+)');

/// 本文中で最初に見つかったURLを返す（無ければnull）。
/// リンクプレビューカードを1メッセージにつき1件だけ出すために使う。
String? firstUrlIn(String text) => urlPattern.firstMatch(text)?.group(0);

/// 1メッセージでプレビューを出すURLの上限（取得の負荷を抑えるため）。
const kMaxLinkPreviews = 5;

/// 本文中のURLを出現順に、重複を除いて最大[limit]件返す。リンクプレビューカードを
/// URLごとに出すために使う（2026-11-01、以前は先頭の1件だけだった）。
List<String> urlsIn(String text, {int limit = kMaxLinkPreviews}) {
  final urls = <String>[];
  for (final match in urlPattern.allMatches(text)) {
    final url = match.group(0)!;
    if (!urls.contains(url)) urls.add(url);
    if (urls.length >= limit) break;
  }
  return urls;
}
