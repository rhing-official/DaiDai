import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/report.dart';

void main() {
  test('AdminReport: メッセージの通報の証拠を読み取る', () {
    final report = AdminReport.fromJson({
      'reportId': 'r1',
      'targetType': 'message',
      'reason': 'harassment',
      'note': 'ひどい',
      'reporterId': 'u1',
      'reporterSeed': 'alice',
      'targetUserId': 'u2',
      'targetSeed': 'bob',
      'status': 'open',
      'createdAt': '2026-11-22T00:00:00.000Z',
      'evidence': {
        'conversation': {
          'kind': 'group',
          'conversationId': 'g1',
          'roomId': 'room',
          'groupName': 'テスト広場',
        },
        'messages': [
          {
            'messageId': 'm0',
            'senderId': 'u1',
            'senderRhingSeed': 'alice',
            'content': 'こんにちは',
            'contentType': 'text',
            'sentAt': '2026-11-21T23:59:00.000Z',
            'attachments': [],
            'isTarget': false,
          },
          {
            'messageId': 'm1',
            'senderId': 'u2',
            'senderRhingSeed': 'bob',
            'content': '',
            'contentType': 'image',
            'sentAt': null,
            'attachments': [
              {
                'fileName': 'a.webp',
                'mimeType': 'image/webp',
                'sizeBytes': 1,
                'url': 'x',
              },
            ],
            'isTarget': true,
          },
        ],
      },
    });
    expect(report.targetType, ReportTargetType.message);
    expect(report.reason, ReportReason.harassment);
    expect(report.isResolved, isFalse);
    expect(report.groupName, 'テスト広場');
    expect(report.evidenceMessages, hasLength(2));
    expect(report.evidenceMessages[1].isTarget, isTrue);
    expect(report.evidenceMessages[1].sentAt, isNull);
    expect(report.evidenceMessages[1].attachmentNames, ['a.webp']);
  });

  test('AdminReport: 処理済み・広場の通報・欠けた項目', () {
    final report = AdminReport.fromJson({
      'reportId': 'r2',
      'targetType': 'group',
      'reason': 'other',
      'status': 'resolved',
      'resolution': 'dismissed',
      'resolutionNote': '問題なし',
      'evidence': {
        'group': {'groupId': 'g', 'name': '広場A'},
      },
    });
    expect(report.isResolved, isTrue);
    expect(report.resolution, ReportResolution.dismissed);
    expect(report.groupName, '広場A');
    expect(report.evidenceMessages, isEmpty);
    expect(report.createdAt, isNull);
    expect(report.reporterSeed, isNull);
  });

  test('列挙: 不明な名前はnull', () {
    expect(ReportReason.fromName('spam'), ReportReason.spam);
    expect(ReportReason.fromName('x'), isNull);
    expect(ReportTargetType.fromName(null), isNull);
  });
}
