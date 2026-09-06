import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/poll.dart';
import 'package:daidai/models/poll_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pollOptionKey', () {
    test('配列indexを文字列化するだけの単純なキー', () {
      expect(pollOptionKey(0), '0');
      expect(pollOptionKey(3), '3');
    });
  });

  group('Poll', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'roomId': 'room1',
        'question': '飲み会の場所は？',
        'options': {
          '0': {'text': '居酒屋', 'mediaUrl': null, 'mediaType': null},
          '1': {
            'text': '焼肉',
            'mediaUrl': 'https://example.com/yakiniku.png',
            'mediaType': 'image',
          },
        },
        'createdBy': 'user1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
        'deadline': Timestamp.fromDate(DateTime(2026, 9, 10)),
        'allowMultipleChoices': true,
        'anonymous': true,
        'allowAddingOptions': true,
        'responseCount': 2,
        'optionVoteCounts': {'0': 1, '1': 1},
      };
      final poll = Poll.fromJson('poll1', json);

      expect(poll.pollId, 'poll1');
      expect(poll.question, '飲み会の場所は？');
      expect(poll.options, hasLength(2));
      expect(poll.options['0']?.text, '居酒屋');
      expect(poll.options['1']?.mediaUrl, 'https://example.com/yakiniku.png');
      expect(poll.options['1']?.hasImage, isTrue);
      expect(poll.allowMultipleChoices, isTrue);
      expect(poll.anonymous, isTrue);
      expect(poll.allowAddingOptions, isTrue);
      expect(poll.responseCount, 2);
      expect(poll.voteCountFor('0'), 1);
      expect(poll.voteCountFor('1'), 1);
      expect(poll.orderedOptionKeys, ['0', '1']);

      final roundTripped = Poll.fromJson('poll1', poll.toJson());
      expect(roundTripped.question, poll.question);
      expect(roundTripped.options.keys, poll.options.keys);
      expect(roundTripped.deadline, poll.deadline);
      // optionVoteCountsはCloud Functions専用フィールドのためtoJsonに含めない
      // （クライアントからは常に書かないことをコード上でも明示するため）。
      expect(roundTripped.optionVoteCounts, isEmpty);
    });

    test('optionVoteCounts省略時は0を返す', () {
      final poll = Poll.fromJson('poll1', {
        'roomId': 'room1',
        'question': 'Q',
        'options': {
          '0': {'text': 'A'},
          '1': {'text': 'B'},
        },
        'createdBy': 'user1',
      });
      expect(poll.voteCountFor('0'), 0);
      expect(poll.responseCount, 0);
      expect(poll.allowMultipleChoices, isFalse);
      expect(poll.anonymous, isFalse);
      expect(poll.allowAddingOptions, isFalse);
    });

    test('isClosedはdeadlineが過去のときのみtrue', () {
      final past = Poll(
        pollId: 'p1',
        roomId: 'room1',
        question: 'Q',
        options: const {},
        createdBy: 'user1',
        deadline: Timestamp.fromDate(DateTime(2000, 1, 1)),
      );
      final future = Poll(
        pollId: 'p2',
        roomId: 'room1',
        question: 'Q',
        options: const {},
        createdBy: 'user1',
        deadline: Timestamp.fromDate(DateTime(2100, 1, 1)),
      );
      final noDeadline = Poll(
        pollId: 'p3',
        roomId: 'room1',
        question: 'Q',
        options: const {},
        createdBy: 'user1',
      );
      expect(past.isClosed, isTrue);
      expect(future.isClosed, isFalse);
      expect(noDeadline.isClosed, isFalse);
    });

    test('orderedOptionKeysは配列indexの昇順', () {
      final poll = Poll.fromJson('poll1', {
        'roomId': 'room1',
        'question': 'Q',
        'options': {
          '10': {'text': 'K'},
          '2': {'text': 'C'},
          '1': {'text': 'B'},
        },
        'createdBy': 'user1',
      });
      expect(poll.orderedOptionKeys, ['1', '2', '10']);
    });
  });

  group('PollResponse', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'userId': 'user1',
        'selectedOptionKeys': ['0', '1'],
        'respondedAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
      };
      final response = PollResponse.fromJson('user1', json);
      expect(response.selectedOptionKeys, ['0', '1']);

      final roundTripped = PollResponse.fromJson('user1', response.toJson());
      expect(roundTripped.selectedOptionKeys, response.selectedOptionKeys);
    });

    test('selectedOptionKeys省略時は空リスト', () {
      final response = PollResponse.fromJson('user1', {'userId': 'user1'});
      expect(response.selectedOptionKeys, isEmpty);
    });
  });
}
