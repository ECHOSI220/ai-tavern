import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'theme_catalog.dart';
import 'theme_definition.dart';
import 'theme_manager.dart';
import 'theme_preferences.dart';
import 'theme_craft.dart';
import 'theme_asset_pipeline.dart';

/// Shared by preloading and painting so both resolve the same image-cache key.
ImageProvider? skinBackgroundImage(
  BuildContext context,
  ThemeDefinition definition,
  ThemeSettings settings, {
  bool chat = false,
  Size? viewport,
}) {
  final path =
      (chat ? settings.chatBackground : null) ?? settings.customBackground;
  final size = viewport ?? MediaQuery.sizeOf(context);
  final portrait =
      definition.portraitBackgroundImage != null &&
      size.width < size.height * .95;
  final bundled = ThemeAssetPipeline.imagePath(
    definition.assetManifest,
    portrait
        ? 'bg_portrait'
        : chat
        ? 'bg_chat'
        : 'bg_main',
    portrait
        ? definition.portraitBackgroundImage
        : (chat ? definition.chatBackgroundImage : null) ??
              definition.backgroundImage,
  );
  final ImageProvider? source = path != null
      ? FileImage(File(path))
      : bundled != null
      ? AssetImage(bundled)
      : null;
  if (source == null) return null;
  final width =
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .clamp(320, 1920)
          .round();
  // Bundled paintings share the header's cache key and retain enough detail
  // when a portrait viewport crops the landscape master. Custom art is bounded.
  return ResizeImage(
    source,
    width: path == null ? (portrait ? 1024 : 1536) : width,
    allowUpscaling: false,
  );
}

class ThemeBackground extends StatefulWidget {
  const ThemeBackground({
    required this.child,
    this.definition,
    this.settings,
    this.chat = false,
    super.key,
  });
  final Widget child;
  final ThemeDefinition? definition;
  final ThemeSettings? settings;
  final bool chat;
  @override
  State<ThemeBackground> createState() => _ThemeBackgroundState();
}

