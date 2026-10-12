import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../widgets/fixed_font_theme.dart';

const _termsUrl = 'https://rhing.jp/legal/terms';
const _privacyPolicyUrl = 'https://rhing.jp/legal/privacy';
const _disclaimerUrl = 'https://rhing.jp/legal/disclaimer';

Future<void> _openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 新規アカウント作成時、[RhingSeedSetupScreen]より前段に挟む同意画面。
/// 利用規約・プライバシーポリシー・免責事項への同意を必須にする
/// （技術仕様書のオンボーディング計画の前倒し実装、2026-09-14追加）。
class TermsConsentScreen extends ConsumerStatefulWidget {
  const TermsConsentScreen({required this.onAgree, super.key});

  final VoidCallback onAgree;

  @override
  ConsumerState<TermsConsentScreen> createState() => _TermsConsentScreenState();
}

class _TermsConsentScreenState extends ConsumerState<TermsConsentScreen> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return FixedFontTheme(
      child: Scaffold(
        appBar: AppBar(title: Text(strings.termsConsentAppBarTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.termsConsentIntro),
                  const SizedBox(height: 16),
                  _LinkRow(
                    label: strings.termsConsentTermsLink,
                    onTap: () => _openExternalUrl(_termsUrl),
                  ),
                  _LinkRow(
                    label: strings.termsConsentPrivacyLink,
                    onTap: () => _openExternalUrl(_privacyPolicyUrl),
                  ),
                  _LinkRow(
                    label: strings.termsConsentDisclaimerLink,
                    onTap: () => _openExternalUrl(_disclaimerUrl),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _checked,
                    onChanged: (value) =>
                        setState(() => _checked = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.termsConsentCheckbox),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _checked ? widget.onAgree : null,
                    child: Text(strings.termsConsentContinueButton),
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const Icon(Icons.open_in_new, size: 18),
          ],
        ),
      ),
    );
  }
}
