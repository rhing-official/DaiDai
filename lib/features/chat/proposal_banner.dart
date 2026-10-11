import 'package:flutter/material.dart';

/// 絶縁・既読オン/オフの提案バナー（`chat_panes.dart`）の共通レイアウト
/// （2026-10-11追加）。幅が[narrowBreakpoint]未満（モバイル等）ならメッセージ文と
/// ボタン群を2段（文の下に右寄せのボタン）に分け、それ以上なら1行に並べる。
class ProposalBannerLayout extends StatelessWidget {
  const ProposalBannerLayout({
    required this.message,
    required this.actions,
    super.key,
  });

  final Widget message;
  final List<Widget> actions;

  /// ホーム・管理画面のナビチップと同じ、狭い/広いの境目。
  static const narrowBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < narrowBreakpoint;
        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: actions,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    message,
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: buttons),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: message),
                    buttons,
                  ],
                ),
        );
      },
    );
  }
}

/// 提案バナーの「同意する」ボタン用スタイル。他の「大事な選択を確定させる
/// ボタン」と同じ固定の濃い赤＋白文字（外観・ライト/ダークに関わらず同じ。
/// `colorScheme.error`はダークで薄く、ライトで濃すぎるため使わない）。
ButtonStyle proposalAcceptButtonStyle() => FilledButton.styleFrom(
  backgroundColor: Colors.red.shade700,
  foregroundColor: Colors.white,
);
