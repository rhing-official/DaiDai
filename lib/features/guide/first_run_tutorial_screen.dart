import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/tutorial_content.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/fixed_font_theme.dart';
import 'tutorial/practice_home.dart';
import 'tutorial/tutorial_stage_screen.dart';

/// 初回の使い方ガイド（2026-10-17追加）。新規登録直後に、居住地アンケートの後で
/// 練習用のホーム（本物の画面＋偽データ）を開き、身だしなみ→縁結び→メッセージの
/// 送り方を実際に押して覚えてもらう（[firstRunTutorial]）。最後まで進んでも
/// 「やめる」でも、`users/{uid}.preferences.guideSeen`を`true`にして次へ進む
/// （二度と自動では出さない）。ほかの使い方は、設定＞運営＞使い方ガイドから開ける。
class FirstRunTutorialScreen extends ConsumerStatefulWidget {
  const FirstRunTutorialScreen({
    required this.userId,
    required this.onCompleted,
    super.key,
  });

  /// 視聴済みの記録を更新する住人。
  final String userId;

  /// 終えた後に、1回だけ呼ぶ。
  final VoidCallback onCompleted;

  @override
  ConsumerState<FirstRunTutorialScreen> createState() =>
      _FirstRunTutorialScreenState();
}

class _FirstRunTutorialScreenState
    extends ConsumerState<FirstRunTutorialScreen> {
  bool _finished = false;

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    try {
      await ref
          .read(userRepositoryProvider)
          .updateUserPreference(widget.userId, 'guideSeen', true);
    } catch (e) {
      // 記録に失敗しても先へ進める（次回また出るだけ）。
      debugPrint('使い方ガイドの視聴記録に失敗: $e');
    }
    if (!mounted) return;
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return FixedFontTheme(
      child: TutorialStageScreen(
        startScript: firstRunTutorial,
        onClosed: _finish,
        child: const PracticeHome(),
      ),
    );
  }
}
