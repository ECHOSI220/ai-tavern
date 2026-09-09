import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/save_slot.dart';
import '../models/story_card.dart';

class OfficialStoryCardService {
  const OfficialStoryCardService();

  static const whiteEchoAsset =
      'examples/white_echo_story_framework.ai-tavern.json';
  static const saintReincarnationAsset =
      'examples/saint_reincarnation_accident_story_framework.ai-tavern.json';
  static const retiredHeroEarlyEightAsset =
      'examples/retired_hero_early_eight_story_framework.ai-tavern.json';
  static const saintReincarnationCoverAsset =
      'assets/official/saint_reincarnation_accident_cover.png';
  static const retiredHeroEarlyEightCoverAsset =
      'assets/official/retired_hero_early_eight_cover.png';

  Future<StoryCard> loadWhiteEcho() async {
    final source = await rootBundle.loadString(whiteEchoAsset);
    return decodeWhiteEcho(source);
  }

  Future<StoryCard> loadSaintReincarnation() async {
    final source = await rootBundle.loadString(saintReincarnationAsset);
    final coverImage = await _persistOfficialImage(
      assetPath: saintReincarnationCoverAsset,
      fileName: 'saint_reincarnation_accident_cover.png',
    );
    return decodeSaintReincarnation(source, coverImage: coverImage);
  }

  Future<StoryCard> loadRetiredHeroEarlyEight() async {
    final source = await rootBundle.loadString(retiredHeroEarlyEightAsset);
    final coverImage = await _persistOfficialImage(
      assetPath: retiredHeroEarlyEightCoverAsset,
      fileName: 'retired_hero_early_eight_cover.png',
    );
    return decodeRetiredHeroEarlyEight(source, coverImage: coverImage);
  }

  StoryCard decodeWhiteEcho(String source) {
    final decoded = jsonDecode(source) as Map;
    final save = SaveSlot.fromJson(
      (decoded['save']! as Map).cast<String, Object?>(),
    );
    final createdAt = DateTime.parse('2026-08-11T22:30:00.000+08:00');
    return StoryCard(
      id: officialWhiteEchoCardId,
      name: save.name,
      description: '极寒地表上的证据、记忆与同行之旅。包含完整章节门禁、角色和世界书。',
      author: '幻境酒馆官方',
      isOfficial: true,
      template: save,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  StoryCard decodeSaintReincarnation(String source, {String? coverImage}) {
    final decoded = jsonDecode(source) as Map;
    var save = SaveSlot.fromJson(
      (decoded['save']! as Map).cast<String, Object?>(),
    );
    if (coverImage != null) save = save.copyWith(coverImage: coverImage);
    final createdAt = DateTime.parse('2026-08-12T12:00:00.000+08:00');
    return StoryCard(
      id: officialSaintReincarnationCardId,
      name: save.name,
      description: '男高中生因转生坐标事故成为银发圣女，在家人、同伴与秘密之间重新定义“圣女”的长篇奇幻故事。',
      author: '幻境酒馆官方',
      isOfficial: true,
      template: save,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  StoryCard decodeRetiredHeroEarlyEight(String source, {String? coverImage}) {
    final decoded = jsonDecode(source) as Map;
    var save = SaveSlot.fromJson(
      (decoded['save']! as Map).cast<String, Object?>(),
    );
    if (coverImage != null) save = save.copyWith(coverImage: coverImage);
    final createdAt = DateTime.parse('2026-08-12T15:00:00.000+08:00');
    return StoryCard(
      id: officialRetiredHeroEarlyEightCardId,
      name: save.name,
      description: '退役泰坦驾驶员进入大学，在早八、邻居、救援机器人与战友数据中学习普通生活。',
      author: '幻境酒馆官方',
      isOfficial: true,
      template: save,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  Future<String> _persistOfficialImage({
    required String assetPath,
    required String fileName,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}images'
      '${Platform.pathSeparator}official',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }
}
