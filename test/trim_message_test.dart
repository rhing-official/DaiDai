import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/utils/trim_message.dart';

void main() {
  test('前後の空白・改行・全角スペースを取り除く', () {
    expect(trimMessage('  \n　こんにちは \t\n'), 'こんにちは');
  });
  test('ゼロ幅スペースも取り除く', () {
    expect(trimMessage('​​abc⁠﻿'), 'abc');
    expect(trimMessage(' ​ \nabc ​\n'), 'abc');
  });
  test('途中の空白・改行は残す', () {
    expect(trimMessage(' a  b\nc '), 'a  b\nc');
  });
  test('空白のみは空になる', () {
    expect(trimMessage(' \n​　'), '');
    expect(trimMessage(''), '');
  });
}
