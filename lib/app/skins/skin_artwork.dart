import 'package:flutter/material.dart';
import 'theme_definition.dart';
import 'theme_tokens.dart';
import 'theme_craft.dart';
import 'theme_background.dart';
import 'theme_preferences.dart';
import 'theme_asset_pipeline.dart';

/// Kept in ThemeData so nested previews never borrow the active skin's art.
@immutable
class SkinArtworkTheme extends ThemeExtension<SkinArtworkTheme> {
  const SkinArtworkTheme(this.definition);
  final ThemeDefinition definition;
  static ThemeDefinition? of(BuildContext context) =>
      Theme.of(context).extension<SkinArtworkTheme>()?.definition;
  @override
  SkinArtworkTheme copyWith({ThemeDefinition? definition}) =>
      SkinArtworkTheme(definition ?? this.definition);
  @override
  SkinArtworkTheme lerp(covariant SkinArtworkTheme? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// An illustrated opening plate, not a screenshot or a fixed-height text card.
/// Text flows naturally at large accessibility sizes; only the art is cropped.
class SkinIllustratedHeader extends StatelessWidget {
  const SkinIllustratedHeader({
    this.definition,
    this.title,
    this.subtitle,
    this.eyebrow = '幻境酒馆 · 叙事空间',
    this.compact = false,
    super.key,
  });
  final ThemeDefinition? definition;
  final String? title, subtitle;
  final String eyebrow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = definition ?? SkinArtworkTheme.of(context);
    final theme = Theme.of(context);
    final t = ThemeTokens.of(context);
    final paper = d?.material == SkinMaterial.paper;
    final base = t.backgroundPrimary;
    final path = ThemeAssetPipeline.imagePath(
      d?.assetManifest,
      'bg_main',
      d?.backgroundImage,
    );
    if (d != null && d.immersiveArtwork) {
      return _ImmersiveSkinHeading(
        title: title ?? d.metadata['coverTitle'] ?? d.name,
        subtitle: subtitle ?? d.metadata['detail'] ?? '',
        eyebrow: eyebrow,
        compact: compact,
      );
    }
    return ClipPath(
      clipper: ShapeBorderClipper(
        shape: SkinCraft.of(context).frame(ornament: false),
      ),
      child: ColoredBox(
        color: base,
        child: Stack(
          children: [
            if (path == null && d != null)
              Positioned.fill(
                child: ThemeBackground(
                  definition: d,
                  settings: const ThemeSettings(),
                  child: const SizedBox.expand(),
                ),
              ),
            if (path != null)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Image.asset(
                    path,
                    fit: BoxFit.cover,
                    alignment: d!.artworkAlignment,
                    cacheWidth: 1536,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => ColoredBox(color: base),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .35, .72, 1],
                    colors: [
                      base.withValues(alpha: paper ? .04 : .02),
                      base.withValues(alpha: paper ? .12 : .1),
                      base.withValues(alpha: .9),
                      base,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, compact ? 120 : 152, 24, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 24, height: 1, color: t.accentPrimary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          eyebrow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.accentPrimary,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title ??
                        d?.metadata['coverTitle'] ??
                        d?.metadata['subtitle'] ??
                        '我的幻境酒馆',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: paper ? 3 : 1,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle ?? d?.metadata['detail'] ?? '选择今天要进入的世界',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: t.textSecondary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Only text and native rules: the character lives in the page wallpaper.
/// No portrait card, independent cutout, medallion or duplicate background.
class _ImmersiveSkinHeading extends StatelessWidget {
  const _ImmersiveSkinHeading({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.compact,
  });
  final String title, subtitle, eyebrow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 700;
        return ConstrainedBox(
          key: const ValueKey('immersive-skin-heading'),
          constraints: BoxConstraints(
            minHeight: compact
                ? 260
                : wide
                ? 280
                : 300,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: bounds.maxWidth * (wide ? .48 : .52),
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 22 : 30, bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: text.labelSmall?.copyWith(
                        color: t.accentPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: text.headlineMedium?.copyWith(
                        color: t.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(width: 44, height: 1, color: t.accentPrimary),
                    const SizedBox(height: 16),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: t.textSecondary,
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SkinWelcomeHeader extends StatelessWidget {
  const SkinWelcomeHeader({super.key});
  @override
  Widget build(BuildContext context) => const SkinIllustratedHeader(
    title: '我的幻境酒馆',
    eyebrow: 'AI TAVERN',
    subtitle: '门外是世界，灯下是你的故事。\n选择今天要进入的世界',
  );
}
