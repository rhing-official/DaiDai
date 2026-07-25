import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../widgets/swipe_gestures.dart';

/// サイドバー/ドリルダウンの切り替えしきい値。設定・身だしなみタブと揃える。
const _kSupportSplitBreakpoint = 760.0;

/// サイドバーの幅。
const _kSupportSidebarWidth = 240.0;

/// 運営タブ。`docs/マップ.md`のサイトマップ（ホームページのURL／お知らせ／
/// 質問フォーム）に沿った項目を、設定・身だしなみタブと同じサイドバー＋
/// ドリルダウン構成で表示する（2026-07-25変更、旧: ダイアログ表示の一覧）。
/// ホームページURLが正式に確定していないため、いずれも準備中として案内する。
class SupportTab extends ConsumerStatefulWidget {
  const SupportTab({super.key});

  @override
  ConsumerState<SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends ConsumerState<SupportTab> {
  /// 狭い画面のドリルダウンでのみ使う、選択中カテゴリのid。
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final categories = _categories(strings);
    final isWide =
        MediaQuery.sizeOf(context).width >= _kSupportSplitBreakpoint;

    if (isWide) {
      final selected = _findCategoryById(categories, _selectedId) ??
          categories.first;
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _kSupportSidebarWidth,
              child: _SupportCategoryList(
                categories: categories,
                selectedId: selected.id,
                onSelect: (category) =>
                    setState(() => _selectedId = category.id),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _SupportPage(
                title: selected.title,
                message: strings.settingsComingSoon,
              ),
            ),
          ],
        ),
      );
    }

    final selected = _findCategoryById(categories, _selectedId);
    final selectedIndex =
        selected == null ? -1 : categories.indexWhere((c) => c.id == selected.id);
    final previousCategory = selectedIndex > 0 ? categories[selectedIndex - 1] : null;
    final nextCategory = selectedIndex >= 0 && selectedIndex < categories.length - 1
        ? categories[selectedIndex + 1]
        : null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: selected == null
                ? _SupportCategoryList(
                    key: const ValueKey('support-categories'),
                    categories: categories,
                    selectedId: null,
                    onSelect: (category) =>
                        setState(() => _selectedId = category.id),
                  )
                : SwipeBackDetector(
                    key: ValueKey(selected.id),
                    onBack: () => setState(() => _selectedId = null),
                    onPrevious: previousCategory == null
                        ? null
                        : () => setState(() => _selectedId = previousCategory.id),
                    onNext: nextCategory == null
                        ? null
                        : () => setState(() => _selectedId = nextCategory.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.arrow_back),
                          title: Text(
                            selected.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => setState(() => _selectedId = null),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _SupportPage(
                            title: selected.title,
                            message: strings.settingsComingSoon,
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

/// 運営タブの最上位カテゴリ1つ分。
class _SupportCategory {
  const _SupportCategory({
    required this.id,
    required this.icon,
    required this.title,
  });

  final String id;
  final IconData icon;
  final String title;
}

_SupportCategory? _findCategoryById(
  List<_SupportCategory> categories,
  String? id,
) {
  if (id == null) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

List<_SupportCategory> _categories(Strings strings) {
  return [
    _SupportCategory(
      id: 'homepage',
      icon: Icons.link,
      title: strings.supportHomepageUrl,
    ),
    _SupportCategory(
      id: 'announcements',
      icon: Icons.campaign_outlined,
      title: strings.supportAnnouncements,
    ),
    _SupportCategory(
      id: 'contact',
      icon: Icons.contact_support_outlined,
      title: strings.supportContactForm,
    ),
  ];
}

/// カテゴリ一覧（サイドバー、または狭い画面での一覧画面）。
class _SupportCategoryList extends StatelessWidget {
  const _SupportCategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_SupportCategory> categories;
  final String? selectedId;
  final ValueChanged<_SupportCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final category in categories)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: category.id == selectedId
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : null,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              selected: category.id == selectedId,
              selectedColor: Theme.of(context).colorScheme.primary,
              leading: Icon(category.icon),
              title: Text(category.title),
              onTap: () => onSelect(category),
            ),
          ),
      ],
    );
  }
}

/// 内容ペイン（広い画面ではタイトル付き、狭い画面では戻る行の下に表示）。
/// 実際の内容は各項目とも準備中のため、案内メッセージのみ表示する。
class _SupportPage extends StatelessWidget {
  const _SupportPage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Divider(height: 24),
              Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
