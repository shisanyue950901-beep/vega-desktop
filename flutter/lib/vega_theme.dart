import 'package:flutter/material.dart';

/// Vega 主题常量：浅色 / 深色两套配色，以及统一圆角。
class VegaColors {
  const VegaColors._();

  // ---- 浅色 ----
  static const Color lightBg = Color(0xFFF4F3FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1C1C1E);
  static const Color lightSecondary = Color(0xFF8A8799);
  static const Color lightAccent = Color(0xFF6C5CE7);
  static const Color lightSeparator = Color(0xFFE6E4F0);

  // ---- 深色 ----
  static const Color darkBg = Color(0xFF0C0B14);
  static const Color darkCard = Color(0xFF17161F);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFF8E8E93);
  static const Color darkAccent = Color(0xFF8E7CFF);
  static const Color darkSeparator = Color(0xFF2A2836);

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

  /// 深空主卡片：深紫夜空底色，白字对比度高，星点自然。
  static const LinearGradient space = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1640), Color(0xFF2B2378), Color(0xFF5546D6)],
    stops: [0.0, 0.55, 1.0],
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
    [0.62, 0.10, 1.0],
    [0.74, 0.22, 1.4],
    [0.88, 0.12, 0.9],
    [0.93, 0.40, 1.2],
    [0.81, 0.55, 0.8],
    [0.95, 0.70, 1.0],
    [0.68, 0.34, 0.7],
    [0.86, 0.84, 0.8],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 右上角一团极光辉光 + 左下角淡紫辉光
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        VegaColors.auroraEnd.withOpacity(0.42),
        VegaColors.auroraEnd.withOpacity(0.0),
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.95, -size.height * 0.05),
          radius: size.height * 0.95));
    canvas.drawRect(Offset.zero & size, glow);
    final glow2 = Paint()
      ..shader = RadialGradient(colors: [
        VegaColors.auroraMid.withOpacity(0.32),
        VegaColors.auroraMid.withOpacity(0.0),
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.10, size.height * 1.15),
          radius: size.height * 0.8));
    canvas.drawRect(Offset.zero & size, glow2);
    final paint = Paint()..color = const Color(0xB3FFFFFF);
    for (final s in _stars) {
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vega 标志：圆角方块里一颗四芒星（✦），极光渐变底。
class VegaMark extends StatelessWidget {
  const VegaMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: VegaColors.aurora,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: CustomPaint(painter: _VegaMarkPainter()),
      );
}

class _VegaMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.32;
    final k = r * 0.22;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
