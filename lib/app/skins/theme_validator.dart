import 'package:flutter/material.dart';
import 'theme_definition.dart';

abstract final class ThemeValidator {
  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
  }

  static List<String> validate(
    ThemeDefinition definition, {
    bool Function(String)? assetExists,
  }) {
    final errors = <String>[];
    if (definition.id.isEmpty || definition.name.isEmpty) {
      errors.add('缺少主题标识或名称');
    }
    for (final v in [definition.backgroundOpacity, definition.overlayOpacity]) {
      if (!v.isFinite || v < 0 || v > 1) errors.add('背景透明度超出范围');
    }
    if (!definition.backgroundBlur.isFinite ||
        definition.backgroundBlur < 0 ||
        definition.backgroundBlur > 20) {
      errors.add('背景模糊超出范围');
    }
    if (!definition.radius.isFinite ||
        definition.radius < 0 ||
        definition.radius > 32) {
      errors.add('圆角超出范围');
    }
    for (final image in [
      definition.backgroundImage,
      definition.chatBackgroundImage,
    ].nonNulls) {
      if (!image.startsWith('assets/') ||
          image.contains('..') ||
          (assetExists != null && !assetExists(image))) {
        errors.add('背景资源不存在或路径不安全');
      }
    }
    for (final mode in Brightness.values) {
      final t = definition.tokens(mode);
      final surfaces = [
        t.backgroundPrimary,
        t.surfacePrimary,
        t.surfaceSecondary,
        t.surfaceElevated,
        t.userBubble,
        t.systemBubble,
        t.privateBubble,
        t.gmBubble,
      ];
      if (contrast(t.aiForeground, t.aiBubble) < 4.5) {
        errors.add('角色气泡文字对比度不足');
      }
      for (final background in surfaces) {
        if (contrast(t.textPrimary, background) < 4.5 ||
            contrast(t.textSecondary, background) < 4.5) {
          errors.add('正文/辅助文字对比度不足');
          break;
        }
      }
      for (final color in [
        t.success,
        t.warning,
        t.danger,
        t.info,
        t.accentPrimary,
        t.accentSecondary,
      ]) {
        if (contrast(color, t.surfacePrimary) < 3) errors.add('语义颜色对比度不足');
      }
    }
    return errors.toSet().toList();
  }
}
