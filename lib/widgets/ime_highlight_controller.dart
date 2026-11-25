import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 変換中の文字の、キーボードが付けた背景色（2026-11-26）。Androidのキーボード（Gboard）は、
/// 変換中の文字の中のカーソルを内部に持ち、アプリへは「末尾にある」と伝える。代わりに、
/// カーソルより前の範囲を濃い背景色にして見せる（標準の入力欄はこれを描く）。Flutterの
/// エンジンはこの装飾を`TextField`へ渡さないため、Android側で読み取って（`ImeSpanBridge`）
/// このコントローラーへ送り、同じ背景色を描く。
@immutable
class ImeHighlight {
  const ImeHighlight(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is ImeHighlight &&
      other.start == start &&
      other.end == end &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);
}

class ImeHighlightController extends TextEditingController {
  List<ImeHighlight> _highlights = const [];

  List<ImeHighlight> get highlights => _highlights;

  void setHighlights(List<ImeHighlight> next) {
    if (listEquals(next, _highlights)) return;
    _highlights = next;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = value.composing;
    if (!withComposing ||
        _highlights.isEmpty ||
        !composing.isValid ||
        composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final text = value.text;
    final length = text.length;
    final cuts = <int>{0, length};
    int clamp(int v) => v.clamp(0, length);
    cuts
      ..add(clamp(composing.start))
      ..add(clamp(composing.end));
    for (final h in _highlights) {
      cuts
        ..add(clamp(h.start))
        ..add(clamp(h.end));
    }
    final sorted = cuts.toList()..sort();
    final underline = style?.merge(
      const TextStyle(decoration: TextDecoration.underline),
    );
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (a == b) continue;
      var segmentStyle = (a >= composing.start && b <= composing.end)
          ? underline
          : style;
      for (final h in _highlights) {
        if (a >= h.start && b <= h.end) {
          // ラベルの色はアクセントカラー。濃さは、キーボードが付けた背景色の濃さ（カーソルより前が濃い）に合わせる。
          segmentStyle = (segmentStyle ?? const TextStyle()).copyWith(
            backgroundColor: accent.withValues(alpha: h.color.a),
          );
        }
      }
      children.add(TextSpan(text: text.substring(a, b), style: segmentStyle));
    }
    return TextSpan(style: style, children: children);
  }
}

/// Android側（`ImeSpanBridge`）からの背景色の範囲を、入力中のコントローラーへ流す。
/// Android以外では何もしない（Web・PC・iOSは、そもそもこの装飾が無い、または描ける）。
class ImeSpanSync {
  ImeSpanSync._();

  static const _channel = MethodChannel('jp.rhing.daidai/ime_spans');
  static ImeHighlightController? _target;
  static bool _handlerSet = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void activate(ImeHighlightController controller) {
    if (!_supported) return;
    _target = controller;
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'spans') return;
        final raw = call.arguments as List<Object?>? ?? const [];
        _target?.setHighlights([
          for (final item in raw)
            if (item is List && item.length == 3)
              ImeHighlight(
                (item[0] as num).toInt(),
                (item[1] as num).toInt(),
                Color((item[2] as num).toInt()),
              ),
        ]);
      });
    }
    _channel.invokeMethod<void>('start').catchError((_) {});
  }

  static void deactivate(ImeHighlightController controller) {
    if (!_supported || _target != controller) return;
    _target = null;
    controller.setHighlights(const []);
    _channel.invokeMethod<void>('stop').catchError((_) {});
  }
}
