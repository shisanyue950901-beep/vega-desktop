import 'package:flutter/widgets.dart';

/// Vega 主题常量：浅色 / 深色两套配色，以及统一圆角。
class VegaColors {
  const VegaColors._();

  // ---- 浅色 ----
  static const Color lightBg = Color(0xFFF2F2F7);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1C1C1E);
  static const Color lightSecondary = Color(0xFF8E8E93);
  static const Color lightAccent = Color(0xFF007AFF);
  static const Color lightSeparator = Color(0xFFE5E5EA);

  // ---- 深色 ----
  static const Color darkBg = Color(0xFF000000);
  static const Color darkCard = Color(0xFF1C1C1E);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFF8E8E93);
  static const Color darkAccent = Color(0xFF0A84FF);
  static const Color darkSeparator = Color(0xFF38383A);

  // ---- 通用 ----
  static const double radius = 14.0;

  /// 按当前亮度取一套配色。
  static VegaPalette of(BuildContext context) =>
      VegaPalette(MediaQuery.maybeOf(context)?.platformBrightness ==
              Brightness.dark
          ? Brightness.dark
          : Brightness.light);
}

/// 一套配色，便于按亮/暗切换时统一取值。
class VegaPalette {
  const VegaPalette(this.brightness);

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  Color get bg =>
      isDark ? VegaColors.darkBg : VegaColors.lightBg;

  Color get card =>
      isDark ? VegaColors.darkCard : VegaColors.lightCard;

  Color get text =>
      isDark ? VegaColors.darkText : VegaColors.lightText;

  Color get secondary =>
      isDark ? VegaColors.darkSecondary : VegaColors.lightSecondary;

  Color get accent =>
      isDark ? VegaColors.darkAccent : VegaColors.lightAccent;

  Color get separator =>
      isDark ? VegaColors.darkSeparator : VegaColors.lightSeparator;

  double get radius => VegaColors.radius;
}
