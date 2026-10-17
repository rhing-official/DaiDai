import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/guide_content.dart';
import '../../l10n/strings.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/fixed_font_theme.dart';

/// 初回の使い方ガイド（2026-10-17追加）。新規登録直後に、居住地アンケートの後で
/// 数枚のカードをスワイプで見せる。「スキップ」でも最後まで進んでも、
/// `users/{uid}.preferences.guideSeen`を`true`にして次へ進む（二度と自動では
/// 出さない）。設定＞運営＞使い方ガイドからの再表示では[userId]を渡さず、
/// 記録は更新しない。
class FirstGuideScreen extends ConsumerStatefulWidget {
  const FirstGuideScreen({required this.onCompleted, this.userId, super.key});

  /// 視聴済みの記録を更新する住人。nullなら記録しない（再表示用）。
  final String? userId;

  /// スキップまたは最後まで進んだ後に、1回だけ呼ぶ。
  final VoidCallback onCompleted;

  @override
  ConsumerState<FirstGuideScreen> createState() => _FirstGuideScreenState();
}

class _FirstGuideScreenState extends ConsumerState<FirstGuideScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finished = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    final userId = widget.userId;
    if (userId != null) {
      try {
        await ref
            .read(userRepositoryProvider)
            .updateUserPreference(userId, 'guideSeen', true);
      } catch (e) {
        // 記録に失敗しても先へ進める（次回また出るだけ）。
        debugPrint('使い方ガイドの視聴記録に失敗: $e');
      }
    }
    if (!mounted) return;
    widget.onCompleted();
  }

  void _next() {
    if (_page >= firstGuidePages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final locale = ref.watch(appLocaleProvider);
    final isLast = _page == firstGuidePages.length - 1;
    final theme = Theme.of(context);
    return FixedFontTheme(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(strings.guideFirstSkip),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: firstGuidePages.length,
                      onPageChanged: (index) => setState(() => _page = index),
                      itemBuilder: (context, index) {
                        final page = firstGuidePages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                page.icon,
                                size: 72,
                                color: theme.colorScheme.onSurface,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                page.titleOf(locale),
                                style: theme.textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                page.bodyOf(locale),
                                style: theme.textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < firstGuidePages.length; i++)
                        Container(
                          key: ValueKey('guide-dot-$i'),
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.25,
                                  ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        child: Text(
                          isLast
                              ? strings.guideFirstStart
                              : strings.guideFirstNext,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
