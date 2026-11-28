import 'dart:convert';
import 'dart:io';

import 'package:daidai/utils/google_sign_in_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Googleログインの「serverClientId must be provided on Android」の再発を防ぐ（2026-11-28）。
/// 原因は、リリースビルドのリソース縮小で`default_web_client_id`が消えること。
void main() {
  test('明示のウェブクライアントIDが、google-services.jsonのものと一致する', () {
    final json =
        jsonDecode(File('android/app/google-services.json').readAsStringSync())
            as Map<String, dynamic>;
    final ids = <String>{
      for (final client in json['client'] as List)
        for (final o in (client as Map)['oauth_client'] as List)
          if ((o as Map)['client_type'] == 3) o['client_id'] as String,
    };
    expect(ids, contains(googleWebClientId));
  });

  test('keep.xmlが、default_web_client_idを縮小から守っている', () {
    final keep = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    expect(keep, contains('@string/default_web_client_id'));
  });
}
