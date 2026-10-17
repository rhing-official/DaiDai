/// 404ページで展示する作品1点の訳（題・解説）。日本語・英語は
/// `MuseumExhibit`自身が持ち、それ以外の表示言語の訳をここに言語別に置く
/// （2026-10-17追加）。キーは作品の`asset`。
class MuseumText {
  const MuseumText({required this.title, required this.caption});

  final String title;
  final String caption;
}

/// フランス語（AIによる初稿、公開前にネイティブの確認を推奨）。
const museumTextsFr = <String, MuseumText>{
  'assets/museum/night-alley.jpg': MuseumText(
    title: '« Le Couloir de la nuit »',
    caption: 'Une ruelle éclairée de lampes, la nuit',
  ),
  'assets/museum/vintage-chairs.jpg': MuseumText(
    title: '« Chaises de couleur »',
    caption: 'Cinq chaises alignées dans un jardin',
  ),
  'assets/museum/rose-and-monument.jpg': MuseumText(
    title: '« Roses et monument »',
    caption: 'Sur une place sous un ciel nuageux',
  ),
  'assets/museum/snow-town.jpg': MuseumText(
    title: '« Ville enneigée, ombre de la montagne »',
    caption: 'Des toits dorés par le soleil couchant',
  ),
  'assets/museum/berries-in-shade.jpg': MuseumText(
    title: '« Fruits à l’ombre »',
    caption: 'Des baies bleues cachées parmi les feuilles',
  ),
  'assets/museum/leaves-in-dark.jpg': MuseumText(
    title: '« Couleurs du feuillage »',
    caption: 'Un amas de feuilles flottant dans l’obscurité',
  ),
};
