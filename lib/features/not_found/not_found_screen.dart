import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// 404ページで展示する作品1点分（2026-10-10追加）。
class MuseumExhibit {
  const MuseumExhibit({
    required this.asset,
    required this.title,
    required this.caption,
  });

  final String asset;
  final String title;
  final String caption;
}

/// HomePage-Rhingの`not-found.tsx`と同じ6点。
const museumExhibits = [
  MuseumExhibit(
    asset: 'assets/museum/night-alley.jpg',
    title: '《夜の回廊》',
    caption: '灯りの続く夜の路地',
  ),
  MuseumExhibit(
    asset: 'assets/museum/vintage-chairs.jpg',
    title: '《色彩の椅子》',
    caption: '庭先に並ぶ五つの椅子',
  ),
  MuseumExhibit(
    asset: 'assets/museum/rose-and-monument.jpg',
    title: '《薔薇と記念碑》',
    caption: '曇天の広場にて',
  ),
  MuseumExhibit(
    asset: 'assets/museum/snow-town.jpg',
    title: '《雪の町、山影》',
    caption: '夕陽に染まる町並み',
  ),
  MuseumExhibit(
    asset: 'assets/museum/berries-in-shade.jpg',
    title: '《木陰の実り》',
    caption: '葉隠れの青い実',
  ),
  MuseumExhibit(
    asset: 'assets/museum/leaves-in-dark.jpg',
    title: '《葉陰の彩り》',
    caption: '闇に浮かぶ葉の群れ',
  ),
];

const _contactUrl = 'https://rhing.jp/contact';

const _background = Color(0xFFFCFBF7);
const _gray900 = Color(0xFF111827);
const _gray800 = Color(0xFF1F2937);
const _gray600 = Color(0xFF4B5563);
const _gray500 = Color(0xFF6B7280);
const _gray400 = Color(0xFF9CA3AF);
const _gray300 = Color(0xFFD1D5DB);
const _gray200 = Color(0xFFE5E7EB);

