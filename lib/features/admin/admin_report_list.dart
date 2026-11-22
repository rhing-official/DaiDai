import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/report.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/style_choice_chip.dart';

/// 管理画面の通報タブ（2026-11-22追加）。住人が出した通報（メッセージ・住人・広場）を
/// 一覧し、証拠を見て、問題なし／対応済みにする。Appleのガイドライン1.2が求める
/// 「通報への迅速な対応」の受け皿で、未対応を一番上に出す。
/// アカウントの停止は、住人一覧の既存の操作（`suspendUserAccount`）と同じ関数を使う。
class AdminReportListSection extends ConsumerStatefulWidget {
  const AdminReportListSection({super.key});

  @override
  ConsumerState<AdminReportListSection> createState() =>
      _AdminReportListSectionState();
}

enum _ReportFilter {
  open('未対応'),
  resolved('対応済み'),
  all('全て');

  const _ReportFilter(this.label);
  final String label;
}

String _targetTypeLabel(ReportTargetType? type) => switch (type) {
  ReportTargetType.message => 'メッセージ',
  ReportTargetType.user => '住人',
  ReportTargetType.group => '広場',
  null => '不明',
};

String _reasonLabel(ReportReason? reason) => switch (reason) {
  ReportReason.harassment => '嫌がらせ・誹謗中傷',
  ReportReason.spam => 'スパム・宣伝',
  ReportReason.sexual => '性的な内容',
  ReportReason.violence => '暴力・自傷をあおる内容',
  ReportReason.illegal => '違法な内容',
  ReportReason.impersonation => 'なりすまし',
  ReportReason.other => 'その他',
  null => '不明',
};

String _formatTime(DateTime? time) {
  if (time == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}/${two(time.month)}/${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

String _seed(String? seed) => seed == null ? '（不明）' : '@$seed';

class _AdminReportListSectionState
    extends ConsumerState<AdminReportListSection> {
  List<AdminReport>? _reports;
  Object? _error;
  bool _loading = false;
  _ReportFilter _filter = _ReportFilter.open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await ref.read(reportRepositoryProvider).listReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<AdminReport> get _visible {
    final all = _reports ?? const <AdminReport>[];
    return switch (_filter) {
      _ReportFilter.open => all.where((r) => !r.isResolved).toList(),
      _ReportFilter.resolved => all.where((r) => r.isResolved).toList(),
      _ReportFilter.all => all,
    };
  }

  Future<void> _open(AdminReport report) async {
    final changed = await showAppDialog<bool>(
      context: context,
      builder: (_) => _ReportDetailDialog(report: report),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final openCount = (_reports ?? const <AdminReport>[])
        .where((r) => !r.isResolved)
        .length;
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _ReportFilter.values)
                      StyleChoiceChip(
                        uiStyle: uiStyle,
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                        labelBuilder: (fg) => Text(
                          f == _ReportFilter.open && _reports != null
                              ? '${f.label}（$openCount）'
                              : f.label,
                          style: TextStyle(color: fg),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '再読み込み',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _error != null
                ? Center(child: Text('通報を読み込めませんでした: $_error'))
                : _reports == null
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? const Center(child: Text('該当する通報はありません'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final r = visible[index];
                      return ListTile(
                        leading: Icon(
                          r.isResolved
                              ? Icons.check_circle_outline
                              : Icons.flag_outlined,
                        ),
                        title: Text(
                          '${_targetTypeLabel(r.targetType)}｜${_reasonLabel(r.reason)}',
                        ),
                        subtitle: Text(
                          '${_formatTime(r.createdAt)}　'
                          '通報者 ${_seed(r.reporterSeed)} → 対象 ${_seed(r.targetSeed)}',
                        ),
                        onTap: () => _open(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 後戻りしにくい確定ボタンの固定の濃い赤（CLAUDE.mdのボタン配色規約）。
final _destructiveStyle = FilledButton.styleFrom(
  backgroundColor: Colors.red.shade700,
  foregroundColor: Colors.white,
);

class _ReportDetailDialog extends ConsumerStatefulWidget {
  const _ReportDetailDialog({required this.report});

  final AdminReport report;

  @override
  ConsumerState<_ReportDetailDialog> createState() =>
      _ReportDetailDialogState();
}

class _ReportDetailDialogState extends ConsumerState<_ReportDetailDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _resolve(ReportResolution resolution) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(reportRepositoryProvider)
          .resolveReport(
            widget.report.reportId,
            resolution: resolution,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '処理できませんでした: $error';
      });
    }
  }

  /// 通報された住人のアカウントを停止し、対応済みにする。停止は違反への対応
  /// （CLAUDE.md「停止と削除の使い分け」）。
  Future<void> _suspendAndResolve() async {
    final targetUserId = widget.report.targetUserId;
    if (targetUserId == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        final title = const Text('アカウントを停止しますか？');
        final content = Text(
          '${_seed(widget.report.targetSeed)} のアカウントを停止し、この通報を対応済みにします。'
          '停止中の住人は使えなくなります。解除は住人一覧から行えます。',
        );
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: _destructiveStyle,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('停止する'),
          ),
        ];
        return ref.read(appUiStyleProvider) == AppUiStyle.glass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .setAccountSuspended(targetUserId, true);
      await ref
          .read(reportRepositoryProvider)
          .resolveReport(
            widget.report.reportId,
            resolution: ReportResolution.actioned,
            note: _note.text.trim().isEmpty ? 'アカウントを停止' : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '停止できませんでした: $error';
      });
      showAutoDismissBanner(context, message: '停止できませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final title = Text(
      '${_targetTypeLabel(r.targetType)}の通報｜${_reasonLabel(r.reason)}',
    );
    final content = SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日時: ${_formatTime(r.createdAt)}'),
            Text('通報者: ${_seed(r.reporterSeed)}'),
            Text('対象: ${_seed(r.targetSeed)}'),
            if (r.groupName != null && r.groupName!.isNotEmpty)
              Text('広場: ${r.groupName}'),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                '通報者の補足',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(r.note),
            ],
            if (r.evidenceMessages.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '証拠（対象のメッセージと前後）',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final m in r.evidenceMessages) _EvidenceTile(message: m),
            ],
            if (r.isResolved) ...[
              const SizedBox(height: 12),
              Text(
                '処理済み: ${r.resolution == ReportResolution.dismissed ? '問題なし' : '対応済み'}'
                '${(r.resolutionNote ?? '').isEmpty ? '' : '（${r.resolutionNote}）'}',
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(hintText: '処理のメモ（任意）'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('閉じる'),
      ),
      if (!r.isResolved) ...[
        TextButton(
          onPressed: _busy ? null : () => _resolve(ReportResolution.dismissed),
          child: const Text('問題なし'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _resolve(ReportResolution.actioned),
          child: const Text('対応済み'),
        ),
        if (r.targetUserId != null && r.targetType != ReportTargetType.group)
          FilledButton(
            style: _destructiveStyle,
            onPressed: _busy ? null : _suspendAndResolve,
            child: const Text('アカウントを停止'),
          ),
      ],
    ];
    return ref.watch(appUiStyleProvider) == AppUiStyle.glass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.message});

  final ReportEvidenceMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attachments = message.attachmentNames.where((n) => n.isNotEmpty);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: message.isTarget
            ? scheme.errorContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${message.isTarget ? '【対象】' : ''}${_seed(message.senderRhingSeed)}　'
            '${_formatTime(message.sentAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (message.content.isNotEmpty) SelectableText(message.content),
          if (attachments.isNotEmpty)
            Text(
              '添付: ${attachments.join('、')}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
