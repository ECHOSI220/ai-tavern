import 'dart:convert';
import 'package:flutter/services.dart';

/// Local, data-only manifest. No downloads, executable scripts or session access.
class ThemeAssetManifest {
  const ThemeAssetManifest(this.themeId, this.assets);
  final String themeId;
  final Map<String, Map<String, dynamic>> assets;
  String? image(String slot) => assets[slot]?['path'] as String?;
}

abstract final class ThemeAssetValidator {
  static List<String> validate(Map<String, dynamic> json) {
    final errors = <String>[];
    final id = json['themeId'];
    if (id is! String || !RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      return ['Invalid theme ID'];
    }
    if (json['schemaVersion'] != 1 || json['assets'] is! Map) {
      return ['Invalid manifest schema'];
    }
    for (final entry in (json['assets'] as Map).entries) {
      final item = entry.value;
      if (item is! Map) {
        errors.add('Invalid slot ${entry.key}');
        continue;
      }
      final path = item['path'];
      if (path != null &&
          (path is! String ||
              path.contains('..') ||
              !path.startsWith('assets/themes/$id/') ||
              !RegExp(r'\.(png|webp|jpg)$').hasMatch(path))) {
        errors.add('Unsafe asset ${entry.key}');
      }
      if (item['renderer'] != 'raster' && item['renderer'] != 'native') {
        errors.add('Unsupported renderer ${entry.key}');
      }
      if (item['renderer'] == 'raster' && path == null) {
        errors.add('Missing image path ${entry.key}');
      }
    }
    for (final slot in [
      'bg_main',
      'bg_chat',
      'preview',
      'panel_texture',
      'border_gold',
      'button_primary',
      'button_secondary',
      'input_frame',
      'card_character',
      'card_system',
      'dice_bg',
      'dice_glow',
      'loading_magic_circle',
      'transition_glow',
      'icon_set',
    ]) {
      if (!(json['assets'] as Map).containsKey(slot)) {
        errors.add('Missing slot $slot');
      }
    }
    return errors;
  }
}

abstract final class ThemeAssetPipeline {
  static final _loaded = <String, ThemeAssetManifest>{};
  static String? imagePath(
    String? manifestPath,
    String slot,
    String? fallback,
  ) => _loaded[manifestPath]?.image(slot) ?? fallback;
  static final _cache = <String, Future<ThemeAssetManifest?>>{};
  static Future<ThemeAssetManifest?> load(String path, {AssetBundle? bundle}) {
    if (bundle != null) return _read(path, bundle);
    return _cache.putIfAbsent(path, () => _read(path, rootBundle));
  }

  static Future<ThemeAssetManifest?> _read(
    String path,
    AssetBundle bundle,
  ) async {
    try {
      final decoded =
          jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>;
      if (ThemeAssetValidator.validate(decoded).isNotEmpty) return null;
      final manifest = ThemeAssetManifest(
        decoded['themeId'] as String,
        (decoded['assets'] as Map).map(
          (key, value) =>
              MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
        ),
      );
      _loaded[path] = manifest;
      return manifest;
    } catch (_) {
      // A missing pack never replaces the opaque background or blocks applying.
      return null;
    }
  }

  static Future<List<String>> missingAssets(
    ThemeAssetManifest manifest, {
    AssetBundle? bundle,
  }) async {
    final missing = <String>[];
    for (final path
        in manifest.assets.keys.map(manifest.image).nonNulls.toSet()) {
      try {
        await (bundle ?? rootBundle).load(path);
      } catch (_) {
        missing.add(path);
      }
    }
    return missing;
  }
}
