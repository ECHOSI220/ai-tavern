import 'package:flutter/material.dart';
import '../../models/character.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/character_social_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/character_social/character_social_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/trpg/account_client_service.dart';

Future<void> addSocialContact(
  BuildContext context,
  Character character,
  CharacterCardRepository cards,
  SettingsRepository settings,
) async {
  final api = ApiRepository(cards.storage, SecureStorageService());
  final account = AccountClientService(apiRepository: api);
  try {
    await account.restore();
    final repo = CharacterSocialRepository(
      cards.storage,
      owner: account.tokens?.account.userId ?? 'local',
    );
    final service = CharacterSocialService(
      repository: repo,
      cards: cards,
      api: api,
      settings: settings,
    );
    await service.initialize();
    final worlds = await repo.list('world', limit: 100);
    if (!context.mounted) return;
    final world = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('添加为联系人 · 选择世界'),
        children: [
          for (final w in worlds)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, w.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(w.text('name')),
              ),
            ),
        ],
      ),
    );
    if (world == null) return;
    await service.addCharacter(character, worldId: world);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已添加到角色社交；原角色卡仍是人格来源。')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加联系人失败：$e')));
    }
  } finally {
    account.dispose();
  }
}
