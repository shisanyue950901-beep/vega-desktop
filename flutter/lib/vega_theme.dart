import 'dart:math' as math;

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

/// Vega 星光：极光辉光缓慢漂移、星点闪烁、偶尔划过一颗流星。
/// 一个 16 秒循环的 AnimationController 驱动，RepaintBoundary 隔离重绘。
class VegaStars extends StatefulWidget {
  const VegaStars({super.key});

  @override
  State<VegaStars> createState() => _VegaStarsState();
}

class _VegaStarsState extends State<VegaStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _VegaStarsPainter(_c)),
        ),
      );
}

class _VegaStarsPainter extends CustomPainter {
  _VegaStarsPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  // [x, y, 半径, 闪烁速度, 相位]，都放在卡片右侧，避开左边的文字。
  static const _stars = <List<double>>[
    [0.62, 0.10, 1.0, 3, 0.1],
    [0.74, 0.22, 1.5, 2, 0.7],
    [0.88, 0.12, 0.9, 4, 0.3],
    [0.93, 0.40, 1.2, 3, 0.9],
    [0.81, 0.55, 0.8, 5, 0.5],
    [0.95, 0.70, 1.0, 2, 0.2],
    [0.68, 0.34, 0.7, 4, 0.6],
    [0.86, 0.84, 0.8, 3, 0.4],
    [0.56, 0.20, 0.6, 5, 0.8],
    [0.77, 0.70, 0.6, 4, 0.0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value; // 0..1
    final a = v * 2 * math.pi;
    final rect = Offset.zero & size;

    // 右上角极光辉光，缓慢画圈漂移
    final g1 = Offset(size.width * (0.92 + 0.06 * math.cos(a)),
        size.height * (-0.02 + 0.10 * math.sin(a)));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            VegaColors.auroraEnd.withOpacity(0.40 + 0.08 * math.sin(a * 2)),
            VegaColors.auroraEnd.withOpacity(0.0),
          ]).createShader(
              Rect.fromCircle(center: g1, radius: size.height * 0.95)));
    // 左下角淡紫辉光，反向漂移
    final g2 = Offset(size.width * (0.12 - 0.06 * math.cos(a)),
        size.height * (1.12 - 0.08 * math.sin(a)));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            VegaColors.auroraMid.withOpacity(0.32),
            VegaColors.auroraMid.withOpacity(0.0),
          ]).createShader(
              Rect.fromCircle(center: g2, radius: size.height * 0.8)));

    // 星点闪烁
    for (final s in _stars) {
      final tw = 0.5 + 0.5 * math.sin(a * s[3] + s[4] * 2 * math.pi);
      final o = 0.25 + 0.75 * tw;
      final c = Offset(s[0] * size.width, s[1] * size.height);
      if (s[2] >= 1.2) {
        canvas.drawCircle(
            c,
            s[2] * 3.2,
            Paint()
              ..color = Colors.white.withOpacity(0.10 * o)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
      canvas.drawCircle(c, s[2] * (0.8 + 0.3 * tw),
          Paint()..color = Colors.white.withOpacity(0.85 * o));
    }

    // 流星：每个循环在 8%–16% 的时间段里从右上划向左下
    const start = 0.08, end = 0.16;
    if (v > start && v < end) {
      final p = (v - start) / (end - start);
      final head = Offset(size.width * (0.98 - 0.42 * p),
          size.height * (0.04 + 0.30 * p));
      final tail = head + Offset(size.width * 0.10, -size.height * 0.07);
      final fade = math.sin(p * math.pi);
      canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(colors: [
              Colors.white.withOpacity(0.0),
              Colors.white.withOpacity(0.9 * fade),
            ]).createShader(Rect.fromPoints(tail, head)));
      canvas.drawCircle(
          head, 1.3, Paint()..color = Colors.white.withOpacity(fade));
    }
  }

  @override
  bool shouldRepaint(covariant _VegaStarsPainter oldDelegate) => false;
}

/// 卡片入场：轻微上移 + 淡入。
class VegaEntrance extends StatelessWidget {
  const VegaEntrance({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 520 + delayMs),
        curve: Interval(delayMs / (520 + delayMs), 1,
            curve: Curves.easeOutCubic),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        child: child,
      );
}

/// 鼠标悬停时轻轻浮起（上移 2px，阴影由子组件自己画）。
class VegaHoverLift extends StatefulWidget {
  const VegaHoverLift({super.key, required this.child});

  final Widget child;

  @override
  State<VegaHoverLift> createState() => _VegaHoverLiftState();
}

class _VegaHoverLiftState extends State<VegaHoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedSlide(
          offset: Offset(0, _hover ? -0.012 : 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
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
