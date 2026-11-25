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

/// 自分が実際に送信出来ている音声・映像の量をログに出す（iOS実機で、権限は
/// 許可したのに相手に音声・映像が届かない不具合の切り分け用、2026-11-23）。
/// ICE接続後に数秒待ってから呼ぶこと（接続直後は送信量がまだ0のため）。
Future<void> logOutboundMediaStats(
  RTCPeerConnection? connection,
  String label,
) async {
  if (connection == null) return;
  try {
    final reports = await connection.getStats();
    for (final report in reports) {
      if (report.type == 'outbound-rtp') {
        final kind = report.values['kind'] ?? report.values['mediaType'];
        final bytesSent = report.values['bytesSent'];
        final packetsSent = report.values['packetsSent'];
        if (kind == 'video') {
          callLog(
            '$label outbound video bytesSent=$bytesSent '
            'packetsSent=$packetsSent '
            'framesEncoded=${report.values['framesEncoded']} '
            'size=${report.values['frameWidth']}x'
            '${report.values['frameHeight']}',
          );
        } else if (kind == 'audio') {
          callLog(
            '$label outbound audio bytesSent=$bytesSent '
            'packetsSent=$packetsSent',
          );
        }
      } else if (report.type == 'media-source' &&
          report.values['kind'] == 'audio') {
        callLog(
          '$label media-source audioLevel=${report.values['audioLevel']}',
        );
      }
    }
  } catch (e) {
    callLog('$label outbound stats failed: $e');
  }
}

/// 送信している映像（`outbound-rtp`の映像）の、これまでに符号化したフレーム数。取れない時は
/// `null`（接続が無い・統計が取れない・映像が無い）。カメラの切り替え後に、新しいカメラの
/// 最初のフレームが出たかを、フレーム数の増加で知るために使う（2026-11-25）。
Future<int?> outboundVideoFramesEncoded(RTCPeerConnection? connection) async {
  if (connection == null) return null;
  try {
    final reports = await connection.getStats();
    int? best;
    for (final report in reports) {
      if (report.type != 'outbound-rtp') continue;
      final kind = report.values['kind'] ?? report.values['mediaType'];
      if (kind != 'video') continue;
      final frames = report.values['framesEncoded'];
      if (frames is num && (best == null || frames > best)) {
        best = frames.toInt();
      }
    }
    return best;
  } catch (_) {
    return null;
  }
}
