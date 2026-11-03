import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_log.dart';

/// ICE候補の文字列から、種類（host/srflx/relay）とプロトコル（udp/tcp）だけを
/// 取り出す診断用の要約（IPアドレスは含めない、2026-11-03）。
String summarizeIceCandidate(String? candidate) {
  if (candidate == null || candidate.isEmpty) return 'empty';
  final parts = candidate.split(' ');
  final protocol = parts.length > 2 ? parts[2].toLowerCase() : '?';
  final typeIndex = parts.indexOf('typ');
  final type = typeIndex >= 0 && typeIndex + 1 < parts.length
      ? parts[typeIndex + 1]
      : '?';
  return '$type/$protocol';
}

/// `iceServers`のURLだけを一覧にする（認証情報は出さない）。
String summarizeIceServers(Object? iceServers) {
  if (iceServers is! List) return '';
  final urls = <String>[];
  for (final server in iceServers) {
    if (server is! Map) continue;
    final u = server['urls'];
    if (u is List) {
      urls.addAll(u.map((e) => e.toString()));
    } else if (u != null) {
      urls.add(u.toString());
    }
  }
  return urls.join(', ');
}

/// 候補の数と、成立した候補ペアの種類をログに出す。失敗時や接続の数秒後に呼ぶ。
Future<void> logIceStats(RTCPeerConnection? connection, String label) async {
  if (connection == null) return;
  try {
    final reports = await connection.getStats();
    final local = <String, int>{};
    String? selected;
    final candidateTypes = <String, String>{};
    for (final report in reports) {
      if (report.type == 'local-candidate') {
        final type = '${report.values['candidateType']}';
        candidateTypes[report.id] = type;
        local[type] = (local[type] ?? 0) + 1;
      }
    }
    for (final report in reports) {
      if (report.type == 'candidate-pair' &&
          (report.values['state'] == 'succeeded' ||
              report.values['nominated'] == true)) {
        selected =
            'local=${candidateTypes[report.values['localCandidateId']] ?? '?'}';
      }
    }
    callLog('$label stats localCandidates=$local selectedPair=$selected');
  } catch (e) {
    callLog('$label stats failed: $e');
  }
}
