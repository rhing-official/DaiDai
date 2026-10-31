/// カード内のURLの左に出す、主要サービスの単色アイコン（2026-10-31追加）。
/// 同梱のSVG（`assets/sns_icons/`、Simple Icons・CC0）だけを使い、外部へは
/// 通信しない。一覧に無いサイトは`null`（アイコンなし）。
///
/// ドメインは**末尾一致**（`host == d`または`host.endsWith('.d')`）で照合する
/// ため、`notex.com`のような別ドメインには一致しない。`www.`・`m.`・`mobile.`は
/// 照合前に取り除く。OGP画像（`functions/src/snsIcons.ts`）も同じ規則・対応表。
const Map<String, String> kSnsIconDomains = {
  'x.com': 'x',
  'twitter.com': 'x',
  'note.com': 'note',
  'youtube.com': 'youtube',
  'youtu.be': 'youtube',
  'instagram.com': 'instagram',
  'github.com': 'github',
  'pixiv.net': 'pixiv',
  'tiktok.com': 'tiktok',
  'twitch.tv': 'twitch',
  'discord.gg': 'discord',
  'discord.com': 'discord',
  'bsky.app': 'bluesky',
  'facebook.com': 'facebook',
  'threads.net': 'threads',
  'threads.com': 'threads',
  'line.me': 'line',
  'nicovideo.jp': 'niconico',
  'zenn.dev': 'zenn',
  'qiita.com': 'qiita',
  'ko-fi.com': 'kofi',
  'spotify.com': 'spotify',
  'soundcloud.com': 'soundcloud',
  'steampowered.com': 'steam',
  'steamcommunity.com': 'steam',
  'reddit.com': 'reddit',
};

/// [url]に対応するアイコンの名前（`assets/sns_icons/<名前>.svg`）。無ければnull。
String? snsIconNameFor(String url) {
  var host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return null;
  host = host.replaceFirst(RegExp(r'^(www|m|mobile)\.'), '');
  for (final entry in kSnsIconDomains.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) return entry.value;
  }
  return null;
}

/// [url]に対応するアイコンのアセットのパス。無ければnull。
String? snsIconAssetFor(String url) {
  final name = snsIconNameFor(url);
  return name == null ? null : 'assets/sns_icons/$name.svg';
}
