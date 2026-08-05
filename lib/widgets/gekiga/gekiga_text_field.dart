import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';
import 'monochrome_box.dart';

/// 劇画スタイルのテキスト入力欄。標準の[TextField]の角丸なし直線枠のままだと
/// 他の劇画パーツ（モノクロボックス、[monochromeBoxVertices]参照）と
/// 馴染まないため、同じ形の枠を背景に敷き、[TextField]自体は枠線・
/// 塗りつぶし無しにして重ねる（2026-08-03新規、2026-08-05にモノクロ
/// ボックス版へ変更。角カットは付けない直線の矩形にしている。横長で幅の
/// ある箱になりやすく、角カットの量が固定pxのpaddingを超えて文字が
/// はみ出す原因になっていたため）。
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

  @override
  Widget build(BuildContext context) {
    final hintColor = GekigaColors.onPanel.withValues(alpha: 0.5);
    return CustomPaint(
      painter: const _GekigaTextFieldPainter(),
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
  const _GekigaTextFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 角カット無しの矩形にする（2026-08-05変更。カット量は幅・高さの
    // パーセントで決まるため、入力欄のように横長で幅がある箱では固定pxの
    // paddingを超えて食い込み、テキストが枠からはみ出す原因になっていた）。
    final vertices = monochromeBoxVertices(
      size.width,
      size.height,
      topLeft: false,
      topRight: false,
      bottomRight: false,
      bottomLeft: false,
    );
    MonochromeBoxPainter(
      vertices: vertices,
      thicknessBase: size.shortestSide,
      fillColor: GekigaColors.panel,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GekigaTextFieldPainter oldDelegate) => false;
}
