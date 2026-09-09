import '../../app/skins/skin_icon.dart';
import 'package:flutter/material.dart';
import '../../app/skins/background_image_store.dart';
import '../../app/skins/theme_background.dart';
import '../../app/skins/theme_builder.dart';
import '../../app/skins/theme_catalog.dart';
import '../../app/skins/theme_definition.dart';
import '../../app/skins/theme_manager.dart';
import '../../app/skins/theme_preferences.dart';
import '../../app/skins/theme_tokens.dart';
import '../../app/skins/themed_components.dart';
import '../../app/skins/theme_craft.dart';
import '../../app/skins/skin_artwork.dart';
import '../../app/skins/character_theme.dart';
import '../../app/skins/theme_asset_pipeline.dart';
import '../trpg_shared/dice_panel.dart';
import '../trpg_shared/trpg_play_ui.dart';

/// Push only a visual settings route: the underlying session stays mounted.
Future<void> openSkinGallery(BuildContext context, {String contextHint = ''}) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SkinGalleryPage(contextHint: contextHint),
      ),
    );

class SkinGalleryPage extends StatefulWidget {
  const SkinGalleryPage({this.contextHint = '', super.key});
  final String contextHint;
  @override
  State<SkinGalleryPage> createState() => _SkinGalleryPageState();
}

