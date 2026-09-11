import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/poll.dart';
import '../models/poll_response.dart';
import '../utils/attachment_upload.dart';

/// 選択肢1件分の作成時ドラフト（永続化する[PollOption]と異なり、アップロード
/// 前の画像・動画バイトを保持する。[PollRepository.createPoll]/
/// [PollRepository.addOption]専用、2026-09-06追加）。
class PollOptionDraft {
  const PollOptionDraft({
    required this.text,
    this.mediaBytes,
    this.mediaFileName,
    this.mediaType,
  });

  final String text;
  final Uint8List? mediaBytes;
  final String? mediaFileName;

  /// 'image' | 'video' | null（添付なし）。
  final String? mediaType;
}

/// 投票機能のRepository（2026-09-06追加）。`ScheduleCoordinationRepository`と
/// 同じく「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した
/// 薄い実装。
abstract class PollRepository {
  Stream<List<Poll>> watchPolls({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  /// 単発で1件だけ取得する（存在しなければnull）。メッセージ画面の投票開始
  /// 通知メッセージをタップした際、そのpollIdから取得して投票ダイアログを
  /// 開くために使う。
  Future<Poll?> getPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  });

  /// 1件のPollドキュメントを購読する（存在しなければnullを流す）。
  /// [responseCount]/[Poll.optionVoteCounts]はCloud Functionsが投票の少し後に
  /// 非同期で更新するため、投票詳細ダイアログを開いたままにしても最新の
  /// 集計・選択肢の追加が反映されるよう、`getPoll`（単発取得）ではなく
  /// こちらを表示に使う。
  Stream<Poll?> watchPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  });

  /// この寄合の参加者一覧（一対は`participants`、広場は`memberIds`）。
  Future<List<String>> participantIds({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  /// [options]は2件以上。画像付きの選択肢があれば先にアップロードしてから
  /// 書き込む。
  Future<Poll> createPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String question,
    required List<PollOptionDraft> options,
    required String createdBy,
    DateTime? deadline,
    bool allowMultipleChoices = false,
    bool anonymous = false,
    bool allowAddingOptions = false,
  });

  /// 選択肢を末尾に1件追加する（`Poll.allowAddingOptions`がtrueかつ未締切の
  /// 場合のみ、firestore.rules参照）。[currentOptionCount]は末尾キーの算出用。
  Future<void> addOption({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required PollOptionDraft option,
    required int currentOptionCount,
  });

  /// 投票を削除する（作成者のみ、firestore.rules参照）。
  Future<void> deletePoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  });

  /// 自分の回答を投稿する（一度きり。2回目以降はfirestore.rulesが
  /// permission-deniedを返す。`Poll.allowMultipleChoices`がfalseの投票では
  /// [selectedOptionKeys]は1件のみ許可される）。
  Future<void> castVote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
    required List<String> selectedOptionKeys,
  });

  /// 自分の回答だけを購読する（匿名投票でも常に読める自分のドキュメント。
  /// 「投票済みか」の判定にタスクバナー・詳細ダイアログ双方が使う）。
  Stream<PollResponse?> watchMyResponse({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
  });

  /// 全員の回答一覧を購読する（非匿名投票の詳細表示専用。匿名投票では
  /// firestore.rulesが自分以外を拒否するため、呼び出し側は`Poll.anonymous`で
  /// 使い分けること）。
  Stream<List<PollResponse>> watchResponses({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  });

  /// この投票を`ChatTaskBanner`から自分だけ非表示にする（2026-09-10追加）。
  /// 投票本体は削除せず、投票一覧（`poll_popup_content.dart`）には引き続き
  /// 表示される（[Poll.bannerHiddenFor]参照）。
  Future<void> hideFromBanner({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
  });
}

class FirestorePollRepository implements PollRepository {
  FirestorePollRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> _roomsCollection(
    bool isDm,
    String conversationId,
  ) {
    final topLevel = isDm ? 'directMessages' : 'groups';
    return _firestore
        .collection(topLevel)
        .doc(conversationId)
        .collection('rooms');
  }

