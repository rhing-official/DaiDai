import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/report.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/app_functions.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/toggles/app_radio.dart';

/// 通報の対象。ダイアログの見出しと、送信する先を決める。
sealed class ReportTarget {
  const ReportTarget();
}

/// メッセージ。一対の会話は[dmId]、広場の会話は[groupId]を渡す。
class ReportMessageTarget extends ReportTarget {
  const ReportMessageTarget({
    this.dmId,
    this.groupId,
    required this.roomId,
    required this.messageId,
  }) : assert((dmId == null) != (groupId == null));

  final String? dmId;
  final String? groupId;
  final String roomId;
  final String messageId;
}

class ReportUserTarget extends ReportTarget {
  const ReportUserTarget(this.userId);

  final String userId;
}

class ReportGroupTarget extends ReportTarget {
  const ReportGroupTarget(this.groupId);

  final String groupId;
}

/// 通報のダイアログを開く（2026-11-22）。メッセージ・住人・広場で共通。
/// 理由（必須）と補足（任意）を入れて送る。結果は、ダイアログの中身を「受け付けました」に
/// 切り替えて伝える（成功の通知を別に出さない方針のため、操作の流れの一部として見せる）。
/// `ChatScreen`・プロフィール・設定の各画面のどこからでも、同じ形で呼べる。
Future<void> showReportDialog(BuildContext context, ReportTarget target) {
  return showAppDialog<void>(
    context: context,
    builder: (context) => ReportDialog(target: target),
  );
}

class ReportDialog extends ConsumerStatefulWidget {
  const ReportDialog({required this.target, super.key});

  final ReportTarget target;

  @override
  ConsumerState<ReportDialog> createState() => _ReportDialogState();
}

enum _Phase { form, sent, alreadySent }

class _ReportDialogState extends ConsumerState<ReportDialog> {
  final _note = TextEditingController();
  ReportReason? _reason;
  _Phase _phase = _Phase.form;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _titleOf(Strings strings) => switch (widget.target) {
    ReportMessageTarget() => strings.reportTitleMessage,
    ReportUserTarget() => strings.reportTitleUser,
    ReportGroupTarget() => strings.reportTitleGroup,
  };

  String _reasonLabel(Strings strings, ReportReason reason) => switch (reason) {
    ReportReason.harassment => strings.reportReasonHarassment,
    ReportReason.spam => strings.reportReasonSpam,
    ReportReason.sexual => strings.reportReasonSexual,
    ReportReason.violence => strings.reportReasonViolence,
    ReportReason.illegal => strings.reportReasonIllegal,
    ReportReason.impersonation => strings.reportReasonImpersonation,
    ReportReason.other => strings.reportReasonOther,
  };

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    final strings = ref.read(appStringsProvider);
    setState(() {
      _sending = true;
      _error = null;
    });
    final repository = ref.read(reportRepositoryProvider);
    final note = _note.text.trim();
    try {
      final already = switch (widget.target) {
        ReportMessageTarget(
          :final dmId,
          :final groupId,
          :final roomId,
          :final messageId,
        ) =>
          await repository.reportMessage(
            dmId: dmId,
            groupId: groupId,
            roomId: roomId,
            messageId: messageId,
            reason: reason,
            note: note,
          ),
        ReportUserTarget(:final userId) => await repository.reportUser(
          targetUserId: userId,
          reason: reason,
          note: note,
        ),
        ReportGroupTarget(:final groupId) => await repository.reportGroup(
          groupId: groupId,
          reason: reason,
          note: note,
        ),
      };
      if (!mounted) return;
      setState(() {
        _phase = already ? _Phase.alreadySent : _Phase.sent;
        _sending = false;
      });
    } on AppFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.code == 'resource-exhausted'
            ? strings.reportTooMany
            : strings.reportFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = strings.reportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final ui = ref.watch(appUiStyleProvider);
    final isGekiga = ui == AppUiStyle.gekiga;
    final isGlass = ui == AppUiStyle.glass;

    final Widget title;
    final Widget content;
    final List<Widget> actions;

    if (_phase == _Phase.form) {
      title = Text(_titleOf(strings));
      final noteField = isGekiga
          ? GekigaTextField(
              controller: _note,
              hintText: strings.reportNoteHint,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kReportNoteMaxLength),
              ],
            )
          : TextField(
              controller: _note,
              maxLines: 3,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kReportNoteMaxLength),
              ],
              decoration: InputDecoration(hintText: strings.reportNoteHint),
            );
      content = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.reportIntro, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Text(
              strings.reportReasonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in ReportReason.values)
                    AppRadioListTile<ReportReason>(
                      value: reason,
                      dense: true,
                      title: Text(_reasonLabel(strings, reason)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            noteField,
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      );
      actions = [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        // 後戻りしにくい操作の確定ボタンは、鮮やかな赤（CLAUDE.md「ボタンの配色」）。
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: (_reason == null || _sending) ? null : _submit,
          child: Text(strings.reportSubmit),
        ),
      ];
    } else {
      title = Text(strings.reportSentTitle);
      content = Text(
        _phase == _Phase.alreadySent
            ? strings.reportAlreadySentBody
            : strings.reportSentBody,
      );
      actions = [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.reportClose),
        ),
      ];
    }

    return isGlass
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GlassAlertDialog(
              title: title,
              content: content,
              actions: actions,
            ),
          )
        : KeyboardAlertDialog(
            constraints: const BoxConstraints(maxWidth: 420),
            title: title,
            content: content,
            actions: actions,
          );
  }
}
