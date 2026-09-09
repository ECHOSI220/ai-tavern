import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Material language, independent of theme IDs and of game/session state.
enum SkinMaterial {
  standard,
  brass,
  neon,
  paper,
  oath,
  tactical,
  digitalStage,
  clockworkVoice,
}

@immutable
class SkinCraft extends ThemeExtension<SkinCraft> {
  const SkinCraft({
    this.material = SkinMaterial.standard,
    this.accent = const Color(0xffc9a76a),
    this.secondary = const Color(0xff6caeb0),
    this.line = const Color(0xff4c4438),
    this.radius = 14,
  });
  final SkinMaterial material;
  final Color accent, secondary, line;
  final double radius;
  bool get refined => material != SkinMaterial.standard;
  static SkinCraft of(BuildContext context) =>
      Theme.of(context).extension<SkinCraft>() ?? const SkinCraft();

  OutlinedBorder frame({Color? border, double? corner, bool ornament = true}) =>
      CraftFrameBorder(
        material: material,
        radius: corner ?? radius,
        accent: accent,
        ornament: ornament,
        side: BorderSide(color: border ?? line),
      );

  @override
  SkinCraft copyWith({
    SkinMaterial? material,
    Color? accent,
    Color? secondary,
    Color? line,
    double? radius,
  }) => SkinCraft(
    material: material ?? this.material,
    accent: accent ?? this.accent,
    secondary: secondary ?? this.secondary,
    line: line ?? this.line,
    radius: radius ?? this.radius,
  );
  @override
  SkinCraft lerp(covariant SkinCraft? other, double t) => other == null
      ? this
      : SkinCraft(
          material: t < .5 ? material : other.material,
          accent: Color.lerp(accent, other.accent, t)!,
          secondary: Color.lerp(secondary, other.secondary, t)!,
          line: Color.lerp(line, other.line, t)!,
          radius: radius + (other.radius - radius) * t,
        );
}

