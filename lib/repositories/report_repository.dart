import '../models/report.dart';
import '../services/app_functions.dart';

/// 通報の送信（住人）と、処理（運営）を扱うリポジトリ。
///
/// 通報は`reports`に保存するが、書き込みはCloud Functions（Admin SDK）だけで、
/// クライアントは直接読み書きしない（証拠の複写をサーバーが行い、申告を信用しない為）。
abstract class ReportRepository {
  /// メッセージを通報する。一対の会話は[dmId]、広場の会話は[groupId]を渡す。
  /// 既に同じ対象を通報済みなら`true`を返す（新しく作らない）。
  Future<bool> reportMessage({
    String? dmId,
    String? groupId,
    required String roomId,
    required String messageId,
    required ReportReason reason,
    String note = '',
  });

  Future<bool> reportUser({
    required String targetUserId,
    required ReportReason reason,
    String note = '',
  });

  Future<bool> reportGroup({
    required String groupId,
    required ReportReason reason,
    String note = '',
  });

  /// 運営向け: 通報の一覧（新しい順、最大200件）。
  Future<List<AdminReport>> listReports();

  /// 運営向け: 通報を処理済みにする。
  Future<void> resolveReport(
    String reportId, {
    required ReportResolution resolution,
    String note = '',
  });
}

class FirebaseReportRepository implements ReportRepository {
  FirebaseReportRepository({AppFunctions? functions})
    : _functions =
          functions ?? AppFunctions.instanceFor(region: 'asia-northeast1');

  final AppFunctions _functions;

  Future<bool> _submit(Map<String, dynamic> params) async {
    final result = await _functions.httpsCallable('submitReport').call(params);
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['alreadyReported'] == true;
  }

  @override
  Future<bool> reportMessage({
    String? dmId,
    String? groupId,
    required String roomId,
    required String messageId,
    required ReportReason reason,
    String note = '',
  }) => _submit({
    'targetType': 'message',
    'reason': reason.name,
    'note': note,
    'roomId': roomId,
    'messageId': messageId,
    'dmId': ?dmId,
    'groupId': ?groupId,
  });

  @override
  Future<bool> reportUser({
    required String targetUserId,
    required ReportReason reason,
    String note = '',
  }) => _submit({
    'targetType': 'user',
    'reason': reason.name,
    'note': note,
    'targetUserId': targetUserId,
  });

  @override
  Future<bool> reportGroup({
    required String groupId,
    required ReportReason reason,
    String note = '',
  }) => _submit({
    'targetType': 'group',
    'reason': reason.name,
    'note': note,
    'groupId': groupId,
  });

  @override
  Future<List<AdminReport>> listReports() async {
    final result = await _functions.httpsCallable('listReports').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return [
      for (final r in data['reports'] as List)
        AdminReport.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  @override
  Future<void> resolveReport(
    String reportId, {
    required ReportResolution resolution,
    String note = '',
  }) async {
    await _functions.httpsCallable('resolveReport').call({
      'reportId': reportId,
      'resolution': resolution.name,
      'note': note,
    });
  }
}
