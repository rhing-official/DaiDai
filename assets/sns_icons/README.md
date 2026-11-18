# SNSロゴ（プロフィールカードのURLの左に出すアイコン）

各社が**公式に配布するロゴ素材そのもの**だけを置く（2026-11-18）。以前はSimple Icons（CC0）の
単色アイコンを使っていたが、CC0が放棄するのはSimple Iconsの著作権だけで、各社の商標権は別。
かつ各社の規定は色の変更・変形・描き直しを禁止（または制限）しているため、公式素材に差し替えた。

## 守ること

- **色を変えない・変形しない・描き直さない。** 背景の明るさに合わせて、公式の別の版（黒／白、
  Zennは青／白）を切り替えるだけにする（`lib/utils/sns_icon.dart`の`snsIconAssetFor`、
  OGP画像は`functions/src/snsIcons.ts`）。`SvgPicture`に`colorFilter`を付けない。
- `<名前>.svg`＝明るい背景用、`<名前>-white.svg`＝暗い背景用。
- 素材を足す時は、公式ページの規定（プロフィールのリンク用途・色・申請の要否）を確認し、
  この表に取得元を書き、`kSnsOfficialIconNames`（Dart）と`SNS_OFFICIAL_ICON_SVGS`（TS）の
  両方に足す。公式素材が無いサービスは、アイコンを出さずドメインの文字を出す。
- ここのSVGを変えたら、`functions/src/snsIcons.ts`の埋め込みSVGも同じ内容に直す
  （`functions/src/snsIcons.test.ts`が一致を確認する）。

## 同梱している素材

| ファイル | 取得元（公式） | 使った版 |
|---|---|---|
| `bluesky.svg` / `bluesky-white.svg` | https://bsky.social/about/support/icons （`brand-assets/butterfly/`） | butterfly 黒／白。商標ポリシーは、公式の形でプロフィールへのリンクに使うことを許可（再着色は公式の白・黒のみ） |
| `github.svg` / `github-white.svg` | https://github.com/logos （GitHub_Logos.zip、`SVG/GitHub_Invertocat_*.svg`） | Invertocat 黒／白。改変（色・寸法）は不可 |
| `discord.svg` / `discord-white.svg` | https://discord.com/branding （Discord_Symbol_Black／White） | Symbol 黒／白。編集・再着色は不可 |
| `zenn.svg` / `zenn-white.svg` | https://zenn.dev/mediakit （zenn-logo.zip、`logo-only.svg`・`logo-only-white.svg`） | ロゴマーク 青（明るい背景）／白（暗い背景）。変形・装飾は避ける |

## 未同梱（公式素材を取得できていない・規定が未確認。アイコンは出さない）

X・Instagram・Facebook・Threads・YouTube（チャンネルのURLのみ可）・TikTok・LINE・Twitch・
Spotify・SoundCloud・Reddit・Steam・Ko-fi・note・pixiv・ニコニコ・Qiita。

- 取得に同意や申請が要るもの（Metaの各ブランド、TikTok等）は、利用者本人の操作で取得する。
- pixivは、使える色が青（明背景）・白（暗背景）のカラーロゴだけ。Qiitaは、営利目的の利用に
  事前の連絡と許諾が必要（DaiDaiは有料プランがあるため、連絡して許諾を得るまで使わない）。
- YouTubeは、ロゴ・アイコンをリンクにしてよいのは行き先がチャンネルの時だけ
  （`isYouTubeChannelPath`）。
