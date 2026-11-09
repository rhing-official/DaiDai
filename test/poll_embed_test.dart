import 'package:daidai/models/poll.dart';
import 'package:daidai/utils/poll_embed.dart';
import 'package:flutter_test/flutter_test.dart';

Poll _poll(List<PollOption> options) => Poll(
  pollId: 'p',
  roomId: 'r',
  question: 'q',
  options: {for (var i = 0; i < options.length; i++) '$i': options[i]},
  createdBy: 'u',
);

void main() {
  group('shouldCollapsePoll', () {
    test('テキストだけの4件までは折りたたまない', () {
      final options = [for (var i = 0; i < 4; i++) PollOption(text: '$i')];
      expect(shouldCollapsePoll(_poll(options)), isFalse);
    });

    test('選択肢が5件以上なら折りたたむ', () {
      final options = [for (var i = 0; i < 5; i++) PollOption(text: '$i')];
      expect(shouldCollapsePoll(_poll(options)), isTrue);
    });

    test('画像・動画付きの選択肢があっても、4件までは折りたたまない（メッセージ画面から答えられる）', () {
      for (final type in ['image', 'video']) {
        final options = [
          const PollOption(text: 'a'),
          PollOption(text: 'b', mediaUrl: 'https://e/x', mediaType: type),
        ];
        expect(shouldCollapsePoll(_poll(options)), isFalse, reason: type);
      }
    });

    test('画像付きでも5件以上なら折りたたむ', () {
      final options = [
        for (var i = 0; i < 5; i++)
          PollOption(text: '$i', mediaUrl: 'https://e/x', mediaType: 'image'),
      ];
      expect(shouldCollapsePoll(_poll(options)), isTrue);
    });
  });
}
