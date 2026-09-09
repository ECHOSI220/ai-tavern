import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/campaign_models.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';

class CampaignRepository {
  const CampaignRepository(this._storage);
  final StorageService _storage;

  Future<List<CampaignDocument>> getAll() async {
    final rows = await _storage.database.query(
      'campaigns',
      columns: ['payload'],
      orderBy: 'updated_at DESC',
    );
    final result = <CampaignDocument>[];
    for (final row in rows) {
      try {
        result.add(
          CampaignDocument.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'campaign.decode.failed',
          error,
          stackTrace: stackTrace,
        );
      }
    }
    return result;
  }

  Future<CampaignDocument?> getById(String id) async {
    final rows = await _storage.database.query(
      'campaigns',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CampaignDocument.fromJson(
      (jsonDecode(rows.single['payload']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<void> upsert(CampaignDocument campaign) =>
      _storage.database.insert('campaigns', {
        'id': campaign.id,
        'title': campaign.title,
        'source': campaign.source.name,
        'updated_at': campaign.updatedAt.millisecondsSinceEpoch,
        'schema_version': campaign.schemaVersion,
        'payload': jsonEncode(campaign.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String id) =>
      _storage.database.delete('campaigns', where: 'id = ?', whereArgs: [id]);
}
