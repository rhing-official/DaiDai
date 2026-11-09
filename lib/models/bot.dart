import 'package:cloud_firestore/cloud_firestore.dart';

/// 住人が持つbot（bot API、2026-11-09、段階2a）の1件（`bots/{botId}`）。
/// トークンのハッシュはクライアントには持たせない。トークンは作成・再発行時の
/// 応答でしか得られない。
class Bot {
  const Bot({
    required this.botId,
    required this.name,
    this.groupIds = const [],
    this.dmIds = const [],
    this.createdAt,
    this.lastUsedAt,
  });

  final String botId;
  final String name;

  /// 追加を要求した/追加された広場。
  final List<String> groupIds;

  /// 追加を要求した/追加された一対。
  final List<String> dmIds;
  final Timestamp? createdAt;
  final Timestamp? lastUsedAt;

  factory Bot.fromJson(String botId, Map<String, dynamic> json) {
    return Bot(
      botId: botId,
      name: json['name'] as String? ?? '',
      groupIds: [
        for (final id in (json['groupIds'] as List<dynamic>? ?? const []))
          id as String,
      ],
      dmIds: [
        for (final id in (json['dmIds'] as List<dynamic>? ?? const []))
          id as String,
      ],
      createdAt: json['createdAt'] as Timestamp?,
      lastUsedAt: json['lastUsedAt'] as Timestamp?,
    );
  }
}

/// 広場へのbotの追加状態（`groups/{groupId}/bots/{botId}`）。
enum GroupBotStatus { pending, active }

class GroupBot {
  const GroupBot({
    required this.botId,
    required this.name,
    required this.ownerUserId,
    required this.status,
    this.addedAt,
  });

  final String botId;
  final String name;
  final String ownerUserId;
  final GroupBotStatus status;

  /// この時刻以降のメッセージだけbotが読める（承認待ちはnull）。
  final Timestamp? addedAt;

  factory GroupBot.fromJson(String botId, Map<String, dynamic> json) {
    return GroupBot(
      botId: botId,
      name: json['name'] as String? ?? '',
      ownerUserId: json['ownerUserId'] as String? ?? '',
      status: json['status'] == 'active'
          ? GroupBotStatus.active
          : GroupBotStatus.pending,
      addedAt: json['addedAt'] as Timestamp?,
    );
  }
}

/// `createBot`・`rotateBotToken`の結果。[token]はこの応答でしか得られない。
class BotToken {
  const BotToken({required this.botId, required this.token});

  final String botId;
  final String token;
}

/// botが入る会話（広場、または一対）。callableへ渡す引数（`groupId`か`dmId`）と、
/// Firestoreの置き場所（`groups`／`directMessages`の`bots`）を決める。
class BotConversation {
  const BotConversation.group(this.id) : isDm = false;
  const BotConversation.dm(this.id) : isDm = true;

  final String id;
  final bool isDm;

  Map<String, Object?> toArgs() => {isDm ? 'dmId' : 'groupId': id};

  @override
  bool operator ==(Object other) =>
      other is BotConversation && other.id == id && other.isDm == isDm;

  @override
  int get hashCode => Object.hash(id, isDm);
}
