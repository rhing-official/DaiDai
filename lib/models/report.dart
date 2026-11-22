/// 通報の対象の種類（`functions/src/reports.ts`の`REPORT_TARGET_TYPES`と一致させる）。
enum ReportTargetType {
  message,
  user,
  group;

  static ReportTargetType? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// 通報の理由（`functions/src/reports.ts`の`REPORT_REASONS`と一致させる）。
enum ReportReason {
  harassment,
  spam,
  sexual,
  violence,
  illegal,
  impersonation,
  other;

  static ReportReason? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// 運営の処理の結果。`dismissed`＝問題なし、`actioned`＝対応済み。
enum ReportResolution { dismissed, actioned }

/// 通報の補足の最大文字数（サーバーの`REPORT_NOTE_MAX_LENGTH`と一致させる）。
const kReportNoteMaxLength = 500;

/// 証拠として複写されたメッセージ1件（管理画面で表示する）。
class ReportEvidenceMessage {
  const ReportEvidenceMessage({
    required this.messageId,
    required this.senderId,
    required this.senderRhingSeed,
    required this.content,
    required this.contentType,
    required this.sentAt,
    required this.attachmentNames,
    required this.isTarget,
  });

  final String messageId;
  final String senderId;
  final String? senderRhingSeed;
  final String content;
  final String contentType;
  final DateTime? sentAt;
  final List<String> attachmentNames;

  /// 通報の対象になったメッセージか。
  final bool isTarget;

  factory ReportEvidenceMessage.fromJson(Map<String, dynamic> json) {
    final sentAt = json['sentAt'] as String?;
    return ReportEvidenceMessage(
      messageId: json['messageId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderRhingSeed: json['senderRhingSeed'] as String?,
      content: json['content'] as String? ?? '',
      contentType: json['contentType'] as String? ?? 'text',
      sentAt: sentAt == null ? null : DateTime.tryParse(sentAt)?.toLocal(),
      attachmentNames: [
        for (final a in (json['attachments'] as List? ?? const []))
          (a as Map)['fileName'] as String? ?? '',
      ],
      isTarget: json['isTarget'] as bool? ?? false,
    );
  }
}

/// 運営が見る通報1件（`listReports`の戻り値）。
class AdminReport {
  const AdminReport({
    required this.reportId,
    required this.targetType,
    required this.reason,
    required this.note,
    required this.reporterId,
    required this.reporterSeed,
    required this.targetUserId,
    required this.targetSeed,
    required this.evidenceMessages,
    required this.groupName,
    required this.isResolved,
    required this.createdAt,
    required this.resolution,
    required this.resolutionNote,
  });

  final String reportId;
  final ReportTargetType? targetType;
  final ReportReason? reason;
  final String note;
  final String reporterId;
  final String? reporterSeed;

  /// 通報された住人。メッセージは送信者、住人はその住人、広場は長。
  final String? targetUserId;
  final String? targetSeed;
  final List<ReportEvidenceMessage> evidenceMessages;

  /// 広場の通報・広場の会話のメッセージの通報での、広場の名前。
  final String? groupName;
  final bool isResolved;
  final DateTime? createdAt;
  final ReportResolution? resolution;
  final String? resolutionNote;

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    final evidence = Map<String, dynamic>.from(json['evidence'] as Map? ?? {});
    final group = evidence['group'] as Map?;
    final conversation = evidence['conversation'] as Map?;
    final createdAt = json['createdAt'] as String?;
    final resolution = json['resolution'] as String?;
    return AdminReport(
      reportId: json['reportId'] as String,
      targetType: ReportTargetType.fromName(json['targetType'] as String?),
      reason: ReportReason.fromName(json['reason'] as String?),
      note: json['note'] as String? ?? '',
      reporterId: json['reporterId'] as String? ?? '',
      reporterSeed: json['reporterSeed'] as String?,
      targetUserId: json['targetUserId'] as String?,
      targetSeed: json['targetSeed'] as String?,
      evidenceMessages: [
        for (final m in (evidence['messages'] as List? ?? const []))
          ReportEvidenceMessage.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      groupName: (group?['name'] ?? conversation?['groupName']) as String?,
      isResolved: json['status'] == 'resolved',
      createdAt: createdAt == null
          ? null
          : DateTime.tryParse(createdAt)?.toLocal(),
      resolution: resolution == null
          ? null
          : ReportResolution.values.asNameMap()[resolution],
      resolutionNote: json['resolutionNote'] as String?,
    );
  }
}
