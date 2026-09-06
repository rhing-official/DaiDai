import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/schedule_coordination.dart';
import 'package:daidai/models/schedule_coordination_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleCoordinationVote', () {
    test('fromNameは既知の値を対応するenumに変換する', () {
      expect(
        ScheduleCoordinationVote.fromName('yes'),
        ScheduleCoordinationVote.yes,
      );
      expect(
        ScheduleCoordinationVote.fromName('maybe'),
        ScheduleCoordinationVote.maybe,
      );
      expect(
        ScheduleCoordinationVote.fromName('no'),
        ScheduleCoordinationVote.no,
      );
    });

    test('未知の文字列・nullはnullを返す', () {
      expect(ScheduleCoordinationVote.fromName('unknown'), isNull);
      expect(ScheduleCoordinationVote.fromName(null), isNull);
    });
  });

  group('scheduleCoordinationCandidateKey', () {
    test('配列indexを文字列化するだけの単純なキー', () {
      expect(scheduleCoordinationCandidateKey(0), '0');
      expect(scheduleCoordinationCandidateKey(3), '3');
    });
  });

  group('ScheduleCoordination', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'roomId': 'room1',
        'title': '忘年会',
        'description': '候補日から選んでください',
        'candidateDates': [
          Timestamp.fromDate(DateTime(2026, 12, 1)),
          Timestamp.fromDate(DateTime(2026, 12, 8)),
        ],
        'createdBy': 'user1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 5)),
        'deadline': Timestamp.fromDate(DateTime(2026, 9, 10)),
        'responseCount': 2,
        'finalizedCandidateIndex': null,
        'finalizedEventId': null,
      };
      final coordination = ScheduleCoordination.fromJson('coord1', json);

      expect(coordination.coordinationId, 'coord1');
      expect(coordination.roomId, 'room1');
      expect(coordination.title, '忘年会');
      expect(coordination.candidateDates, hasLength(2));
      expect(coordination.responseCount, 2);
      expect(coordination.isFinalized, isFalse);

      final roundTripped = ScheduleCoordination.fromJson(
        'coord1',
        coordination.toJson(),
      );
      expect(roundTripped.title, coordination.title);
      expect(roundTripped.candidateDates, coordination.candidateDates);
      expect(roundTripped.deadline, coordination.deadline);
    });

    test('finalizedEventIdが設定されているとisFinalizedがtrueになる', () {
      final coordination = ScheduleCoordination(
        coordinationId: 'coord1',
        roomId: 'room1',
        title: '忘年会',
        candidateDates: [Timestamp.fromDate(DateTime(2026, 12, 1))],
        createdBy: 'user1',
        finalizedCandidateIndex: 0,
        finalizedEventId: 'event1',
      );
      expect(coordination.isFinalized, isTrue);
    });

    test('responseCount・deadline省略時のデフォルト値', () {
      final json = {
        'roomId': 'room1',
        'title': '忘年会',
        'candidateDates': <Timestamp>[],
        'createdBy': 'user1',
      };
      final coordination = ScheduleCoordination.fromJson('coord1', json);
      expect(coordination.responseCount, 0);
      expect(coordination.deadline, isNull);
      expect(coordination.finalizedEventId, isNull);
    });
  });

  group('ScheduleCoordinationResponse', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'userId': 'user1',
        'votes': {'0': 'yes', '1': 'maybe'},
        'respondedAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
      };
      final response = ScheduleCoordinationResponse.fromJson('user1', json);
      expect(response.votes['0'], ScheduleCoordinationVote.yes);
      expect(response.votes['1'], ScheduleCoordinationVote.maybe);

      final roundTripped = ScheduleCoordinationResponse.fromJson(
        'user1',
        response.toJson(),
      );
      expect(roundTripped.votes, response.votes);
    });

    test('不正な投票値は無視する', () {
      final json = {
        'userId': 'user1',
        'votes': {'0': 'invalid'},
      };
      final response = ScheduleCoordinationResponse.fromJson('user1', json);
      expect(response.votes, isEmpty);
    });
  });
}
