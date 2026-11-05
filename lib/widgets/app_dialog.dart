import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// 画面遷移の種類（設定＞画面遷移）に従って開閉するダイアログ（2026-11-05）。
/// 素の`showDialog`と同じ引数・同じ見た目で、開閉のアニメーションだけを
/// [buildDialogTransition]に差し替える。アプリのダイアログ・ポップアップは
/// `showDialog`ではなくこれを使う。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push(
    AppDialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      barrierColor:
          barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      requestFocus: requestFocus,
    ),
  );
}

/// [showAppDialog]のルート。素の`DialogRoute`の開閉（フェードだけ）を、画面遷移の
/// 種類に従う動きに差し替える。
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.anchorPoint,
    super.traversalEdgeBehavior,
    super.requestFocus,
  });

  @override
  Duration get transitionDuration => popSlideDuration;

  @override
  Duration get reverseTransitionDuration => popSlideDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => buildDialogTransition(animation, child);
}
