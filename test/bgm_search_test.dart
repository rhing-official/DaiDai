import 'package:daidai/features/call/bgm/bgm_track.dart';
import 'package:flutter_test/flutter_test.dart';

BgmTrack _t(String id, String name, {String? artist, String? tagAlbum}) =>
    BgmTrack(
      id: id,
      name: name,
      mimeType: 'audio/mpeg',
      size: 1,
      artist: artist,
      tagAlbum: tagAlbum,
    );

void main() {
  final tracks = [
    _t('1', 'Blue Moon', artist: 'Alice'),
    _t('2', 'ありがとう', artist: 'Bob', tagAlbum: 'Thanks'),
    _t('3', '夜に駆ける', artist: 'YOASOBI'),
  ];

  List<String> ids(String q) => [
    for (final t in searchBgmTracks(tracks, q)) t.id,
  ];

  test('空の入力は全曲（元の並び）', () {
    expect(ids(''), ['1', '2', '3']);
    expect(ids('  '), ['1', '2', '3']);
  });

  test('大文字小文字・ひらがな/カタカナのゆれを吸収する', () {
    expect(ids('BLUE'), ['1']);
    expect(ids('アリガトウ'), ['2']);
    expect(ids('ありがとう'), ['2']);
  });

  test('アーティスト・タグのアルバム名にも一致する', () {
    expect(ids('yoasobi'), ['3']);
    expect(ids('thanks'), ['2']);
  });

  test('空白で区切った語は全てを含む曲だけ（AND）', () {
    expect(ids('blue alice'), ['1']);
    expect(ids('blue bob'), isEmpty);
    expect(ids('blue　alice'), ['1']);
  });

  test('該当なしは空', () {
    expect(ids('zzz'), isEmpty);
  });
}