/// Ornament lives inside a real Material ShapeBorder, so ink, focus, clipping
/// and hit testing retain Material behavior. No overlay widget intercepts taps.
class CraftFrameBorder extends OutlinedBorder {
  const CraftFrameBorder({
    required this.material,
    required this.radius,
    required this.accent,
    this.ornament = true,
    super.side,
  });
  final SkinMaterial material;
  final double radius;
  final Color accent;
  final bool ornament;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  CraftFrameBorder copyWith({BorderSide? side}) => CraftFrameBorder(
    material: material,
    radius: radius,
    accent: accent,
    ornament: ornament,
    side: side ?? this.side,
  );
  @override
  ShapeBorder scale(double t) => CraftFrameBorder(
    material: material,
    radius: radius * t,
    accent: accent,
    ornament: ornament,
    side: side.scale(t),
  );
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(radius, rect.shortestSide / 3);
    if (material == SkinMaterial.tactical) {
      final cut = math.min(10.0, rect.shortestSide * .2);
      final largeCut = math.min(24.0, rect.shortestSide * .34);
      return Path()
        ..moveTo(rect.left + cut, rect.top)
        ..lineTo(rect.right - largeCut, rect.top)
        ..lineTo(rect.right, rect.top + largeCut)
        ..lineTo(rect.right, rect.bottom - cut)
        ..lineTo(rect.right - cut, rect.bottom)
        ..lineTo(rect.left + largeCut, rect.bottom)
        ..lineTo(rect.left, rect.bottom - largeCut)
        ..lineTo(rect.left, rect.top + cut)
        ..close();
    }
    if (material == SkinMaterial.digitalStage) {
      final cut = math.min(18.0, rect.shortestSide * .28);
      return Path()
        ..moveTo(rect.left + r, rect.top)
        ..lineTo(rect.right - cut, rect.top)
        ..lineTo(rect.right, rect.top + cut)
        ..lineTo(rect.right, rect.bottom - r)
        ..quadraticBezierTo(
          rect.right,
          rect.bottom,
          rect.right - r,
          rect.bottom,
        )
        ..lineTo(rect.left + cut, rect.bottom)
        ..lineTo(rect.left, rect.bottom - cut)
        ..lineTo(rect.left, rect.top + r)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top)
        ..close();
    }
    if (material == SkinMaterial.clockworkVoice) {
      final notch = math.min(10.0, rect.shortestSide * .18);
      return Path()
        ..moveTo(rect.left + r, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r)
        ..lineTo(rect.right, rect.bottom - notch)
        ..lineTo(rect.right - notch, rect.bottom)
        ..lineTo(rect.left + r, rect.bottom)
        ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - r)
        ..lineTo(rect.left, rect.top + notch)
        ..lineTo(rect.left + notch, rect.top)
        ..close();
    }
    if (material == SkinMaterial.neon) {
      return Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..lineTo(rect.right, rect.top + r)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left + r, rect.bottom)
        ..lineTo(rect.left, rect.bottom - r)
        ..close();
    }
    return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
    if (!ornament || rect.shortestSide < 40) return;
    final p = Paint()
      ..color = accent.withValues(alpha: .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    switch (material) {
      case SkinMaterial.oath:
        // The ornament stays within the padding rail; never over the text.
        final inner = rect.deflate(4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            inner,
            Radius.circular(math.max(2, radius - 3)),
          ),
          p..color = accent.withValues(alpha: .13),
        );
        for (final right in [false, true]) {
          final x = right ? rect.right - 10 : rect.left + 10;
          final direction = right ? -1.0 : 1.0;
          final path = Path()
            ..moveTo(x, rect.top + 25)
            ..lineTo(x, rect.top + 10)
            ..lineTo(x + direction * 24, rect.top + 10);
          canvas.drawPath(path, p..color = accent.withValues(alpha: .65));
          final c = Offset(x + direction * 28, rect.top + 10);
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - 2)
              ..lineTo(c.dx + 3, c.dy)
              ..lineTo(c.dx, c.dy + 2)
              ..lineTo(c.dx - 3, c.dy)
              ..close(),
            p,
          );
        }
        canvas.drawLine(
          Offset(rect.center.dx - 18, rect.bottom - 5),
          Offset(rect.center.dx + 18, rect.bottom - 5),
          p..color = accent.withValues(alpha: .32),
        );
      case SkinMaterial.brass:
        final inset = rect.deflate(5);
        final r = math.max(2.0, radius - 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(inset, Radius.circular(r)),
          p..color = accent.withValues(alpha: .12),
        );
        for (final x in [rect.left + 17, rect.right - 17]) {
          canvas.drawCircle(
            Offset(x, rect.top + 5),
            1.3,
            Paint()..color = accent.withValues(alpha: .6),
          );
        }
      case SkinMaterial.neon:
        p
          ..color = accent.withValues(alpha: .75)
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(rect.left + 1, rect.top + 10),
          Offset(rect.left + 1, rect.top + math.min(32, rect.height - 10)),
          p,
        );
        p.strokeWidth = 1;
        canvas.drawLine(
          Offset(rect.right - 36, rect.bottom - 4),
          Offset(rect.right - 12, rect.bottom - 4),
          p,
        );
      case SkinMaterial.tactical:
        final topRail = math.min(52.0, rect.width * .25);
        canvas.drawLine(
          Offset(rect.left + 12, rect.top + 3),
          Offset(rect.left + 12 + topRail, rect.top + 3),
          p
            ..color = accent.withValues(alpha: .9)
            ..strokeWidth = 1.5,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 7, rect.top + 8, 3, 11),
          Paint()..color = accent.withValues(alpha: .85),
        );
        canvas.drawLine(
          Offset(rect.right - 42, rect.bottom - 4),
          Offset(rect.right - 14, rect.bottom - 4),
          p
            ..color = accent.withValues(alpha: .7)
            ..strokeWidth = 1,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(
              rect.right - 17 - i * 7,
              rect.top + 8,
              i == 0 ? 4 : 2,
              2,
            ),
            Paint()..color = accent.withValues(alpha: .48),
          );
        }
      case SkinMaterial.digitalStage:
        final topWidth = math.min(rect.width * .27, 82.0);
        canvas.drawLine(
          Offset(rect.left + 12, rect.top + 4),
          Offset(rect.left + 12 + topWidth, rect.top + 4),
          p
            ..color = accent.withValues(alpha: .86)
            ..strokeWidth = 1.4,
        );
        final baseY = rect.bottom - 5;
        for (var i = 0; i < 8; i++) {
          final bar = 3.0 + ((i * 5) % 9);
          canvas.drawLine(
            Offset(rect.right - 13 - i * 5, baseY),
            Offset(rect.right - 13 - i * 5, baseY - bar),
            p
              ..color = accent.withValues(alpha: .35 + i * .035)
              ..strokeWidth = 1.5,
          );
        }
        canvas.drawCircle(
          Offset(rect.right - 7, rect.top + 13),
          2,
          Paint()..color = accent.withValues(alpha: .78),
        );
      case SkinMaterial.clockworkVoice:
        // Keep the card corner decorative, but do not draw a miniature VU
        // dial here. Its semicircle and needle were clipped by the card's
        // chamfer and looked like a broken icon on narrow/mobile cards.
        final railStart = rect.left + 18;
        final railEnd = math.min(rect.right - 34, railStart + 48);
        final railY = rect.top + 6;
        canvas.drawLine(
          Offset(railStart, railY),
          Offset(railEnd, railY),
          p
            ..color = accent.withValues(alpha: .68)
            ..strokeWidth = 1.15,
        );
        for (var i = 0; i < 3; i++) {
          final x = railStart + 8 + i * 12;
          canvas.drawLine(
            Offset(x, railY),
            Offset(x + 4, railY + (i == 1 ? 3 : 2)),
            p
              ..color = accent.withValues(alpha: .42)
              ..strokeWidth = .8,
          );
        }
        for (final point in [
          Offset(rect.left + 8, rect.bottom - 8),
          Offset(rect.right - 8, rect.top + 8),
        ]) {
          canvas.drawCircle(
            point,
            2.2,
            Paint()..color = accent.withValues(alpha: .7),
          );
          canvas.drawCircle(
            point,
            4.2,
            p
              ..color = accent.withValues(alpha: .25)
              ..strokeWidth = .7,
          );
        }
      case SkinMaterial.paper:
        p
          ..color = side.color
          ..strokeWidth = .7;
        canvas.drawLine(
          Offset(rect.left + 5, rect.top + 14),
          Offset(rect.left + 5, rect.bottom - 14),
          p,
        );
        canvas.drawLine(
          Offset(rect.right - 5, rect.top + 14),
          Offset(rect.right - 5, rect.bottom - 14),
          p,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.right - 22, rect.top + 5, 9, 3),
          Paint()..color = accent.withValues(alpha: .65),
        );
      case SkinMaterial.standard:
        break;
    }
  }
}

