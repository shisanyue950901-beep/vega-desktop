import 'package:flutter/material.dart';

/// Vega 主题常量：浅色 / 深色两套配色，以及统一圆角。
class VegaColors {
  const VegaColors._();

  // ---- 浅色 ----
  static const Color lightBg = Color(0xFFF2F2F7);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1C1C1E);
  static const Color lightSecondary = Color(0xFF8E8E93);
  static const Color lightAccent = Color(0xFF6C5CE7);
  static const Color lightSeparator = Color(0xFFE5E5EA);

  // ---- 深色 ----
  static const Color darkBg = Color(0xFF000000);
  static const Color darkCard = Color(0xFF1C1C1E);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFF8E8E93);
  static const Color darkAccent = Color(0xFF8E7CFF);
  static const Color darkSeparator = Color(0xFF38383A);

  // ---- 通用 ----
  static const double radius = 18.0;

  // ---- Vega 品牌极光（与 Vega 0.6 控制台 --aurora 一致）----
  static const Color auroraStart = Color(0xFF6C5CE7);
  static const Color auroraMid = Color(0xFF8E7CFF);
  static const Color auroraEnd = Color(0xFF4FC3F7);
  static const LinearGradient aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [auroraStart, auroraMid, auroraEnd],
    stops: [0.0, 0.45, 1.0],
  );

  /// 按当前主题亮度取一套配色（跟随 Theme.of(context)，而非系统亮度）。
  static VegaPalette of(BuildContext context) =>
      VegaPalette(Theme.of(context).brightness);
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

/// Vega 星光点缀：在极光卡片上画几颗固定位置的小星点（与 0.6 控制台 hero__stars 一致）。
class VegaStars extends StatelessWidget {
  const VegaStars({super.key});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _VegaStarsPainter()));
}

class _VegaStarsPainter extends CustomPainter {
  static const _stars = <List<double>>[
    [0.18, 0.22, 1.3],
    [0.72, 0.14, 1.0],
    [0.86, 0.62, 1.6],
    [0.40, 0.78, 1.0],
    [0.58, 0.36, 1.2],
    [0.08, 0.66, 1.0],
    [0.93, 0.30, 0.9],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xCCFFFFFF);
    for (final s in _stars) {
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
