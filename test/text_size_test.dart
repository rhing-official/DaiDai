import 'package:daidai/providers/text_size_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('倍率は小100%・中125%・大150%', () {
    expect(AppTextSize.small.scale, 1.0);
    expect(AppTextSize.medium.scale, 1.25);
    expect(AppTextSize.large.scale, 1.5);
  });

  test('保存値が不明・未保存なら小になる', () {
    expect(AppTextSize.fromName(null), AppTextSize.small);
    expect(AppTextSize.fromName('huge'), AppTextSize.small);
    expect(AppTextSize.fromName('large'), AppTextSize.large);
  });

  test('選んだフォントサイズは端末に保存され、次回の起動で復元される', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appTextSizeProvider), AppTextSize.small);
    await container
        .read(appTextSizeProvider.notifier)
        .setSize(AppTextSize.large);
    expect(container.read(appTextSizeProvider), AppTextSize.large);
    expect(await loadInitialAppTextSize(), AppTextSize.large);
  });
}
