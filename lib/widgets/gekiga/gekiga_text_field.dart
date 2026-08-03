import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';

/// 劇画スタイルのテキスト入力欄。標準の[TextField]の角丸なし直線枠のままだと
/// 他の劇画パーツ（手描き風ギザギザ枠、[GekigaPanelBox]/`GekigaMenuTile`）と
/// 馴染まないため、同じ`handDrawnPolygonPath`ベースの枠を背景に敷き、
/// [TextField]自体は枠線・塗りつぶし無しにして重ねる（2026-08-03新規）。
class GekigaTextField extends StatelessWidget {
  const GekigaTextField({
    required this.controller,
    this.hintText,
    this.labelText,
    this.prefixText,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.seed = 0,
    super.key,
  });

  final TextEditingController controller;
  final String? hintText;
  final String? labelText;
  final String? prefixText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final hintColor = GekigaColors.onPanel.withValues(alpha: 0.5);
    return CustomPaint(
      painter: _GekigaTextFieldPainter(seed: seed),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: const TextStyle(color: GekigaColors.onPanel),
        cursorColor: GekigaColors.onPanel,
        decoration: InputDecoration(
          hintText: hintText,
          labelText: labelText,
          prefixText: prefixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          errorText: errorText,
          counterText: '',
          hintStyle: TextStyle(color: hintColor),
          labelStyle: TextStyle(color: hintColor),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _GekigaTextFieldPainter extends CustomPainter {
  const _GekigaTextFieldPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final path = handDrawnPolygonPath(
      [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ],
      seed,
      jitter: 2.4,
      segmentsPerEdge: 5,
    );
    canvas.drawPath(path, Paint()..color = GekigaColors.panel);
    canvas.drawPath(
      path,
      Paint()
        ..color = GekigaColors.onPanel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GekigaTextFieldPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
