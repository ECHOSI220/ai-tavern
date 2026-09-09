import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_craft.dart';
import 'theme_background.dart';

/// Visual-only capabilities. No session, repository, random source or API access.
@immutable
class CharacterThemeExtension extends ThemeExtension<CharacterThemeExtension> {
  const CharacterThemeExtension({
    required this.motion,
    required this.effects,
    this.gold = const Color(0xffdec48a),
    this.ivory = const Color(0xffeee8da),
    this.blue = const Color(0xffa4cdf0),
    this.ink = const Color(0xff203047),
    this.wine = const Color(0xff382031),
  });
  final bool motion, effects;
  final Color gold, ivory, blue, ink, wine;
  static CharacterThemeExtension? of(BuildContext context) =>
      Theme.of(context).extension<CharacterThemeExtension>();
  @override
  CharacterThemeExtension copyWith({bool? motion, bool? effects}) =>
      CharacterThemeExtension(
        motion: motion ?? this.motion,
        effects: effects ?? this.effects,
        gold: gold,
        ivory: ivory,
        blue: blue,
        ink: ink,
        wine: wine,
      );
  @override
  CharacterThemeExtension lerp(
    covariant CharacterThemeExtension? other,
    double t,
  ) => other == null || t < .5 ? this : other;
}

/// A bounded, slow, decoration-only animation; static at low/off/reduce motion.
class OathSigil extends StatefulWidget {
  const OathSigil({
    this.size = 40,
    this.color,
    this.phase,
    this.child,
    super.key,
  });
  final double size;
  final Color? color;
  final double? phase;
  final Widget? child;
  @override
  State<OathSigil> createState() => _OathSigilState();
}

class _OathSigilState extends State<OathSigil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CharacterThemeExtension.of(context);
    final moving =
        widget.phase == null &&
        (theme?.motion ?? false) &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (moving && !_turn.isAnimating) _turn.repeat();
    if (!moving && _turn.isAnimating) _turn.stop();
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _turn,
          child: widget.child,
          builder: (context, child) => CustomPaint(
            painter: OathCirclePainter(
              gold: widget.color ?? theme?.gold ?? Colors.amber,
              blue: theme?.blue ?? Colors.lightBlue,
              phase: widget.phase ?? (moving ? _turn.value : 0),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class OathCirclePainter extends CustomPainter {
  const OathCirclePainter({
    required this.gold,
    required this.blue,
    this.phase = 0,
  });
  final Color gold, blue;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), r = size.shortestSide * .46;
    if (r <= 0) return;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * math.pi * 2);
    canvas.drawCircle(Offset.zero, r, pen..color = gold.withValues(alpha: .7));
    canvas.drawCircle(
      Offset.zero,
      r * .88,
      pen..color = blue.withValues(alpha: .4),
    );
    final polygon = Path();
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 - math.pi / 2;
      final x = math.cos(a) * r * .78, y = math.sin(a) * r * .78;
      if (i == 0) {
        polygon.moveTo(x, y);
      } else {
        polygon.lineTo(x, y);
      }
    }
    canvas.drawPath(polygon..close(), pen..color = gold.withValues(alpha: .5));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(d * r * .94, d * r * (i.isEven ? 1.04 : 1.0), pen);
    }
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * .65),
      -.5,
      1,
      false,
      pen
        ..color = blue
        ..strokeWidth = 1.4,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OathCirclePainter old) =>
      phase != old.phase || gold != old.gold || blue != old.blue;
}

/// Drop-in loader: preserves caller dimensions, progress semantics and labels.
class ThemedLoadingIndicator extends StatelessWidget {
  const ThemedLoadingIndicator({
    this.strokeWidth = 4,
    this.value,
    this.color,
    this.semanticsLabel,
    super.key,
  });
  final double strokeWidth;
  final double? value;
  final Color? color;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) {
    if (CharacterThemeExtension.of(context) == null) {
      return CircularProgressIndicator(
        strokeWidth: strokeWidth,
        value: value,
        color: color,
        semanticsLabel: semanticsLabel,
      );
    }
    return Semantics(
      label: semanticsLabel ?? '正在加载',
      value: value == null ? null : '${(value! * 100).round()}%',
      child: OathSigil(
        color: color ?? Theme.of(context).colorScheme.primary,
        child: const FractionallySizedBox(
          widthFactor: .42,
          heightFactor: .42,
          child: FittedBox(child: CraftEmblem()),
        ),
      ),
    );
  }
}

/// Uses the existing die result and rotation, never rolls or mutates a die.
class ThemedDiceCard extends StatelessWidget {
  const ThemedDiceCard({
    required this.child,
    this.failure = false,
    this.critical = false,
    this.phase = 0,
    this.size = 188,
    super.key,
  });
  final Widget child;
  final bool failure, critical;
  final double phase;
  final double size;
  @override
  Widget build(BuildContext context) {
    final theme = CharacterThemeExtension.of(context);
    if (theme == null) return child;
    final base = failure ? theme.wine : theme.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failure ? const Color(0xffc68888) : theme.gold,
        ),
        gradient: RadialGradient(
          colors: [
            Color.lerp(
              base,
              failure ? const Color(0xffc68888) : theme.blue,
              .3,
            )!,
            Color.lerp(base, Colors.black, .3)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: OathSigil(
          size: size,
          phase: theme.motion && !MediaQuery.disableAnimationsOf(context)
              ? phase
              : 0,
          color: failure ? const Color(0xffde9a9a) : theme.gold,
          child: Stack(
            alignment: Alignment.center,
            children: [
              child,
              if (critical)
                const Positioned(
                  top: 0,
                  child: ExcludeSemantics(child: CraftEmblem(size: 30)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Retains Material's label gap, adds a sword-like focus line inside the field.
class OathInputBorder extends OutlineInputBorder {
  const OathInputBorder({
    super.borderSide,
    super.borderRadius,
    super.gapPadding,
    this.focused = false,
  });
  final bool focused;
  @override
  OathInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => OathInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
    focused: focused,
  );
  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    if (!focused || rect.width < 60) return;
    final start = Offset(rect.left + 20, rect.bottom - 4);
    final end = Offset(rect.right - 20, rect.bottom - 4);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..strokeWidth = 1
        ..shader =
            LinearGradient(
              colors: [
                borderSide.color.withValues(alpha: 0),
                borderSide.color,
                borderSide.color.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromPoints(
                start - const Offset(0, 1),
                end + const Offset(0, 1),
              ),
            ),
    );
  }
}

class OathPageTransitionsBuilder extends PageTransitionsBuilder {
  const OathPageTransitionsBuilder({required this.enabled});
  final bool enabled;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Character skins use transparent Scaffolds so their artwork can remain
    // visible. Fading that whole transparent route exposed the previous page
    // and produced a stacked, frozen-looking frame during every navigation.
    // Give each route its own opaque wallpaper and animate only a tiny content
    // offset. This avoids a full-screen opacity saveLayer and keeps the old
    // route completely hidden throughout push and pop transitions.
    final reduceMotion = !enabled || MediaQuery.disableAnimationsOf(context);
    final page = RepaintBoundary(child: child);
    return ThemeBackground(
      key: const ValueKey('character-route-background'),
      child: reduceMotion
          ? page
          : ClipRect(
              child: SlideTransition(
                position: animation.drive(
                  Tween<Offset>(
                    begin: const Offset(0, .012),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: page,
              ),
            ),
    );
  }
}
