import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import '../../models/trpg_presentation_models.dart';

class TRPGAudioDirector {
  TRPGAudioDirector({this.assets = const []});

  final List<AudioAsset> assets;
  final AudioPlayer _bgm = AudioPlayer();
  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _sfx = AudioPlayer();
  double masterVolume = 1;
  double bgmVolume = .65;
  double ambientVolume = .55;
  double sfxVolume = .85;
  double voiceVolume = 1;
  String? currentBgmId, currentAmbientId;

  AudioAsset? resolve(String id, AudioAssetType type) {
    final exact = assets
        .where((value) => value.id == id && value.type == type)
        .firstOrNull;
    if (exact != null) return exact;
    return assets
        .where((value) => value.type == type && value.tags.contains(id))
        .firstOrNull;
  }

  Future<void> handle(PresentationEvent event) async {
    switch (event.type) {
      case PresentationEventType.bgmPlay:
        await playBgm(event.payload['assetId'] as String? ?? '');
      case PresentationEventType.bgmStop:
        await stopBgm();
      case PresentationEventType.ambientPlay:
        await playAmbient(event.payload['assetId'] as String? ?? '');
      case PresentationEventType.ambientStop:
        await stopAmbient();
      case PresentationEventType.sfxPlay:
        await playSfx(event.payload['assetId'] as String? ?? '');
      case PresentationEventType.combatStart:
        await playBgm(event.payload['bgmId'] as String? ?? 'battle');
      case PresentationEventType.diceAnimation:
        await playSfx('dice');
      case PresentationEventType.itemGainAnimation:
        await playSfx('item');
      case PresentationEventType.questUpdateAnimation:
        await playSfx('quest');
      case PresentationEventType.damageAnimation:
        await playSfx('hit');
      case PresentationEventType.healAnimation:
        await playSfx('heal');
      default:
        break;
    }
  }

  Future<void> playBgm(String moodOrId) async {
    final asset = resolve(moodOrId, AudioAssetType.bgm);
    if (asset == null || asset.path.isEmpty || currentBgmId == asset.id) return;
    for (var step = 5; step >= 0; step--) {
      await _bgm.setVolume(masterVolume * bgmVolume * step / 5);
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
    await _bgm.stop();
    await _bgm.setReleaseMode(asset.loop ? ReleaseMode.loop : ReleaseMode.stop);
    await _bgm.play(_source(asset.path), volume: 0);
    currentBgmId = asset.id;
    for (var step = 1; step <= 5; step++) {
      await _bgm.setVolume(masterVolume * bgmVolume * asset.volume * step / 5);
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
  }

  Future<void> stopBgm() async {
    await _bgm.stop();
    currentBgmId = null;
  }

  Future<void> playAmbient(String id) async {
    final asset = resolve(id, AudioAssetType.ambient);
    if (asset == null || asset.path.isEmpty || currentAmbientId == asset.id) {
      return;
    }
    await _ambient.stop();
    await _ambient.setReleaseMode(ReleaseMode.loop);
    await _ambient.play(
      _source(asset.path),
      volume: masterVolume * ambientVolume * asset.volume,
    );
    currentAmbientId = asset.id;
  }

  Future<void> stopAmbient() async {
    await _ambient.stop();
    currentAmbientId = null;
  }

  Future<void> playSfx(String id) async {
    final asset = resolve(id, AudioAssetType.sfx);
    if (asset == null || asset.path.isEmpty) return;
    await _sfx.stop();
    await _sfx.play(
      _source(asset.path),
      volume: masterVolume * sfxVolume * asset.volume,
    );
  }

  Source _source(String path) => path.startsWith('assets/')
      ? AssetSource(path.substring('assets/'.length))
      : File(path).existsSync()
      ? DeviceFileSource(path)
      : UrlSource(path);

  Future<void> dispose() async {
    await Future.wait([_bgm.dispose(), _ambient.dispose(), _sfx.dispose()]);
  }
}

class CampaignAssetManager {
  CampaignAssetManager({this.maxImageEntries = 3, this.maxSfxEntries = 12});
  final int maxImageEntries, maxSfxEntries;
  final _images = <String, DateTime>{};
  final _sfx = <String, DateTime>{};

  void touchBackground(String id) => _touch(_images, id, maxImageEntries);
  void touchPortrait(String id) => _touch(_images, id, maxImageEntries);
  void preloadSfx(String id) => _touch(_sfx, id, maxSfxEntries);

  void _touch(Map<String, DateTime> cache, String id, int maximum) {
    cache[id] = DateTime.now();
    while (cache.length > maximum) {
      final oldest = cache.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      cache.remove(oldest.key);
    }
  }

  void handleMemoryWarning({String? currentBackground}) {
    _images.removeWhere((key, _) => key != currentBackground);
    _sfx.clear();
  }

  Set<String> get cachedAssets => {..._images.keys, ..._sfx.keys};
}