/// 定義されていないURLを開いた時の「404 美術館」ページ（2026-10-10新設）。
/// go_routerの`errorBuilder`と、管理者でない人が開いた`/admin`
/// （`AdminGate`）で共通に使う。表示のたびに6点からランダムで1点を展示する。
/// 参照元はHomePage-Rhingの`not-found.tsx`で、アプリのテーマ（ダーク/ライト・
/// アクセントカラー・UIスタイル）とは無関係の単独デザインのため、色は固定値
/// にしている（フォントだけテーマを継承する）。
class NotFoundScreen extends StatefulWidget {
  const NotFoundScreen({super.key});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen>
    with SingleTickerProviderStateMixin {
  // カード（〜1.3秒）→額縁（確定後0.8秒）→ボタン（0.9秒遅れ・1秒）が
  // 全て終わる長さ。各要素は[Interval]で切り出す。
  static const _totalSeconds = 1.9;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  /// 選出が確定するまでnull（額縁は非表示）。参照元と同じく、描画後に
  /// 選んでからフェードインさせる。
  MuseumExhibit? _exhibit;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _exhibit = museumExhibits[Random().nextInt(museumExhibits.length)];
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [begin]〜[end]秒の区間だけ進む0→1のアニメーション。
  Animation<double> _interval(double begin, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(
      begin / _totalSeconds,
      end / _totalSeconds,
      curve: Curves.easeOut,
    ),
  );

  /// 下から[offset]px移動しながらフェードインさせる。
  Widget _riseIn(Animation<double> animation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseText =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final width = MediaQuery.sizeOf(context).width;
    final showIllustrations = width >= 1024;
    final illustrationWidth = width >= 1280 ? 176.0 : 144.0;

    final exhibitCard = _ExhibitFrame(exhibit: _exhibit, baseText: baseText);

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 896),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 96),
                child: Column(
                  children: [
                    _riseIn(
                      _interval(0, 1.2),
                      _GlassCard(
                        radius: 24,
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 16,
                        ),
                        child: Column(
                          children: [
                            Text(
                              '404 MUSEUM',
                              textAlign: TextAlign.center,
                              style: baseText.copyWith(
                                fontSize: width >= 768 ? 48 : 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: _gray900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'お探しのページは見つかりませんでした',
                              textAlign: TextAlign.center,
                              style: baseText.copyWith(
                                fontSize: 14,
                                letterSpacing: 1.4,
                                color: _gray500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                    _riseIn(
                      _interval(0.1, 1.3),
                      _GlassCard(
                        radius: 24,
                        padding: EdgeInsets.all(width >= 768 ? 40 : 32),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            '本日は存在しないページ特別展を開催しております。\n'
                            'お探しのページは見当たりませんでした。\n'
                            'URLをご確認のうえ、常設展示からお探しください。',
                            textAlign: TextAlign.center,
                            style: baseText.copyWith(
                              fontSize: 16,
                              height: 1.7,
                              color: _gray600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                    if (showIllustrations)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Illustration(
                            'assets/illustrations/book-lover.svg',
                            width: illustrationWidth,
                          ),
                          const SizedBox(width: 40),
                          Flexible(child: exhibitCard),
                          const SizedBox(width: 40),
                          _Illustration(
                            'assets/illustrations/couple-photo.svg',
                            width: illustrationWidth,
                          ),
                        ],
                      )
                    else
                      exhibitCard,
                    const SizedBox(height: 64),
                    FadeTransition(
                      opacity: _interval(0.9, 1.9),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _PillButton(
                            label: 'トップページへ戻る',
                            filled: true,
                            baseText: baseText,
                            onPressed: () => context.go('/'),
                          ),
                          _PillButton(
                            label: 'お問い合わせ',
                            filled: false,
                            baseText: baseText,
                            onPressed: () => launchUrl(
                              Uri.parse(_contactUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 半透明の白・薄いぼかし・白い細枠・弱い影のカード。
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    required this.radius,
    required this.padding,
    this.alpha = 0.4,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// 白の不透明度（案内カード0.4、額縁0.6）。
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: _gray200.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: alpha),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 展示作品の額縁。選出が確定する（[exhibit]がnullでなくなる）までは
/// 見えない（opacity 0）。確定後に0.8秒で下から上がってフェードインする。
class _ExhibitFrame extends StatelessWidget {
  const _ExhibitFrame({required this.exhibit, required this.baseText});

  final MuseumExhibit? exhibit;
  final TextStyle baseText;

  @override
  Widget build(BuildContext context) {
    final exhibit = this.exhibit;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: exhibit == null ? 0 : 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: _GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(12),
          alpha: 0.6,
          child: exhibit == null
              // 確定前も額縁の大きさを確保し、確定後にレイアウトが動かないようにする。
              ? const SizedBox(height: 288 + 8 + 8 + 56, width: double.infinity)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _gray200),
                      ),
                      child: SizedBox(
                        height: 288,
                        width: double.infinity,
                        child: Image.asset(
                          exhibit.asset,
                          fit: BoxFit.cover,
                          semanticLabel: exhibit.title,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: _gray200),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      exhibit.title,
                      textAlign: TextAlign.center,
                      style: baseText.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: _gray800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exhibit.caption,
                      textAlign: TextAlign.center,
                      style: baseText.copyWith(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        color: _gray400,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration(this.asset, {required this.width});

  final String asset;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SvgPicture.asset(asset, width: width),
    );
  }
}

/// 完全な丸み（pill型）のボタン。黒の塗り／灰色の枠線。
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.filled,
    required this.baseText,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final TextStyle baseText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xFF111111) : Colors.transparent,
      shape: StadiumBorder(
        side: filled ? BorderSide.none : const BorderSide(color: _gray300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: baseText.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: filled ? Colors.white : _gray600,
            ),
          ),
        ),
      ),
    );
  }
}
