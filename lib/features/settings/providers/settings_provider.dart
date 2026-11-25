import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/device/device_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_store.dart';

/// Pengaturan toko (nama, alamat, footer struk, logo) — sama di semua HP.
/// Pengaturan per HP (printer, nama kasir) ada di [deviceSettingsProvider].
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Map<String, String>>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    ref.watch(syncRevisionProvider);
    final local = await _fetchLocal();
    // Versi lama menyimpan printer di sini; pindahkan sekali ke penyimpanan HP.
    await ref.read(deviceSettingsProvider.notifier).migrateLegacyPrinter(local);
    return local;
  }

  Future<Map<String, String>> _fetchLocal() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> setSetting(String key, String value) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // insert-or-replace: key baru juga tersimpan (versi lama pakai UPDATE,
      // sehingga key yang belum ada diam-diam tidak tersimpan).
      await txn.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncStore.enqueue(txn,
          table: SyncTables.settings, op: SyncOp.upsert, row: {'key': key, 'value': value});
    });
    state = AsyncData(await _fetchLocal());
    ref.read(syncControllerProvider).requestSync();
  }

  String get(String key) {
    return state.valueOrNull?[key] ?? '';
  }
}
