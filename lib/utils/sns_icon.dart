/// カード内のURLの左に出す、主要サービスのロゴ（2026-10-31追加、2026-11-18に公式素材へ変更）。
///
/// **各社が公式に配布するロゴ素材だけ**を同梱し（`assets/sns_icons/`、取得元と
/// 条件は同フォルダの`README.md`）、外部へは通信しない。公式素材は色の変更・変形・
/// 描き直しが禁止（または制限）されているため、色は変えず、**背景の明るさに合わせて
/// 公式の黒／白（Zennは青／白）の版を切り替える**だけにする。公式素材をまだ同梱して
/// いないサービス・一覧に無いサイトは`null`（アイコンなし、カードはドメインの文字を出す）。
///
/// ドメインは**末尾一致**（`host == d`又は`host.endsWith('.d')`）で照合する
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

/// YouTubeのチャンネルのURLのパスか（`/@名前`・`/channel/`・`/c/`・`/user/`）。
/// YouTubeのブランド規定（YouTube API Services Branding Guidelines）は、ロゴ・アイコンを
/// リンクにしてよいのは行き先がYouTubeのチャンネルの時だけとしているため、動画・
/// 再生リスト・ショート・`youtu.be`の短縮URLなどにはアイコンを出さない（2026-11-18）。
/// OGP画像（`functions/src/snsIcons.ts`）も同じ規則。
bool isYouTubeChannelPath(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('/@') ||
      lower.startsWith('/channel/') ||
      lower.startsWith('/c/') ||
      lower.startsWith('/user/');
}

/// [url]に対応するアイコンの名前（`assets/sns_icons/<名前>.svg`）。無ければnull。
String? snsIconNameFor(String url) {
  final uri = Uri.tryParse(url);
  var host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) return null;
  host = host.replaceFirst(RegExp(r'^(www|m|mobile)\.'), '');
  for (final entry in kSnsIconDomains.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      if (entry.value == 'youtube' && !isYouTubeChannelPath(uri!.path)) {
        return null;
      }
      return entry.value;
    }
  }
  return null;
}

/// 公式のロゴ素材を同梱しているサービス（`assets/sns_icons/<名前>.svg`＝明るい背景用、
/// `<名前>-white.svg`＝暗い背景用）。ここに無いサービスはアイコンを出さない。
/// 追加する時は、公式の配布ページの規定を確認し、`README.md`に取得元を書く。
const Set<String> kSnsOfficialIconNames = {
  'bluesky',
  'discord',
  'github',
  'zenn',
};

/// [url]に対応するロゴのアセットのパス。公式素材が無ければnull。
/// [onDark]が真なら暗い背景用（白）の版を返す。
String? snsIconAssetFor(String url, {bool onDark = false}) {
  final name = snsIconNameFor(url);
  if (name == null || !kSnsOfficialIconNames.contains(name)) return null;
  return 'assets/sns_icons/$name${onDark ? '-white' : ''}.svg';
}
