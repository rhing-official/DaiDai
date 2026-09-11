import 'package:cloud_firestore/cloud_firestore.dart';

/// 投票の選択肢1件（2026-09-06追加）。[mediaUrl]は画像・動画のどちらか
/// 一方を指す（[mediaType]で区別、2026-09-06に画像専用の`imageUrl`から
/// 一般化）。
class PollOption {
  const PollOption({required this.text, this.mediaUrl, this.mediaType});

  final String text;
  final String? mediaUrl;

  /// 'image' | 'video' | null（添付なし）。
  final String? mediaType;

  bool get hasImage => mediaType == 'image';
  bool get hasVideo => mediaType == 'video';

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      text: json['text'] as String,
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
  };
}

/// [Poll.options]/[Poll.optionVoteCounts]のキー形式。選択肢は配列indexで
/// 識別する（[scheduleCoordinationCandidateKey]と同じ理由。選択肢のテキストを
/// キーにすると同じ文言の選択肢が複数あった場合に衝突するため）。
String pollOptionKey(int index) => '$index';

/// 寄合単位の投票（2026-09-06追加。`directMessages/{dmId}/rooms/{roomId}/
/// polls/{pollId}`または`groups/{groupId}/rooms/{roomId}/polls/{pollId}`）。
///
/// 作成時に「選択肢」（自由記述の選択肢、画像添付・複数選択可・選択肢の
/// 追加を許可に対応）と「○×」（選択肢入力を省き固定で○/×の2択にする）の
/// 2モードを選べるが、どちらもデータ形状は完全に同一（[options]が2件以上の
/// Map）で、UI側の作成ダイアログでのみ分岐する（`poll_form_dialog.dart`参照）。
///
/// 回答は[PollResponse]（`responses`サブコレクション）に分離。投票は一度きり
/// （変更不可、firestore.rulesで`update`/`delete`とも`if false`）。
/// [responseCount]/[optionVoteCounts]はCloud Functions（`onDmPollResponseCreated`/
/// `onGroupPollResponseCreated`、Admin SDK経由）だけが書き込む非正規化フィールド
/// で、クライアントの`update`では一切触れない。これにより匿名投票
/// （[anonymous]）でも、`responses`サブコレクションの読み取りを本人のみに
/// 絞りつつ、選択肢ごとの得票数だけは全員に安全に見せられる。
class Poll {
  const Poll({
    required this.pollId,
    required this.roomId,
    required this.question,
    required this.options,
    required this.createdBy,
    this.createdAt,
    this.deadline,
    this.allowMultipleChoices = false,
    this.anonymous = false,
    this.allowAddingOptions = false,
    this.responseCount = 0,
    this.optionVoteCounts = const {},
    this.bannerHiddenFor = const [],
  });

  final String pollId;
  final String roomId;
  final String question;

  /// [pollOptionKey] -> 選択肢。
  final Map<String, PollOption> options;
  final String createdBy;
  final Timestamp? createdAt;

  /// 回答期限。[ScheduleCoordination.deadline]と同じ意味論（nullなら期限
  /// なし、過ぎると新規投票がfirestore.rulesで拒否される）。
  final Timestamp? deadline;

  final bool allowMultipleChoices;

  /// trueの場合、作成者を含め誰にも「誰が何に投票したか」を見せない
  /// （集計数のみ全員に見える）。
  final bool anonymous;

  /// trueの場合、参加者が末尾に選択肢を追加できる（firestore.rules参照）。
  final bool allowAddingOptions;

  /// 回答済み住人の人数（非正規化カウンタ、Cloud Functionsのみ更新）。
  final int responseCount;

  /// [pollOptionKey] -> 得票数（非正規化カウンタ、Cloud Functionsのみ更新）。
  final Map<String, int> optionVoteCounts;

  /// この投票を`ChatTaskBanner`（`task_banner.dart`）から個人的に非表示に
  /// した住人のuserId一覧（2026-09-10追加、`CalendarEvent.bannerHiddenFor`と
  /// 同じ設計）。
  final List<String> bannerHiddenFor;

  /// [options]を配列indexの昇順に並べたキー一覧。
  List<String> get orderedOptionKeys =>
      options.keys.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

  int voteCountFor(String key) => optionVoteCounts[key] ?? 0;

  bool get isClosed {
    final deadlineDate = deadline?.toDate();
    return deadlineDate != null && DateTime.now().isAfter(deadlineDate);
  }

  factory Poll.fromJson(String pollId, Map<String, dynamic> json) {
    final rawOptions = json['options'] as Map? ?? const {};
    final options = <String, PollOption>{
      for (final entry in rawOptions.entries)
        entry.key as String: PollOption.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
    final rawVoteCounts = json['optionVoteCounts'] as Map? ?? const {};
    final optionVoteCounts = <String, int>{
      for (final entry in rawVoteCounts.entries)
        entry.key as String: entry.value as int,
    };
    return Poll(
      pollId: pollId,
      roomId: json['roomId'] as String,
      question: json['question'] as String,
      options: options,
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as Timestamp?,
      deadline: json['deadline'] as Timestamp?,
      allowMultipleChoices: json['allowMultipleChoices'] as bool? ?? false,
      anonymous: json['anonymous'] as bool? ?? false,
      allowAddingOptions: json['allowAddingOptions'] as bool? ?? false,
      responseCount: json['responseCount'] as int? ?? 0,
      optionVoteCounts: optionVoteCounts,
      bannerHiddenFor: (json['bannerHiddenFor'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  /// [optionVoteCounts]は含めない。Cloud Functions専用フィールドであり
  /// クライアントからは常に書かないことをコード上でも明示するため。
  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'question': question,
    'options': options.map((key, option) => MapEntry(key, option.toJson())),
    'createdBy': createdBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'deadline': deadline,
    'allowMultipleChoices': allowMultipleChoices,
    'anonymous': anonymous,
    'allowAddingOptions': allowAddingOptions,
    'responseCount': responseCount,
    'bannerHiddenFor': bannerHiddenFor,
  };
}