/// Shared framing. Paint the translucent fill once, not twice (Material + Ink).
class CraftedSurface extends StatelessWidget {
  const CraftedSurface({
    required this.child,
    required this.color,
    this.padding = EdgeInsets.zero,
    this.margin,
    this.radius,
    this.border,
    this.ornament = true,
    super.key,
  });
  final Widget child;
  final Color color;
  final Color? border;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final bool ornament;
  @override
  Widget build(BuildContext context) {
    final craft = SkinCraft.of(context);
    final shape = craft.frame(
      border: border,
      corner: radius,
      ornament: ornament,
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: craft.refined ? Colors.transparent : color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: ShapeDecoration(
            shape: shape,
            gradient: craft.refined
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(color, craft.accent, .035)!, color],
                  )
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Geometric seal, astrolabe or circuit core: drawn crisply at any pixel ratio.
class CraftEmblem extends StatelessWidget {
  const CraftEmblem({this.size = 52, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _EmblemPainter(SkinCraft.of(context))),
    ),
  );
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter(this.craft);
  final SkinCraft craft;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide * .4;
    final p = Paint()
      ..color = craft.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (craft.material == SkinMaterial.oath) {
      canvas.drawCircle(c, r, p..color = craft.accent.withValues(alpha: .5));
      canvas.drawCircle(
        c,
        r * .84,
        p..color = craft.secondary.withValues(alpha: .3),
      );
      final blade = Path()
        ..moveTo(c.dx, c.dy - r * .8)
        ..lineTo(c.dx + r * .12, c.dy - r * .5)
        ..lineTo(c.dx + r * .09, c.dy + r * .35)
        ..lineTo(c.dx - r * .09, c.dy + r * .35)
        ..lineTo(c.dx - r * .12, c.dy - r * .5)
        ..close();
      canvas.drawPath(blade, p..color = craft.accent);
      canvas.drawLine(
        c + Offset(-r * .4, r * .28),
        c + Offset(r * .4, r * .28),
        p..strokeWidth = 1.7,
      );
      canvas.drawLine(c + Offset(0, r * .35), c + Offset(0, r * .68), p);
      canvas.drawCircle(c + Offset(0, r * .73), r * .06, p);
      return;
    }
    if (craft.material == SkinMaterial.paper) {
      final rect = Rect.fromCircle(center: c, radius: r * .8);
      canvas.drawRect(rect, p..strokeWidth = 1.6);
      canvas.drawRect(rect.deflate(3), p..strokeWidth = .6);
      final path = Path()
        ..moveTo(c.dx - r * .45, c.dy + r * .4)
        ..lineTo(c.dx - r * .45, c.dy - r * .25)
        ..lineTo(c.dx, c.dy + r * .05)
        ..lineTo(c.dx, c.dy - r * .5)
        ..moveTo(c.dx, c.dy + r * .05)
        ..lineTo(c.dx + r * .45, c.dy - r * .25)
        ..lineTo(c.dx + r * .45, c.dy + r * .4);
      canvas.drawPath(path, p..strokeWidth = 2);
      return;
    }
    if (craft.material == SkinMaterial.tactical) {
      final frame = Path()
        ..moveTo(c.dx - r, c.dy - r * .35)
        ..lineTo(c.dx - r, c.dy - r)
        ..lineTo(c.dx - r * .35, c.dy - r)
        ..moveTo(c.dx + r * .35, c.dy - r)
        ..lineTo(c.dx + r, c.dy - r)
        ..lineTo(c.dx + r, c.dy - r * .35)
        ..moveTo(c.dx + r, c.dy + r * .35)
        ..lineTo(c.dx + r, c.dy + r)
        ..lineTo(c.dx + r * .35, c.dy + r)
        ..moveTo(c.dx - r * .35, c.dy + r)
        ..lineTo(c.dx - r, c.dy + r)
        ..lineTo(c.dx - r, c.dy + r * .35);
      canvas.drawPath(frame, p..strokeWidth = 1.4);
      canvas.drawCircle(
        c,
        r * .55,
        p
          ..color = craft.secondary.withValues(alpha: .5)
          ..strokeWidth = .8,
      );
      canvas.drawCircle(c, r * .12, Paint()..color = craft.accent);
      canvas.drawLine(
        Offset(c.dx - r * .72, c.dy),
        Offset(c.dx - r * .28, c.dy),
        p..color = craft.accent,
      );
      canvas.drawLine(
        Offset(c.dx + r * .28, c.dy),
        Offset(c.dx + r * .72, c.dy),
        p,
      );
      return;
    }
    if (craft.material == SkinMaterial.digitalStage) {
      canvas.drawCircle(c, r, p..color = craft.accent.withValues(alpha: .42));
      canvas.drawCircle(
        c,
        r * .72,
        p..color = craft.secondary.withValues(alpha: .34),
      );
      final wave = Path();
      for (var i = 0; i <= 20; i++) {
        final x = c.dx - r * .72 + r * 1.44 * i / 20;
        final y = c.dy + math.sin(i * math.pi * .45) * r * .2;
        i == 0 ? wave.moveTo(x, y) : wave.lineTo(x, y);
      }
      canvas.drawPath(
        wave,
        p
          ..color = craft.accent
          ..strokeWidth = 1.7,
      );
      for (var i = 0; i < 5; i++) {
        final x = c.dx - r * .44 + i * r * .22;
        final height = r * (.28 + (i.isEven ? .2 : 0));
        canvas.drawLine(
          Offset(x, c.dy - height),
          Offset(x, c.dy + height),
          p
            ..color = craft.secondary.withValues(alpha: .62)
            ..strokeWidth = .8,
        );
      }
      return;
    }
    if (craft.material == SkinMaterial.clockworkVoice) {
      canvas.drawCircle(c, r, p..color = craft.accent.withValues(alpha: .44));
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * .7),
        math.pi,
        math.pi,
        false,
        p
          ..color = craft.secondary.withValues(alpha: .72)
          ..strokeWidth = 1.3,
      );
      canvas.drawLine(
        c,
        c + Offset(r * .48, -r * .38),
        p
          ..color = craft.accent
          ..strokeWidth = 1.8,
      );
      canvas.drawCircle(c, r * .12, Paint()..color = craft.accent);
      for (var i = 0; i < 10; i++) {
        final a = i * math.pi * 2 / 10;
        final from = c + Offset(math.cos(a), math.sin(a)) * r * .88;
        final to = c + Offset(math.cos(a), math.sin(a)) * r * 1.08;
        canvas.drawLine(from, to, p..strokeWidth = i.isEven ? 1.3 : .7);
      }
      return;
    }
    canvas.drawCircle(c, r, p..color = craft.accent.withValues(alpha: .5));
    canvas.drawCircle(
      c,
      r * .76,
      p..color = craft.accent.withValues(alpha: .3),
    );
    final diamond = Path()
      ..moveTo(c.dx, c.dy - r * .65)
      ..lineTo(c.dx + r * .3, c.dy)
      ..lineTo(c.dx, c.dy + r * .65)
      ..lineTo(c.dx - r * .3, c.dy)
      ..close();
    canvas.drawPath(
      diamond,
      p
        ..color = craft.accent
        ..strokeWidth = 1.3,
    );
    canvas.drawLine(
      Offset(c.dx - r * .55, c.dy),
      Offset(c.dx + r * .55, c.dy),
      p,
    );
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final from = c + Offset(math.cos(a), math.sin(a)) * r * .9;
      final to = c + Offset(math.cos(a), math.sin(a)) * r * 1.1;
      canvas.drawLine(from, to, p..strokeWidth = .7);
    }
    if (craft.material == SkinMaterial.neon) {
      canvas.drawCircle(c, r * .14, Paint()..color = craft.secondary);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.2),
        -.7,
        .95,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) => old.craft != craft;
}
