import 'package:flutter_riverpod/flutter_riverpod.dart';

/// チャット内で現在再生中の音声添付メッセージid（無ければnull）。
/// 複数の音声添付が同時に再生されないよう、新しい再生開始時にこの値を
/// 書き換え、各音声プレビュー行が自分以外の値になったら一時停止する
/// （`lib/features/chat/chat_screen.dart`の`_FileAttachmentBlock`参照、
/// 2026-09-12追加）。
class PlayingAudioMessageIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setPlaying(String? messageId) => state = messageId;
}

final playingAudioMessageIdProvider =
    NotifierProvider<PlayingAudioMessageIdNotifier, String?>(
      PlayingAudioMessageIdNotifier.new,
    );