class _ThemeBackgroundState extends State<ThemeBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ThemeScope.maybeOf(context);
    final definition =
        widget.definition ??
        manager?.getCurrentTheme() ??
        ThemeCatalog.byId('classic_tavern');
    final settings =
        widget.settings ?? manager?.settings ?? const ThemeSettings();
    final tokens = definition.tokens(MediaQuery.platformBrightnessOf(context));
    final shouldAnimate =
        definition.animatedBackground &&
        settings.animated &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate && !_animation.isAnimating) _animation.repeat();
    if (!shouldAnimate && _animation.isAnimating) _animation.stop();
    final opacity = settings.opacity ?? definition.backgroundOpacity;
    final blur = settings.complexEffects && !settings.reduceMotion
        ? settings.blur ?? definition.backgroundBlur
        : 0.0;
    final overlay = settings.overlay ?? definition.overlayOpacity;
    final character = ThemeAssetPipeline.imagePath(
      definition.assetManifest,
      'character',
      definition.characterImage,
    );
    return ColoredBox(
      color: tokens.backgroundPrimary,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: _WallpaperCanvas(
                  pageSize: MediaQuery.sizeOf(context),
                  alignToPage:
                      widget.chat &&
                      definition.immersiveArtwork &&
                      settings.chatBackground == null &&
                      settings.customBackground == null,
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final portraitArtwork =
                            definition.portraitBackgroundImage != null &&
                            bounds.maxWidth < bounds.maxHeight * .95 &&
                            settings.customBackground == null &&
                            (!widget.chat || settings.chatBackground == null);
                        final image = skinBackgroundImage(
                          context,
                          definition,
                          settings,
                          chat: widget.chat,
                          viewport: bounds.biggest,
                        );
                        final pattern = AnimatedBuilder(
                          animation: _animation,
                          builder: (context, _) => CustomPaint(
                            painter: SkinBackdropPainter(
                              pattern:
                                  settings.effectsLevel == ThemeEffectsLevel.off
                                  ? BackgroundPattern.plain
                                  : definition.pattern,
                              primary: tokens.accentPrimary,
                              secondary: tokens.accentSecondary,
                              phase: shouldAnimate ? _animation.value : 0,
                              dense:
                                  settings.effectsLevel ==
                                  ThemeEffectsLevel.high,
                            ),
                          ),
                        );
                        Widget background = pattern;
                        if (image != null) {
                          background = Image(
                            key:
                                definition.immersiveArtwork &&
                                    settings.customBackground == null &&
                                    (!widget.chat ||
                                        settings.chatBackground == null)
                                ? const ValueKey('skin-integrated-wallpaper')
                                : null,
                            image: image,
                            fit: BoxFit.cover,
                            alignment:
                                settings.customBackground != null ||
                                    (widget.chat &&
                                        settings.chatBackground != null)
                                ? Alignment.center
                                : definition.artworkAlignment,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => pattern,
                          );
                          if (portraitArtwork &&
                              definition.portraitArtworkScale > 1) {
                            background = Transform.scale(
                              scale: definition.portraitArtworkScale,
                              alignment: Alignment.centerRight,
                              child: background,
                            );
                          }
                        }
                        return ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: opacity,
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: blur,
                                    sigmaY: blur,
                                  ),
                                  enabled: blur > 0,
                                  child: background,
                                ),
                              ),
                              if (definition.material == SkinMaterial.neon &&
                                  settings.effectsLevel !=
                                      ThemeEffectsLevel.off)
                                AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, _) => CustomPaint(
                                    painter: CyberFlowPainter(
                                      primary: tokens.accentPrimary,
                                      secondary: tokens.accentSecondary,
                                      phase: shouldAnimate
                                          ? _animation.value
                                          : 0,
                                      dense:
                                          settings.effectsLevel ==
                                          ThemeEffectsLevel.high,
                                    ),
                                  ),
                                ),
                              if (definition.id == 'rapi_tactical_command' &&
                                  settings.effectsLevel !=
                                      ThemeEffectsLevel.off)
                                AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, _) => CustomPaint(
                                    painter: RapiTacticalPainter(
                                      signal: tokens.accentPrimary,
                                      neutral: tokens.accentSecondary,
                                      phase: shouldAnimate
                                          ? _animation.value
                                          : 0,
                                      dense:
                                          settings.effectsLevel ==
                                          ThemeEffectsLevel.high,
                                    ),
                                  ),
                                ),
                              if ((definition.material ==
                                          SkinMaterial.digitalStage ||
                                      definition.material ==
                                          SkinMaterial.clockworkVoice) &&
                                  settings.effectsLevel !=
                                      ThemeEffectsLevel.off)
                                AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, _) => CustomPaint(
                                    painter: VocalSkinMotionPainter(
                                      material: definition.material,
                                      primary: tokens.accentPrimary,
                                      secondary: tokens.accentSecondary,
                                      phase: shouldAnimate
                                          ? _animation.value
                                          : 0,
                                      dense:
                                          settings.effectsLevel ==
                                          ThemeEffectsLevel.high,
                                    ),
                                  ),
                                ),
                              ColoredBox(
                                color: tokens.overlay.withValues(
                                  alpha: overlay,
                                ),
                              ),
                              // Calm reading canvas. Keep an opaque backing below
                              // this tint; never expose an unpainted viewport.
                              if (image != null)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        tokens.backgroundPrimary.withValues(
                                          alpha: definition.immersiveArtwork
                                              ? (widget.chat ? .2 : .04)
                                              : widget.chat
                                              ? .48
                                              : .38,
                                        ),
                                        tokens.backgroundPrimary.withValues(
                                          alpha: definition.immersiveArtwork
                                              ? (widget.chat ? .48 : .32)
                                              : widget.chat
                                              ? .88
                                              : .9,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // A quiet character watermark, behind all content.
                              // Respect custom wallpapers and background opacity.
                              // One shared image, not a portrait on every message.
                              if (widget.chat &&
                                  !definition.immersiveArtwork &&
                                  character != null &&
                                  settings.chatBackground == null &&
                                  settings.customBackground == null)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  width: math.min(bounds.maxWidth * .7, 400),
                                  height: math.min(bounds.maxHeight, 560),
                                  child: Opacity(
                                    opacity: .24 * opacity,
                                    child: Image.asset(
                                      character,
                                      key: const ValueKey(
                                        'skin-chat-character-watermark',
                                      ),
                                      fit: BoxFit.contain,
                                      alignment: Alignment.bottomRight,
                                      cacheWidth: 768,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              if (settings.brightness < 1)
                                ColoredBox(
                                  color: Colors.black.withValues(
                                    alpha: 1 - settings.brightness,
                                  ),
                                ),
                              if (settings.brightness > 1)
                                ColoredBox(
                                  color: Colors.white.withValues(
                                    alpha: (settings.brightness - 1) * .5,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Nested reading surfaces show the same slice of the full-page illustration,
/// not a second face starting below the scene banner. No state or image copies.
class _WallpaperCanvas extends SingleChildRenderObjectWidget {
  const _WallpaperCanvas({
    required this.pageSize,
    required this.alignToPage,
    required super.child,
  });
  final Size pageSize;
  final bool alignToPage;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWallpaperCanvas(pageSize, alignToPage);
  @override
  void updateRenderObject(BuildContext context, _RenderWallpaperCanvas object) {
    object.configure(pageSize, alignToPage);
  }
}

class _RenderWallpaperCanvas extends RenderProxyBox {
  _RenderWallpaperCanvas(this._pageSize, this._alignToPage);
  Size _pageSize;
  bool _alignToPage;
  void configure(Size pageSize, bool alignToPage) {
    if (_pageSize == pageSize && _alignToPage == alignToPage) return;
    _pageSize = pageSize;
    _alignToPage = alignToPage;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (!_alignToPage) {
      super.performLayout();
      return;
    }
    child?.layout(BoxConstraints.tight(_pageSize));
    size = constraints.constrain(_pageSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_alignToPage) {
      super.paint(context, offset);
      return;
    }
    final shift = localToGlobal(Offset.zero);
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      paintOffset,
    ) {
      if (child != null) context.paintChild(child!, paintOffset - shift);
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!_alignToPage) {
      super.applyPaintTransform(child, transform);
      return;
    }
    final shift = localToGlobal(Offset.zero);
    transform.translateByDouble(-shift.dx, -shift.dy, 0, 1);
  }
}

/// Restrained animated light trails for the cyber skin. It is painted below the reading veil.
class CyberFlowPainter extends CustomPainter {
  const CyberFlowPainter({
    required this.primary,
    required this.secondary,
    this.phase = 0,
    this.dense = false,
  });
  final Color primary, secondary;
  final double phase;
  final bool dense;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height, cycle = phase * math.pi * 2;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < (dense ? 8 : 5); i++) {
      final y = h * (.18 + i * .16) + math.sin(cycle + i * 1.7) * h * .025;
      final drift = math.sin(cycle * .7 + i) * w * .08;
      final path = Path()
        ..moveTo(-w * .12 + drift, y + h * .04)
        ..cubicTo(
          w * .22 + drift,
          y - h * .07,
          w * .52 + drift,
          y + h * .09,
          w * 1.08 + drift,
          y - h * .04,
        );
      final color = i.isEven ? primary : secondary;
      trail
        ..strokeWidth = i == 1 ? 2.2 : 1.1
        ..color = color.withValues(alpha: dense ? .16 : .105)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i == 1 ? 8 : 4);
      canvas.drawPath(path, trail);
      trail
        ..strokeWidth = .55
        ..color = color.withValues(alpha: dense ? .38 : .22)
        ..maskFilter = null;
      canvas.drawPath(path, trail);
    }
    for (var i = 0; i < 3; i++) {
      final x = w * (.14 + i * .37) + math.sin(cycle + i) * 12;
      final y = h * (.12 + i * .31);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + w * .06, y),
        Paint()
          ..color = (i.isEven ? primary : secondary).withValues(alpha: .28)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CyberFlowPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.dense != dense;
}

/// Rapi's restrained combat HUD: a moving scan rail and quiet targeting marks.
/// It is decorative, clipped to the wallpaper and never receives input.
class RapiTacticalPainter extends CustomPainter {
  const RapiTacticalPainter({
    required this.signal,
    required this.neutral,
    this.phase = 0,
    this.dense = false,
  });

  final Color signal, neutral;
  final double phase;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final scanY = ((phase * 1.15) % 1) * h;
    final scan = Paint()
      ..shader = LinearGradient(
        colors: [
          signal.withValues(alpha: 0),
          signal.withValues(alpha: dense ? .2 : .13),
          signal.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 22, w, 44));
    canvas.drawRect(Rect.fromLTWH(0, scanY - 22, w, 44), scan);
    canvas.drawLine(
      Offset(0, scanY),
      Offset(w, scanY),
      Paint()
        ..color = signal.withValues(alpha: dense ? .42 : .28)
        ..strokeWidth = .8,
    );

    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = neutral.withValues(alpha: .16);
    final center = Offset(w * .18, h * .24);
    final radius = math.min(w, h) * .09;
    canvas.drawCircle(center, radius, pen);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .72),
      phase * math.pi * 2,
      1.15,
      false,
      pen
        ..color = signal.withValues(alpha: .36)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      center - Offset(radius * 1.28, 0),
      center - Offset(radius * .62, 0),
      pen,
    );
    canvas.drawLine(
      center + Offset(radius * .62, 0),
      center + Offset(radius * 1.28, 0),
      pen,
    );
    canvas.drawLine(
      center - Offset(0, radius * 1.28),
      center - Offset(0, radius * .62),
      pen,
    );
    canvas.drawLine(
      center + Offset(0, radius * .62),
      center + Offset(0, radius * 1.28),
      pen,
    );

    for (var i = 0; i < (dense ? 6 : 4); i++) {
      final y = h * (.58 + i * .075);
      final x = w * (.06 + (i.isEven ? 0 : .035));
      canvas.drawLine(
        Offset(x, y),
        Offset(x + w * (.09 + i * .012), y),
        pen
          ..color = (i == 0 ? signal : neutral).withValues(alpha: .24)
          ..strokeWidth = i == 0 ? 1.6 : .7,
      );
    }

    final corner = Path()
      ..moveTo(w * .04, h * .1)
      ..lineTo(w * .04, h * .07)
      ..lineTo(w * .11, h * .07)
      ..moveTo(w * .89, h * .92)
      ..lineTo(w * .96, h * .92)
      ..lineTo(w * .96, h * .89);
    canvas.drawPath(
      corner,
      pen
        ..color = signal.withValues(alpha: .3)
        ..strokeWidth = 1.15,
    );
  }

  @override
  bool shouldRepaint(covariant RapiTacticalPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.signal != signal ||
      oldDelegate.neutral != neutral ||
      oldDelegate.dense != dense;
}

