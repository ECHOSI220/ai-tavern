import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_craft.dart';

/// Original, Fate-inspired heraldry, drawn on a 24px grid. Semantic meaning and
/// hit targets stay with the existing buttons; other skins keep Material icons.
enum OathGlyph {
  sword,
  seal,
  grail,
  book,
  crown,
  party,
  dice,
  bag,
  scroll,
  search,
  world,
  settings,
  send,
  chat,
}

class SkinIcon extends StatelessWidget {
  const SkinIcon(
    this.icon, {
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  static OathGlyph? glyphFor(IconData? icon) => _glyphs[icon];
  static final _glyphs = <IconData, OathGlyph>{
    Icons.explore_outlined: OathGlyph.sword,
    Icons.explore: OathGlyph.sword,
    Icons.auto_awesome: OathGlyph.grail,
    Icons.auto_awesome_outlined: OathGlyph.grail,
    Icons.lock_outline: OathGlyph.seal,
    Icons.lock_outlined: OathGlyph.seal,
    Icons.lock: OathGlyph.seal,
    Icons.menu_book_outlined: OathGlyph.book,
    Icons.menu_book: OathGlyph.book,
    Icons.book_outlined: OathGlyph.book,
    Icons.person_outline: OathGlyph.crown,
    Icons.person_outlined: OathGlyph.crown,
    Icons.person: OathGlyph.crown,
    Icons.badge_outlined: OathGlyph.crown,
    Icons.groups_outlined: OathGlyph.party,
    Icons.groups: OathGlyph.party,
    Icons.people_outline: OathGlyph.party,
    Icons.casino_outlined: OathGlyph.dice,
    Icons.casino: OathGlyph.dice,
    Icons.backpack_outlined: OathGlyph.bag,
    Icons.inventory_2_outlined: OathGlyph.bag,
    Icons.assignment_outlined: OathGlyph.scroll,
    Icons.receipt_long_outlined: OathGlyph.scroll,
    Icons.task_alt: OathGlyph.scroll,
    Icons.edit_note: OathGlyph.scroll,
    Icons.search: OathGlyph.search,
    Icons.manage_search: OathGlyph.search,
    Icons.public: OathGlyph.world,
    Icons.map_outlined: OathGlyph.world,
    Icons.settings_outlined: OathGlyph.settings,
    Icons.settings: OathGlyph.settings,
    Icons.send: OathGlyph.send,
    Icons.arrow_upward_rounded: OathGlyph.send,
    Icons.chat_outlined: OathGlyph.chat,
    Icons.chat_bubble_outline: OathGlyph.chat,
    Icons.forum_outlined: OathGlyph.chat,
  };

  @override
  Widget build(BuildContext context) {
    final glyph = glyphFor(icon);
    final material = SkinCraft.of(context).material;
    if ((material != SkinMaterial.oath && material != SkinMaterial.tactical) ||
        glyph == null) {
      return Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    }
    final inherited = IconTheme.of(context);
    final tint =
        color ?? inherited.color ?? Theme.of(context).colorScheme.onSurface;
    final dimension = size ?? inherited.size ?? 24;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: material == SkinMaterial.tactical
                ? TacticalIconPainter(
                    glyph,
                    tint.withValues(alpha: tint.a * (inherited.opacity ?? 1)),
                  )
                : OathIconPainter(
                    glyph,
                    tint.withValues(alpha: tint.a * (inherited.opacity ?? 1)),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Angular 24px combat-terminal glyphs used only by the Rapi skin.
class TacticalIconPainter extends CustomPainter {
  const TacticalIconPainter(this.glyph, this.color);
  final OathGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final fill = Paint()..color = color;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pen);
    void polygon(List<Offset> points, {bool solid = false}) =>
        canvas.drawPath(Path()..addPolygon(points, true), solid ? fill : pen);

    // Shared targeting corners keep unrelated semantic icons in one system.
    line(2, 7, 2, 2);
    line(2, 2, 7, 2);
    line(22, 17, 22, 22);
    line(22, 22, 17, 22);

    switch (glyph) {
      case OathGlyph.sword:
      case OathGlyph.send:
        polygon(const [Offset(5, 12), Offset(19, 5), Offset(15, 19)]);
        line(8, 12, 16, 8);
        line(8, 12, 14, 14);
        if (glyph == OathGlyph.sword) {
          canvas.drawCircle(const Offset(12, 12), 8, pen..strokeWidth = .65);
        }
      case OathGlyph.seal:
        canvas.drawRect(const Rect.fromLTWH(6, 10, 12, 9), pen);
        canvas.drawArc(
          const Rect.fromLTWH(8, 4, 8, 11),
          math.pi,
          math.pi,
          false,
          pen,
        );
        canvas.drawCircle(const Offset(12, 14), 1.4, fill);
        line(12, 15, 12, 17);
      case OathGlyph.grail:
        canvas.drawCircle(const Offset(12, 12), 6, pen);
        canvas.drawCircle(const Offset(12, 12), 1.5, fill);
        for (final a in [0.0, math.pi / 2, math.pi, math.pi * 1.5]) {
          line(
            12 + math.cos(a) * 8,
            12 + math.sin(a) * 8,
            12 + math.cos(a) * 10,
            12 + math.sin(a) * 10,
          );
        }
      case OathGlyph.book:
        polygon(const [
          Offset(5, 5),
          Offset(11, 5),
          Offset(12, 7),
          Offset(13, 5),
          Offset(19, 5),
          Offset(19, 19),
          Offset(13, 19),
          Offset(12, 21),
          Offset(11, 19),
          Offset(5, 19),
        ]);
        line(12, 7, 12, 20);
        line(7, 9, 10, 9);
        line(14, 9, 17, 9);
      case OathGlyph.crown:
        canvas.drawCircle(const Offset(12, 8), 3, pen);
        polygon(const [
          Offset(6, 19),
          Offset(7, 14),
          Offset(12, 12),
          Offset(17, 14),
          Offset(18, 19),
        ]);
        line(8, 19, 16, 19);
      case OathGlyph.party:
        for (final center in const [
          Offset(6.5, 9),
          Offset(12, 6.5),
          Offset(17.5, 9),
        ]) {
          canvas.drawCircle(center, 2, pen);
          line(center.dx - 2.6, center.dy + 5, center.dx + 2.6, center.dy + 5);
        }
      case OathGlyph.dice:
        polygon(const [
          Offset(12, 3),
          Offset(20, 8),
          Offset(18, 18),
          Offset(12, 21),
          Offset(5, 17),
          Offset(4, 8),
        ]);
        canvas.drawCircle(const Offset(12, 12), 1.5, fill);
        canvas.drawCircle(const Offset(8, 9), 1, fill);
        canvas.drawCircle(const Offset(16, 15), 1, fill);
      case OathGlyph.bag:
        polygon(const [
          Offset(5, 8),
          Offset(19, 8),
          Offset(19, 20),
          Offset(5, 20),
        ]);
        canvas.drawArc(
          const Rect.fromLTWH(8, 3, 8, 9),
          math.pi,
          math.pi,
          false,
          pen,
        );
        line(8, 13, 16, 13);
      case OathGlyph.scroll:
        polygon(const [
          Offset(6, 3),
          Offset(18, 3),
          Offset(20, 5),
          Offset(20, 21),
          Offset(6, 21),
        ]);
        line(9, 8, 17, 8);
        line(9, 12, 17, 12);
        line(9, 16, 14, 16);
      case OathGlyph.search:
        canvas.drawCircle(const Offset(10, 10), 6, pen);
        line(14.5, 14.5, 21, 21);
        line(10, 6, 10, 14);
        line(6, 10, 14, 10);
      case OathGlyph.world:
        canvas.drawCircle(const Offset(12, 12), 8, pen);
        canvas.drawArc(
          const Rect.fromLTWH(7, 4, 10, 16),
          -math.pi / 2,
          math.pi,
          false,
          pen,
        );
        line(4, 12, 20, 12);
        canvas.drawCircle(const Offset(12, 12), 1.4, fill);
      case OathGlyph.settings:
        canvas.drawCircle(const Offset(12, 12), 6, pen);
        canvas.drawCircle(const Offset(12, 12), 2, pen);
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          line(
            12 + math.cos(a) * 7,
            12 + math.sin(a) * 7,
            12 + math.cos(a) * 10,
            12 + math.sin(a) * 10,
          );
        }
      case OathGlyph.chat:
        polygon(const [
          Offset(4, 5),
          Offset(20, 5),
          Offset(20, 17),
          Offset(10, 17),
          Offset(5, 21),
          Offset(5, 17),
          Offset(4, 17),
        ]);
        line(8, 10, 16, 10);
        line(8, 13, 13, 13);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TacticalIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}

class OathIconPainter extends CustomPainter {
  const OathIconPainter(this.glyph, this.color);
  final OathGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.45
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), pen);
    void path(List<Offset> points, {bool closed = false, bool solid = false}) {
      final p = Path()..addPolygon(points, closed);
      canvas.drawPath(p, solid ? fill : pen);
    }

    void diamond(double x, double y, double r) => path(
      [Offset(x, y - r), Offset(x + r, y), Offset(x, y + r), Offset(x - r, y)],
      closed: true,
      solid: true,
    );
    void shield(double x, double y, double scale) {
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(8, 0)
          ..lineTo(8, 5)
          ..quadraticBezierTo(8, 9, 4, 11)
          ..quadraticBezierTo(0, 9, 0, 5)
          ..close(),
        pen,
      );
      line(4, 2, 4, 7);
      canvas.restore();
    }

    switch (glyph) {
      case OathGlyph.sword:
      case OathGlyph.send:
        path(const [
          Offset(12, 2),
          Offset(15, 7),
          Offset(13, 15),
          Offset(11, 15),
          Offset(9, 7),
        ], closed: true);
        line(12, 5, 12, 14);
        path(const [
          Offset(6, 16),
          Offset(9, 14),
          Offset(15, 14),
          Offset(18, 16),
        ]);
        line(12, 16, 12, 20);
        diamond(12, 21, 1.3);
        if (glyph == OathGlyph.sword) {
          line(4, 7, 4, 11);
          line(20, 7, 20, 11);
        } else {
          path(const [Offset(4, 10), Offset(6, 7), Offset(7, 8)]);
          path(const [Offset(20, 10), Offset(18, 7), Offset(17, 8)]);
        }
      case OathGlyph.seal:
        // A three-part angular seal surrounds a clearly readable keyhole.
        path(const [
          Offset(12, 2),
          Offset(17, 6),
          Offset(15, 9),
          Offset(12, 6),
          Offset(9, 9),
          Offset(7, 6),
        ], closed: true);
        path(const [
          Offset(5, 9),
          Offset(8, 11),
          Offset(7, 17),
          Offset(10, 20),
          Offset(4, 18),
        ], closed: true);
        path(const [
          Offset(19, 9),
          Offset(16, 11),
          Offset(17, 17),
          Offset(14, 20),
          Offset(20, 18),
        ], closed: true);
        canvas.drawCircle(const Offset(12, 12), 1.6, pen);
        line(12, 14, 12, 17);
      case OathGlyph.grail:
        path(const [
          Offset(6, 5),
          Offset(18, 5),
          Offset(16, 11),
          Offset(12, 14),
          Offset(8, 11),
        ], closed: true);
        line(12, 14, 12, 19);
        path(const [
          Offset(8, 21),
          Offset(9, 19),
          Offset(15, 19),
          Offset(16, 21),
        ]);
        line(5, 8, 3, 6);
        line(19, 8, 21, 6);
        diamond(12, 2, 1.2);
      case OathGlyph.book:
        path(const [
          Offset(3, 4),
          Offset(9, 4),
          Offset(12, 6),
          Offset(15, 4),
          Offset(21, 4),
          Offset(21, 19),
          Offset(15, 19),
          Offset(12, 21),
          Offset(9, 19),
          Offset(3, 19),
        ], closed: true);
        line(12, 6, 12, 20);
        diamond(7.5, 10.5, 2);
        line(16, 9, 18, 9);
        line(16, 12, 18, 12);
        line(6, 16, 9, 16);
      case OathGlyph.crown:
        shield(7.4, 9, 1.15);
        path(const [
          Offset(5, 7),
          Offset(4, 3),
          Offset(9, 5),
          Offset(12, 2),
          Offset(15, 5),
          Offset(20, 3),
          Offset(19, 7),
        ], closed: true);
        diamond(12, 14, 2);
      case OathGlyph.party:
        shield(2, 6, 1);
        shield(14, 6, 1);
        shield(8, 11, 1);
        diamond(12, 3, 1.3);
      case OathGlyph.dice:
        final vertices = List.generate(
          6,
          (i) => Offset(
            12 + 10 * math.cos(-math.pi / 2 + i * math.pi / 3),
            12 + 10 * math.sin(-math.pi / 2 + i * math.pi / 3),
          ),
        );
        path(vertices, closed: true);
        path([vertices[0], vertices[2], vertices[4]], closed: true);
        line(vertices[1].dx, vertices[1].dy, vertices[2].dx, vertices[2].dy);
        diamond(12, 12, 1.5);
      case OathGlyph.bag:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 7, 14, 14),
            const Radius.circular(2),
          ),
          pen,
        );
        canvas.drawArc(
          const Rect.fromLTWH(8, 2, 8, 10),
          math.pi,
          math.pi,
          false,
          pen,
        );
        line(5, 12, 19, 12);
        diamond(12, 13, 1.6);
        line(9, 18, 15, 18);
      case OathGlyph.scroll:
        canvas.drawPath(
          Path()
            ..moveTo(7, 3)
            ..lineTo(18, 3)
            ..quadraticBezierTo(21, 3, 21, 7)
            ..lineTo(8, 7)
            ..lineTo(8, 18)
            ..quadraticBezierTo(8, 22, 4, 21)
            ..quadraticBezierTo(1, 20, 3, 17)
            ..lineTo(6, 17),
          pen,
        );
        line(18, 8, 18, 19);
        line(6, 21, 16, 21);
        line(11, 11, 15, 11);
        line(11, 14, 15, 14);
      case OathGlyph.search:
        canvas.drawCircle(const Offset(10, 10), 6.5, pen);
        diamond(10, 10, 2);
        line(15, 15, 21, 21);
        line(17, 19, 19, 17);
      case OathGlyph.world:
        canvas.drawCircle(const Offset(12, 12), 8, pen);
        canvas.drawOval(const Rect.fromLTWH(8, 4, 8, 16), pen);
        line(4, 12, 20, 12);
        diamond(12, 2, 1.4);
        diamond(12, 22, 1.4);
      case OathGlyph.settings:
        canvas.drawCircle(const Offset(12, 12), 6, pen);
        canvas.drawCircle(const Offset(12, 12), 2, pen);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            12 + 8 * math.cos(a),
            12 + 8 * math.sin(a),
            12 + 10 * math.cos(a),
            12 + 10 * math.sin(a),
          );
        }
      case OathGlyph.chat:
        path(const [
          Offset(3, 4),
          Offset(21, 4),
          Offset(21, 17),
          Offset(9, 17),
          Offset(4, 21),
          Offset(4, 17),
          Offset(3, 17),
        ], closed: true);
        diamond(12, 10, 2.5);
        line(6, 10, 7, 10);
        line(17, 10, 18, 10);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OathIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
