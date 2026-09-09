import 'package:flutter/material.dart';
import 'theme_catalog.dart';
import 'theme_definition.dart';
import 'theme_preferences.dart';
import 'theme_validator.dart';
import 'theme_asset_pipeline.dart';

abstract interface class ThemePreferenceStore {
  Future<ThemePreference> loadThemePreference();
  Future<void> saveThemePreference(ThemePreference preference);
}

class ThemeManager extends ChangeNotifier {
  ThemeManager(this.store);
  final ThemePreferenceStore store;
  ThemePreference _preference = const ThemePreference();
  bool _disposed = false;
  int _revision = 0;
  Future<void> _pendingWrite = Future.value();
  String? warning;
  ThemePreference get preference => _preference;
  ThemeSettings get settings => _preference.settings;
  ThemeDefinition getCurrentTheme() => ThemeCatalog.byId(_preference.themeId);

  /// Preview is deliberately local data, not a change to the live app.
  ThemeDefinition previewTheme(String id) => ThemeCatalog.byId(id);
  ThemeDefinition themeForSession(String? id) => ThemeCatalog.byId(
    _preference.sessionOverrideIds[id] ?? _preference.themeId,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadThemePreference() async {
    final revision = _revision;
    try {
      final p = await store.loadThemePreference();
      if (_disposed || revision != _revision) return;
      final definition = ThemeCatalog.byId(p.themeId);
      if (definition.assetManifest case final path?) {
        await ThemeAssetPipeline.load(path);
        if (_disposed || revision != _revision) return;
      }
      final valid = ThemeValidator.validate(definition).isEmpty;
      _preference = ThemePreference(
        themeId: valid ? definition.id : 'default_clean',
        themeSettings: p.themeSettings,
        sessionOverrideIds: p.sessionOverrideIds,
      );
      if (!valid || definition.id != p.themeId) warning = '皮肤资源不可用，已恢复默认简洁。';
    } catch (_) {
      if (_disposed || revision != _revision) return;
      _preference = const ThemePreference();
      warning = '皮肤设置无法读取，已使用默认简洁；其他数据不受影响。';
    }
    _notify();
  }

  Future<void> applyTheme(String id) async {
    final definition = ThemeCatalog.byId(id);
    final errors = ThemeValidator.validate(definition);
    if (errors.isNotEmpty) throw FormatException(errors.join('；'));
    _revision++;
    warning = null;
    _preference = ThemePreference(
      themeId: definition.id,
      themeSettings: _preference.themeSettings,
      sessionOverrideIds: _preference.sessionOverrideIds,
    );
    _notify();
    await saveThemePreference();
  }

  Future<void> updateSettings(
    ThemeSettings settings, {
    bool persist = true,
  }) async {
    _revision++;
    // Round-trip normalizes malformed/out-of-range preference data.
    _preference = ThemePreference(
      themeId: _preference.themeId,
      themeSettings: {
        ..._preference.themeSettings,
        _preference.themeId: ThemeSettings.fromJson(settings.toJson()),
      },
      sessionOverrideIds: _preference.sessionOverrideIds,
    );
    _notify();
    if (persist) await saveThemePreference();
  }

  Future<void> resetTheme() => updateSettings(const ThemeSettings());
  Future<void> saveThemePreference() {
    final snapshot = _preference;
    final task = _pendingWrite.then((_) => store.saveThemePreference(snapshot));
    // A failed disk write must not poison all subsequent saves.
    _pendingWrite = task.catchError((Object _) {});
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemeScope extends InheritedNotifier<ThemeManager> {
  const ThemeScope({
    required ThemeManager manager,
    required super.child,
    super.key,
  }) : super(notifier: manager);
  static ThemeManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
  static ThemeManager of(BuildContext context) => maybeOf(context)!;
}
