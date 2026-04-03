import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/supabase/supabase_service.dart';

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Map<String, String>>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final local = await _fetchLocal();
    // Pull dari cloud di background, update state jika ada data baru
    _syncFromCloud().ignore();
    return local;
  }

  Future<Map<String, String>> _fetchLocal() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> _syncFromCloud() async {
    final cloud = await SupabaseService.instance.fetchSettings();
    if (cloud.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    for (final entry in cloud.entries) {
      await db.insert(
        'settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    state = AsyncData(await _fetchLocal());
  }

  Future<void> setSetting(String key, String value) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'settings',
      {'value': value},
      where: 'key = ?',
      whereArgs: [key],
    );
    state = AsyncData(await _fetchLocal());
    // Sync ke Supabase (fire and forget)
    SupabaseService.instance.upsertSetting(key, value).ignore();
  }

  String get(String key) {
    return state.valueOrNull?[key] ?? '';
  }
}