/// Lightweight audio motion shared by the two vocal character skins. Miku
/// receives flowing digital equalizers; Teto receives a warm VU needle and
/// oscilloscope trace. The layer is decorative and isolated from scrolling.
class VocalSkinMotionPainter extends CustomPainter {
  const VocalSkinMotionPainter({
    required this.material,
    required this.primary,
    required this.secondary,
    this.phase = 0,
    this.dense = false,
  });

  final SkinMaterial material;
  final Color primary, secondary;
  final double phase;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final cycle = phase * math.pi * 2;
    if (material == SkinMaterial.digitalStage) {
      final wave = Path();
      for (var i = 0; i <= 48; i++) {
        final x = w * i / 48;
        final envelope = .5 + .5 * math.sin(i * .31 + cycle * .55);
        final y = h * .72 + math.sin(i * .54 + cycle) * h * .012 * envelope;
        i == 0 ? wave.moveTo(x, y) : wave.lineTo(x, y);
      }
      canvas.drawPath(
        wave,
        Paint()
          ..color = primary.withValues(alpha: dense ? .34 : .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        wave,
        Paint()
          ..color = secondary.withValues(alpha: dense ? .48 : .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .55,
      );
      final count = dense ? 22 : 14;
      for (var i = 0; i < count; i++) {
        final x = w * (.06 + i / count * .5);
        final level =
            .018 + (.5 + .5 * math.sin(cycle * 1.25 + i * .9)) * h * .024;
        canvas.drawLine(
          Offset(x, h * .89 - level),
          Offset(x, h * .89 + level),
          Paint()
            ..color = (i.isEven ? primary : secondary).withValues(alpha: .22)
            ..strokeWidth = 1.4,
        );
      }
      return;
    }

    final meterCenter = Offset(w * .2, h * .78);
    final radius = math.min(w * .14, 88.0);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = secondary.withValues(alpha: .2);
    canvas.drawArc(
      Rect.fromCircle(center: meterCenter, radius: radius),
      math.pi * 1.12,
      math.pi * .76,
      false,
      pen,
    );
    final angle = math.pi * (1.18 + .64 * (.5 + .5 * math.sin(cycle)));
    canvas.drawLine(
      meterCenter,
      meterCenter + Offset(math.cos(angle), math.sin(angle)) * radius * .82,
      pen
        ..color = primary.withValues(alpha: dense ? .52 : .36)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      meterCenter,
      3,
      Paint()..color = secondary.withValues(alpha: .55),
    );
    final trace = Path();
    for (var i = 0; i <= 40; i++) {
      final x = w * (.48 + .48 * i / 40);
      final y =
          h * .16 +
          math.sin(i * .63 + cycle * .8) * h * .008 * (i % 7 == 0 ? 2.2 : 1);
      i == 0 ? trace.moveTo(x, y) : trace.lineTo(x, y);
    }
    canvas.drawPath(
      trace,
      pen
        ..color = primary.withValues(alpha: dense ? .36 : .23)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant VocalSkinMotionPainter oldDelegate) =>
      material != oldDelegate.material ||
      primary != oldDelegate.primary ||
      secondary != oldDelegate.secondary ||
      phase != oldDelegate.phase ||
      dense != oldDelegate.dense;
}

/// Small deterministic vector motifs. No downloaded image, GPU backdrop blur,
/// particle allocation or scripts. Only the decorative layer repaints.
class SkinBackdropPainter extends CustomPainter {
  const SkinBackdropPainter({
    required this.pattern,
    required this.primary,
    required this.secondary,
    this.phase = 0,
    this.dense = false,
  });
  final BackgroundPattern pattern;
  final Color primary, secondary;
  final double phase;
  final bool dense;
  @override
  void paint(Canvas canvas, Size size) {
    if (pattern == BackgroundPattern.plain || size.isEmpty) return;
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = primary.withValues(alpha: .3)
      ..strokeWidth = 1;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: .18),
            secondary.withValues(alpha: .03),
          ],
          center: const Alignment(.7, -.7),
          radius: 1.5,
        ).createShader(Offset.zero & size),
    );
    switch (pattern) {
      case BackgroundPattern.city:
        _city(canvas, size);
      case BackgroundPattern.stars:
        for (var i = 0; i < (dense ? 70 : 35); i++) {
          canvas.drawCircle(
            Offset(((i * 97) % 991) / 991 * w, ((i * 137) % 997) / 997 * h),
            i % 5 == 0 ? 2 : 1,
            paint..color = primary.withValues(alpha: .7),
          );
        }
      case BackgroundPattern.wood:
        _tavern(canvas, size);
      case BackgroundPattern.arches:
        for (var i = 0; i < 4; i++) {
          final x = w * (i + .5) / 4, span = w / 5;
          final path = Path()
            ..moveTo(x - span / 2, h)
            ..lineTo(x - span / 2, h * .25)
            ..quadraticBezierTo(x - span / 2, h * .15, x, h * .09)
            ..quadraticBezierTo(x + span / 2, h * .15, x + span / 2, h * .25)
            ..lineTo(x + span / 2, h);
          canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        }
      case BackgroundPattern.mountains:
        _mountains(canvas, size);
      case BackgroundPattern.petals:
        for (var i = 0; i < (dense ? 24 : 12); i++) {
          final x =
              ((i * .173 + math.sin(phase * math.pi * 2 + i) * .02) % 1) * w;
          final y = ((i * .237 + phase) % 1) * h;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: 7, height: 14),
            paint..color = primary.withValues(alpha: .5),
          );
        }
      case BackgroundPattern.grid:
        for (double x = 0; x < w; x += 48) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
        }
        for (double y = 0; y < h; y += 48) {
          canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        }
      case BackgroundPattern.waves:
        for (var i = 0; i < 7; i++) {
          final path = Path();
          for (var j = 0; j <= 30; j++) {
            final x = w * j / 30,
                y =
                    h * (i + 1) / 8 +
                    math.sin(j / 5 + phase * math.pi * 2 + i) * 18;
            j == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
          }
          canvas.drawPath(
            path,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      case BackgroundPattern.scanlines:
        for (double y = 0; y < h; y += 7) {
          canvas.drawLine(
            Offset(0, y),
            Offset(w, y),
            paint..color = primary.withValues(alpha: .1),
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, phase * h, w, 2),
          paint..color = primary.withValues(alpha: .3),
        );
      case BackgroundPattern.plain:
        break;
    }
  }

  void _city(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    // Layered skyline silhouettes, sparse lit windows and fine circuit traces.
    for (var layer = 0; layer < 2; layer++) {
      for (var i = 0; i < 13; i++) {
        final bw = w / 12;
        final bh = h * (.14 + ((i * 7 + layer * 3) % 9) * .025);
        final x = i * bw - layer * bw * .5;
        final top = h * (layer == 0 ? .9 : 1) - bh;
        final rect = Rect.fromLTWH(x, top, bw * .83, bh + h * .1);
        canvas.drawRect(
          rect,
          Paint()..color = primary.withValues(alpha: layer == 0 ? .025 : .04),
        );
        canvas.drawLine(
          rect.topLeft,
          rect.topRight,
          Paint()
            ..color = (i.isEven ? primary : secondary).withValues(alpha: .23)
            ..strokeWidth = .7,
        );
        for (var row = 0; row < 9; row++) {
          for (var col = 0; col < 3; col++) {
            if ((row + col * 3 + i) % 4 != 0) continue;
            canvas.drawRect(
              Rect.fromLTWH(x + 5 + col * bw * .22, top + 10 + row * 12, 2, 4),
              Paint()..color = secondary.withValues(alpha: .19),
            );
          }
        }
      }
    }
    for (var i = 0; i < 5; i++) {
      final x = w * (.07 + i * .225);
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, h * .14)
        ..lineTo(x + 20, h * .14 + 20)
        ..lineTo(x + 20, h * .28);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = primary.withValues(alpha: .10)
          ..strokeWidth = .7,
      );
      canvas.drawCircle(
        Offset(x + 20, h * .28),
        2,
        Paint()..color = secondary.withValues(alpha: .23),
      );
    }
    final orbit = Rect.fromCircle(
      center: Offset(w * .86, h * .25),
      radius: w * .27,
    );
    canvas.drawArc(
      orbit,
      -2.1,
      2.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = primary.withValues(alpha: .12)
        ..strokeWidth = .6,
    );
    canvas.drawArc(
      orbit,
      phase * math.pi * 2,
      .3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = secondary.withValues(alpha: .3)
        ..strokeWidth = 1.5,
    );
  }

  void _tavern(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    // Fine walnut grain along the margins; a restrained brass astrolabe.
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = primary.withValues(alpha: .045);
    for (var i = 0; i < 35; i++) {
      final x = w * i / 34;
      final path = Path()
        ..moveTo(x, 0)
        ..cubicTo(x + 14, h * .3, x - 18, h * .6, x + 3, h);
      canvas.drawPath(path, p);
    }
    final center = Offset(w * .85, h * .16), r = math.min(w * .4, 200.0);
    for (final scale in [.72, .86, 1.0]) {
      canvas.drawCircle(
        center,
        r * scale,
        p..color = primary.withValues(alpha: .12),
      );
    }
    for (var i = 0; i < 48; i++) {
      final a = i * math.pi / 24, vector = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + vector * r * .86,
        center + vector * r * (i % 4 == 0 ? .96 : .91),
        p,
      );
    }
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8, length = r * (i.isEven ? .68 : .15);
      final point = center + Offset(math.cos(a), math.sin(a)) * length;
      i == 0
          ? star.moveTo(point.dx, point.dy)
          : star.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(star..close(), p..color = primary.withValues(alpha: .13));
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.9, .4),
          radius: 1,
          colors: [
            primary.withValues(alpha: .08),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & s),
    );
  }

  void _mountains(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    // Mineral-green ink washes, not red zigzags. Broad empty center for reading.
    for (var layer = 0; layer < 4; layer++) {
      final y = h * (.60 + layer * .095);
      final path = Path()
        ..moveTo(-w * .1, h)
        ..lineTo(-w * .1, y + w * .15)
        ..cubicTo(
          w * .05,
          y - w * .16,
          w * .14,
          y - w * .22,
          w * .25,
          y - w * .05,
        )
        ..cubicTo(
          w * .35,
          y + w * .06,
          w * .43,
          y - w * .24,
          w * .55,
          y - w * .16,
        )
        ..cubicTo(
          w * .67,
          y - w * .09,
          w * .70,
          y + w * .03,
          w * .83,
          y - w * .08,
        )
        ..cubicTo(w * .94, y - w * .21, w * 1.04, y - w * .05, w * 1.1, y)
        ..lineTo(w * 1.1, h)
        ..close();
      canvas.save();
      canvas.translate(layer.isEven ? 0 : -w * .12, 0);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              secondary.withValues(alpha: .045 + layer * .025),
              secondary.withValues(alpha: .012),
            ],
          ).createShader(Offset.zero & s),
      );
      canvas.restore();
    }
    final sun = Offset(w * .78, h * .21);
    canvas.drawCircle(
      sun,
      math.min(w * .085, 42),
      Paint()..color = primary.withValues(alpha: .055),
    );
    final grain = Paint()
      ..color = secondary.withValues(alpha: .035)
      ..strokeWidth = .6;
    for (var i = 0; i < 360; i++) {
      final p = Offset((i * 137 % 997) / 997 * w, (i * 251 % 991) / 991 * h);
      canvas.drawLine(p, p + Offset(i.isEven ? 2 : 1, .5), grain);
    }
    final twig = Path()
      ..moveTo(w, h * .29)
      ..quadraticBezierTo(w * .89, h * .24, w * .81, h * .29)
      ..moveTo(w * .9, h * .255)
      ..lineTo(w * .86, h * .20);
    canvas.drawPath(
      twig,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = secondary.withValues(alpha: .18),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * (.86 + i * .024), h * (.24 + i * .006)),
          width: 3,
          height: 8,
        ),
        Paint()..color = secondary.withValues(alpha: .17),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SkinBackdropPainter old) =>
      pattern != old.pattern ||
      primary != old.primary ||
      secondary != old.secondary ||
      phase != old.phase ||
      dense != old.dense;
}
