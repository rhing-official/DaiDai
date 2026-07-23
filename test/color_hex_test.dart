import 'package:daidai/utils/color_hex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// アクセントカラーのカラーコード解析。8桁入力（RRGGBBAA）の末尾2桁は
// 透明度のはずが、Color(value)へ生の整数として渡していたためAARRGGBBと
// 取り違えて全く別の色になっていたバグの回帰テスト。
void main() {
  test('6桁と、透明度FFを付けた8桁は同じ色になる', () {
    final six = tryParseHexColor('f08300');
    final eight = tryParseHexColor('f08300ff');
    expect(six, isNotNull);
    expect(eight, isNotNull);
    expect(eight, six);
    expect(six!.toARGB32(), 0xFFF08300);
  });

  test('#付き・大文字小文字混在でも解析できる', () {
    expect(tryParseHexColor('#F08300'), tryParseHexColor('f08300'));
  });

  test('透明度80のRRGGBBAAは正しくAA=0x80になる', () {
    final color = tryParseHexColor('f0830080');
    expect(color!.toARGB32(), 0x80F08300);
  });

  test('不正な桁数・不正な文字はnullを返す', () {
    expect(tryParseHexColor('f083'), isNull);
    expect(tryParseHexColor('gggggg'), isNull);
  });

  test('toHexStringは不透明なら6桁、透明度があれば8桁を返す', () {
    expect(const Color(0xFFF08300).toHexString(), '#F08300');
    expect(const Color(0x80F08300).toHexString(), '#F0830080');
  });
}
