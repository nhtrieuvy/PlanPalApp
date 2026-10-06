import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

enum PlanPalMarkStyle { standard, onDark, monochrome }

class PlanPalMark extends StatelessWidget {
  const PlanPalMark({
    super.key,
    this.size = 48,
    this.style = PlanPalMarkStyle.standard,
    this.onTap,
  });

  final double size;
  final PlanPalMarkStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = RepaintBoundary(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          isComplex: true,
          willChange: false,
          painter: _PlanPalMarkPainter(
            style: style,
            brightness: Theme.of(context).brightness,
          ),
        ),
      ),
    );
    if (onTap == null) {
      return Semantics(image: true, label: 'PlanPal', child: mark);
    }

    return Semantics(
      button: true,
      label: 'PlanPal',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: mark,
      ),
    );
  }
}

class PlanPalLogo extends StatelessWidget {
  const PlanPalLogo({
    super.key,
    this.height = 48,
    this.onDark = false,
    this.monochrome = false,
    this.onTap,
  });

  final double height;
  final bool onDark;
  final bool monochrome;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final markStyle = monochrome
        ? PlanPalMarkStyle.monochrome
        : onDark
        ? PlanPalMarkStyle.onDark
        : PlanPalMarkStyle.standard;
    final wordColor = onDark
        ? AppColors.warmWhite
        : Theme.of(context).colorScheme.onSurface;
    final logo = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlanPalMark(size: height, style: markStyle),
          SizedBox(width: height * .18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Plan',
                style: GoogleFonts.spaceGrotesk(
                  color: wordColor,
                  fontSize: height * .48,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -height * .018,
                ),
              ),
              Text(
                'Pal',
                style: GoogleFonts.spaceGrotesk(
                  color: monochrome
                      ? wordColor
                      : onDark ||
                            Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : AppColors.oceanTeal,
                  fontSize: height * .48,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -height * .018,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(image: true, label: 'PlanPal', child: logo);
    }

    return Semantics(
      button: true,
      label: 'PlanPal',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(height * .18),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: height * .08),
          child: logo,
        ),
      ),
    );
  }
}

class _PlanPalMarkPainter extends CustomPainter {
  const _PlanPalMarkPainter({required this.style, required this.brightness});

  final PlanPalMarkStyle style;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 160;
    final monochromeColor = brightness == Brightness.dark
        ? AppColors.warmWhite
        : AppColors.ink;
    final deepStart = switch (style) {
      PlanPalMarkStyle.onDark => AppColors.warmWhite,
      PlanPalMarkStyle.monochrome => monochromeColor,
      PlanPalMarkStyle.standard =>
        brightness == Brightness.dark
            ? AppColors.warmWhite
            : const Color(0xFF087C73),
    };
    final deepEnd =
        style == PlanPalMarkStyle.standard && brightness == Brightness.light
        ? const Color(0xFF004D49)
        : deepStart;
    final mintStart = style == PlanPalMarkStyle.monochrome
        ? monochromeColor
        : const Color(0xFF52CFC1);
    final mintEnd = style == PlanPalMarkStyle.monochrome
        ? monochromeColor
        : const Color(0xFF80E1D2);
    final holeColor = Colors.transparent;

    final deepRoute = Path()
      ..moveTo(40 * scale, 127 * scale)
      ..lineTo(40 * scale, 75 * scale)
      ..cubicTo(
        40 * scale,
        43 * scale,
        67 * scale,
        27 * scale,
        107 * scale,
        27 * scale,
      );
    final mintRoute = Path()
      ..moveTo(40 * scale, 127 * scale)
      ..cubicTo(
        67 * scale,
        127 * scale,
        64 * scale,
        96 * scale,
        87 * scale,
        92 * scale,
      )
      ..lineTo(104 * scale, 92 * scale)
      ..cubicTo(
        126 * scale,
        92 * scale,
        139 * scale,
        75 * scale,
        139 * scale,
        53 * scale,
      )
      ..cubicTo(
        139 * scale,
        36 * scale,
        127 * scale,
        27 * scale,
        107 * scale,
        27 * scale,
      );

    final bounds = Rect.fromLTWH(0, 0, 160 * scale, 160 * scale);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      deepRoute,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [deepStart, deepEnd],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      mintRoute,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [mintStart, mintEnd],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final deepNode = style == PlanPalMarkStyle.monochrome
        ? monochromeColor
        : deepStart;
    canvas.drawCircle(
      Offset(40 * scale, 75 * scale),
      15 * scale,
      Paint()..color = deepNode,
    );
    canvas.drawCircle(
      Offset(107 * scale, 27 * scale),
      15 * scale,
      Paint()..color = deepEnd,
    );
    canvas.drawCircle(
      Offset(40 * scale, 127 * scale),
      16 * scale,
      Paint()
        ..color = style == PlanPalMarkStyle.monochrome
            ? monochromeColor
            : AppColors.sunsetCoral,
    );
    final holePaint = Paint()
      ..color = holeColor
      ..blendMode = BlendMode.clear;
    canvas.drawCircle(Offset(40 * scale, 75 * scale), 5 * scale, holePaint);
    canvas.drawCircle(Offset(107 * scale, 27 * scale), 5 * scale, holePaint);
    canvas.drawCircle(Offset(40 * scale, 127 * scale), 5.5 * scale, holePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlanPalMarkPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.brightness != brightness;
}