class _SkinGalleryPageState extends State<SkinGalleryPage> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('外观设置未能保存：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(ThemeDefinition definition) => _run(() async {
    final manager = ThemeScope.of(context);
    await preloadSkin(
      context,
      definition,
      manager.preference.themeSettings[definition.id] ?? const ThemeSettings(),
    );
    await manager.applyTheme(definition.id);
  });
  Future<void> _pick(bool chat) => _run(() async {
    final manager = ThemeScope.of(context);
    final path = await BackgroundImageStore().pickAndStore();
    if (path == null || !mounted) return;
    final settings = chat
        ? manager.settings.copyWith(chatBackground: path)
        : manager.settings.copyWith(customBackground: path);
    await preloadSkin(context, manager.getCurrentTheme(), settings, chat: chat);
    await manager.updateSettings(settings);
  });
  @override
  Widget build(BuildContext context) {
    final manager = ThemeScope.of(context);
    final theme = Theme.of(context), current = manager.getCurrentTheme();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('外观与皮肤'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '皮肤库'),
              Tab(text: '背景与效果'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '为故事，挑一个栖身之所',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前：${current.name} · 只改变外观，不会重新载入聊天或跑团',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (manager.warning case final warning?)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(warning),
                          ),
                        const SizedBox(height: 28),
                        Text('角色主题 · 誓约之剑', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _galleryGrid(ThemeCatalog.characters, manager),
                        const SizedBox(height: 28),
                        Text(
                          '本期精修 · 三种叙事氛围',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '从纸页、边框到每一条消息，各有自己的细节。',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        _galleryGrid(ThemeCatalog.featured, manager),
                        const SizedBox(height: 24),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('其他基础皮肤'),
                          subtitle: const Text('保留原有选择与设置 · 9 套'),
                          children: [
                            _galleryGrid(
                              ThemeCatalog.themes
                                  .where(
                                    (d) =>
                                        d.category != 'character_theme' &&
                                        !ThemeCatalog.featuredIds.contains(
                                          d.id,
                                        ),
                                  )
                                  .toList(),
                              manager,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _settingsPage(manager),
          ],
        ),
      ),
    );
  }

  Widget _galleryGrid(
    List<ThemeDefinition> definitions,
    ThemeManager manager,
  ) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = bounds.maxWidth >= 1000
          ? 3
          : bounds.maxWidth >= 700
          ? 2
          : 1;
      final width = (bounds.maxWidth - 20 * (columns - 1)) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 24,
        children: definitions
            .map(
              (d) => SizedBox(
                width: width,
                child: Theme(
                  data: SkinThemeBuilder.build(
                    d,
                    MediaQuery.platformBrightnessOf(context),
                  ),
                  child: _SkinCard(
                    definition: d,
                    current: manager.getCurrentTheme().id == d.id,
                    recommended: ThemeCatalog.recommend(
                      widget.contextHint,
                    ).contains(d.id),
                    busy: _busy,
                    onPreview: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemePreview(
                          definition: manager.previewTheme(d.id),
                        ),
                      ),
                    ),
                    onApply: () => _apply(d),
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _settingsPage(ThemeManager manager) {
    final s = manager.settings, d = manager.getCurrentTheme();
    void draft(ThemeSettings next) {
      manager.updateSettings(next, persist: false);
    }

    void save(double _) {
      _run(manager.saveThemePreference);
    }

    Widget slider(
      String title,
      double value,
      double min,
      double max,
      ValueChanged<double> onChanged, {
      String? hint,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: hint == null ? null : Text(hint),
          trailing: Text(value.toStringAsFixed(2)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: _busy ? null : onChanged,
          onChangeEnd: save,
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ThemedPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('以下设置按皮肤分别保存。图片只用于本机显示，不发送给 AI。'),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ThemeBackground(
                            definition: d,
                            settings: s,
                            child: const Center(
                              child: ThemedPanel(child: Text('背景预览 · 正文始终清晰')),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _pick(false),
                            icon: const SkinIcon(Icons.wallpaper_outlined),
                            label: const Text('自定义背景'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => manager.updateSettings(
                                      s.copyWith(
                                        resetBackground: true,
                                        brightness: 1,
                                      ),
                                    ),
                                  ),
                            child: const Text('恢复该皮肤默认背景'),
                          ),
                        ],
                      ),
                      slider(
                        '背景亮度',
                        s.brightness,
                        .4,
                        1.4,
                        (v) => draft(s.copyWith(brightness: v)),
                      ),
                      slider(
                        '背景透明度',
                        s.opacity ?? d.backgroundOpacity,
                        0,
                        1,
                        (v) => draft(s.copyWith(opacity: v)),
                      ),
                      slider(
                        '背景模糊',
                        s.blur ?? d.backgroundBlur,
                        0,
                        20,
                        (v) => draft(s.copyWith(blur: v)),
                        hint: '低 / 关闭效果时停用模糊，保护手机性能',
                      ),
                      slider(
                        '背景遮罩',
                        s.overlay ?? d.overlayOpacity,
                        0,
                        1,
                        (v) => draft(s.copyWith(overlay: v)),
                      ),
                      slider(
                        '界面不透明度',
                        s.uiOpacity,
                        .35,
                        1,
                        (v) => draft(s.copyWith(uiOpacity: v)),
                        hint: '调整卡片、消息气泡和输入面板的透明程度；背景亮度不受影响',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ThemedPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '聊天专属背景',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('用于酒馆及单人 / 多人跑团聊天区域，其他页面仍使用全局背景。'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _pick(true),
                            icon: const SkinIcon(Icons.chat_bubble_outline),
                            label: Text(
                              s.chatBackground == null ? '选择聊天背景' : '更换聊天背景',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy || s.chatBackground == null
                                ? null
                                : () => _run(
                                    () => manager.updateSettings(
                                      s.copyWith(resetChat: true),
                                    ),
                                  ),
                            child: const Text('跟随全局背景'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ThemedPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '动画与性能',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ThemeEffectsLevel>(
                        initialValue: s.effectsLevel,
                        key: ValueKey(s.effectsLevel),
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '动态效果等级'),
                        items: ThemeEffectsLevel.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(effectLabel(v)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) {
                                if (v != null) {
                                  _run(
                                    () => manager.updateSettings(
                                      s.copyWith(effectsLevel: v),
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('减少动画'),
                        subtitle: const Text('停止漂浮花瓣、水光和扫描线；同时遵循系统减少动画设置'),
                        value: s.reduceMotion,
                        onChanged: _busy
                            ? null
                            : (v) => _run(
                                () => manager.updateSettings(
                                  s.copyWith(reduceMotion: v),
                                ),
                              ),
                      ),
                      const Text('默认“低”：静态装饰、无粒子移动、无复杂模糊或发光。纯黑皮肤始终没有动态背景。'),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(manager.resetTheme),
                        child: const Text('重置本皮肤全部外观设置'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String effectLabel(ThemeEffectsLevel level) => switch (level) {
  ThemeEffectsLevel.off => '关闭 · 无装饰',
  ThemeEffectsLevel.low => '低 · 静态轻量（推荐）',
  ThemeEffectsLevel.normal => '标准 · 轻量动态',
  ThemeEffectsLevel.high => '高 · 更丰富装饰',
};

Future<void> preloadSkin(
  BuildContext context,
  ThemeDefinition d,
  ThemeSettings s, {
  bool chat = false,
}) async {
  if (d.assetManifest case final path?) {
    await ThemeAssetPipeline.load(path);
    if (!context.mounted) return;
  }
  final images = <ImageProvider>{
    ?skinBackgroundImage(context, d, s, chat: chat),
    if (!chat) ?skinBackgroundImage(context, d, s, chat: true),
    if (!d.immersiveArtwork && d.characterImage != null)
      ResizeImage(
        AssetImage(
          ThemeAssetPipeline.imagePath(
            d.assetManifest,
            'character',
            d.characterImage,
          )!,
        ),
        width: 768,
      ),
  };
  for (final image in images) {
    // Missing/corrupt custom resources fall back to the theme's code background.
    await precacheImage(
      image,
      context,
      onError: (Object error, StackTrace? stack) {},
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.definition,
    required this.current,
    required this.recommended,
    required this.busy,
    required this.onPreview,
    required this.onApply,
  });
  final ThemeDefinition definition;
  final bool current, recommended, busy;
  final VoidCallback onPreview, onApply;
  @override
  Widget build(BuildContext context) {
    final d = definition;
    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onPreview,
            child: Theme(
              data: SkinThemeBuilder.build(
                d,
                MediaQuery.platformBrightnessOf(context),
              ),
              child: _SkinThumbnail(definition: d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关于这个皮肤',
                      icon: const SkinIcon(Icons.info_outline, size: 20),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ThemedDialog(
                          title: Text(d.name),
                          content: Text(
                            '${d.description}\n${modeLabel(d.mode)}\n${d.animatedBackground ? '支持动态背景' : '静态背景'}\n默认性能等级：低\n精修皮肤内置 AI 环境画，基础皮肤采用代码绘制，全部离线可用。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Text(d.description),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      modeLabel(d.mode),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      d.animatedBackground ? '可选轻动态' : '静态',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (recommended)
                      Text(
                        '适合当前故事',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: ThemeTokens.of(context).accentPrimary,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPreview,
                        child: const Text('预览'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ThemedButton(
                        onPressed: busy || current ? null : onApply,
                        child: current
                            ? const Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 5,
                                children: [
                                  SkinIcon(Icons.check, size: 16),
                                  Text('当前皮肤'),
                                ],
                              )
                            : const Text('使用'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String modeLabel(SkinMode mode) => switch (mode) {
  SkinMode.system => '跟随系统',
  SkinMode.light => '亮色',
  SkinMode.dark => '暗色',
};

class _SkinThumbnail extends StatelessWidget {
  const _SkinThumbnail({required this.definition});
  final ThemeDefinition definition;
  @override
  Widget build(BuildContext context) {
    final header = SkinIllustratedHeader(
      definition: definition,
      compact: true,
      eyebrow: '幻境酒馆',
    );
    if (!definition.immersiveArtwork) return header;
    return ThemeBackground(
      definition: definition,
      settings: const ThemeSettings(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: header,
      ),
    );
  }
}

class ThemePreview extends StatefulWidget {
  const ThemePreview({required this.definition, super.key});
  final ThemeDefinition definition;
  @override
  State<ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends State<ThemePreview> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final manager = ThemeScope.of(context), d = widget.definition;
    final s = manager.preference.themeSettings[d.id] ?? const ThemeSettings();
    return Theme(
      data: SkinThemeBuilder.build(
        d,
        MediaQuery.platformBrightnessOf(context),
        settings: s,
        transparentScaffold: true,
      ),
      child: Builder(
        builder: (context) => ThemeBackground(
          definition: d,
          settings: s,
          child: Scaffold(
            appBar: AppBar(title: Text('预览 · ${d.name}')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SkinPreviewContent(definition: d),
                ),
              ),
            ),
            bottomNavigationBar: ThemedNavigation(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('返回'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ThemedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await preloadSkin(context, d, s);
                                    await manager.applyTheme(d.id);
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('保存失败：$error')),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: const Text('应用皮肤'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SkinPreviewContent extends StatelessWidget {
  const SkinPreviewContent({this.definition, super.key});
  final ThemeDefinition? definition;
  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (definition?.material != null &&
            definition!.material != SkinMaterial.standard)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: SkinIllustratedHeader(
              definition: definition,
              compact: true,
              eyebrow: '外观试阅',
            ),
          ),
        Text(
          '预览不会修改正在使用的皮肤或游戏数据。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 24),
        ThemedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('幻境酒馆', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: SkinIcon(Icons.chat_outlined),
                    label: Text('新建对话'),
                  ),
                  Chip(
                    avatar: SkinIcon(Icons.badge_outlined),
                    label: Text('角色卡'),
                  ),
                  Chip(
                    avatar: SkinIcon(Icons.menu_book_outlined),
                    label: Text('世界书'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ThemedPanel(
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: t.userBubble,
                foregroundColor: t.accentPrimary,
                child: const SkinIcon(Icons.person_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '角色头像',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('HP 18/20 · 状态正常'),
                  ],
                ),
              ),
              const SkinIcon(Icons.chevron_right),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TrpgMessageBubble(
          label: 'GM 主持',
          content: '雨雾笼罩着旧港。你握紧地图，听见远处传来钟声。',
          tone: TrpgMessageTone.gm,
        ),
        const TrpgMessageBubble(
          label: '玩家',
          content: '我沿着街道走向港口。',
          tone: TrpgMessageTone.player,
        ),
        if (CharacterThemeExtension.of(context) != null)
          const TrpgMessageBubble(
            label: '角色',
            content: '月光照亮回廊。你的同伴停下脚步，等待你的回答。',
            tone: TrpgMessageTone.npc,
          ),
        const TrpgMessageBubble(
          label: '私密信息 · 仅你可见',
          content: '你发现信封背面有一行小字。',
          tone: TrpgMessageTone.private,
        ),
        const ThemedInput(label: '输入行动、对白或想法…', readOnly: true),
        const SizedBox(height: 16),
        ThemedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DiceGlyph(sides: 20, color: t.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '检定成功 · D20',
                      style: TextStyle(
                        color: t.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('16 + 2 = 18 · 难度 12'),
              if (CharacterThemeExtension.of(context) != null) ...[
                const SizedBox(height: 14),
                Center(
                  child: ThemedDiceCard(
                    critical: true,
                    child: Text(
                      '18',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ThemedLoadingIndicator(),
                    SizedBox(width: 12),
                    Text('正在加载'),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  Text('成功', style: TextStyle(color: t.success)),
                  Text('警告', style: TextStyle(color: t.warning)),
                  Text('危险', style: TextStyle(color: t.danger)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TrpgSceneSummary(
          title: '旧港仓库',
          subtitle: '深夜 · 浓雾',
          facts: [
            TrpgFact(Icons.assignment_outlined, '调查失踪者'),
            TrpgFact(Icons.favorite_outline, 'HP 18/20'),
          ],
        ),
        const SizedBox(height: 16),
        const ThemedPanel(
          child: Column(
            children: [
              ListTile(
                leading: SkinIcon(Icons.settings_outlined),
                title: Text('设置面板'),
                subtitle: Text('原有设置内容保持不变'),
              ),
              ListTile(
                leading: SkinIcon(Icons.groups_outlined),
                title: Text('多人房间'),
                subtitle: Text('玩家 · Ready · AI Host'),
                trailing: SkinIcon(Icons.check_circle_outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