  CollectionReference<Map<String, dynamic>> _pollsCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).collection('polls');
  }

  DocumentReference<Map<String, dynamic>> _pollRef({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) {
    return _pollsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(pollId);
  }

  CollectionReference<Map<String, dynamic>> _responsesCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) {
    return _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).collection('responses');
  }

  @override
  Future<List<String>> participantIds({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) async {
    final roomDoc = await _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).get();
    final data = roomDoc.data();
    if (data == null) return const [];
    final field = isDm ? 'participants' : 'memberIds';
    return (data[field] as List?)?.cast<String>() ?? const [];
  }

  @override
  Stream<List<Poll>> watchPolls({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _pollsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Poll.fromJson(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Future<Poll?> getPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) async {
    final doc = await _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).get();
    final data = doc.data();
    if (data == null) return null;
    return Poll.fromJson(doc.id, data);
  }

  @override
  Stream<Poll?> watchPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) {
    return _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return Poll.fromJson(doc.id, data);
    });
  }

  String _storagePathPrefix(bool isDm, String conversationId) =>
      'pollOptionMedia/${isDm ? 'dm' : 'group'}/$conversationId';

  Future<PollOption> _buildOption(
    PollOptionDraft draft,
    String storagePathPrefix,
    String pollId,
    int index,
  ) async {
    final mediaBytes = draft.mediaBytes;
    final mediaType = draft.mediaType;
    if (mediaBytes == null || mediaType == null) {
      return PollOption(text: draft.text);
    }
    final defaultFileName = mediaType == 'video'
        ? 'option_$index.mp4'
        : 'option_$index.jpg';
    final metadata = await uploadMessageAttachment(
      storage: _storage,
      storagePathPrefix: storagePathPrefix,
      attachmentId: '${pollId}_$index',
      bytes: mediaBytes,
      fileName: draft.mediaFileName ?? defaultFileName,
      contentType: mediaType,
    );
    return PollOption(
      text: draft.text,
      mediaUrl: metadata.url,
      mediaType: mediaType,
    );
  }

  @override
  Future<Poll> createPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String question,
    required List<PollOptionDraft> options,
    required String createdBy,
    DateTime? deadline,
    bool allowMultipleChoices = false,
    bool anonymous = false,
    bool allowAddingOptions = false,
  }) async {
    final ref = _pollsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final storagePathPrefix = _storagePathPrefix(isDm, conversationId);
    final builtOptions = <String, PollOption>{};
    for (var i = 0; i < options.length; i++) {
      builtOptions[pollOptionKey(i)] = await _buildOption(
        options[i],
        storagePathPrefix,
        ref.id,
        i,
      );
    }
    final poll = Poll(
      pollId: ref.id,
      roomId: roomId,
      question: question,
      options: builtOptions,
      createdBy: createdBy,
      deadline: deadline != null ? Timestamp.fromDate(deadline) : null,
      allowMultipleChoices: allowMultipleChoices,
      anonymous: anonymous,
      allowAddingOptions: allowAddingOptions,
    );
    await ref.set(poll.toJson());
    return poll;
  }

  @override
  Future<void> addOption({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required PollOptionDraft option,
    required int currentOptionCount,
  }) async {
    final built = await _buildOption(
      option,
      _storagePathPrefix(isDm, conversationId),
      pollId,
      currentOptionCount,
    );
    await _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).update({'options.${pollOptionKey(currentOptionCount)}': built.toJson()});
  }

  @override
  Future<void> deletePoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) {
    return _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).delete();
  }

  @override
  Future<void> castVote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
    required List<String> selectedOptionKeys,
  }) {
    return _responsesCollection(
          isDm: isDm,
          conversationId: conversationId,
          roomId: roomId,
          pollId: pollId,
        )
        .doc(userId)
        .set(
          PollResponse(
            userId: userId,
            selectedOptionKeys: selectedOptionKeys,
          ).toJson(),
        );
  }

  @override
  Stream<PollResponse?> watchMyResponse({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
  }) {
    return _responsesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).doc(userId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return PollResponse.fromJson(doc.id, data);
    });
  }

  @override
  Stream<List<PollResponse>> watchResponses({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) {
    return _responsesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PollResponse.fromJson(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Future<void> hideFromBanner({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
  }) {
    return _pollRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      pollId: pollId,
    ).update({
      'bannerHiddenFor': FieldValue.arrayUnion([userId]),
    });
  }
}
