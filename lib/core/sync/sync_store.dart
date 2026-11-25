import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Tabel yang disinkronkan, urut sesuai ketergantungan (induk dulu).
class SyncTables {
  SyncTables._();

  static const categories = 'categories';
  static const products = 'products';
  static const variantGroups = 'product_variant_groups';
  static const variantOptions = 'product_variant_options';
  static const orders = 'orders';
  static const orderItems = 'order_items';
  static const settings = 'settings';

  static const all = [
    categories, products, variantGroups, variantOptions, orders, orderItems, settings,
  ];

  static String keyColumn(String table) => table == settings ? 'key' : 'id';

  /// Setting milik masing-masing HP — tidak pernah dikirim/diterima dari cloud.
  static const deviceLocalSettingKeys = {'printer_address', 'printer_name'};
}

/// Jenis operasi antrean (lihat push_changes di Supabase).
class SyncOp {
  SyncOp._();
  static const upsert = 'upsert'; // buat / perbarui
  static const insert = 'insert'; // buat kalau belum ada (aman diulang)
  static const delete = 'delete'; // soft delete
}

class QueuedOp {
  final int seq;
  final String table;
  final String op;
  final String rowId;
  final Map<String, dynamic> payload;
  final int attempts;

  const QueuedOp({
    required this.seq,
    required this.table,
    required this.op,
    required this.rowId,
    required this.payload,
    required this.attempts,
  });

  Map<String, dynamic> toRpc() => {'t': table, 'k': op, 'r': payload};
}

class SyncCursor {
  final String? since;
  final String? afterId;
  const SyncCursor(this.since, this.afterId);
}

/// Semua operasi SQLite untuk sinkronisasi. Tidak tahu apa-apa soal jaringan,
/// sehingga bisa dites dengan database in-memory.
class SyncStore {
  final Database db;
  SyncStore(this.db);

  static const maxAttempts = 5;

  /// Catat perubahan ke antrean. Panggil DI DALAM transaksi yang sama dengan
  /// perubahan datanya (pakai `txn`), supaya keduanya selalu konsisten.
  static Future<void> enqueue(
    DatabaseExecutor txn, {
    required String table,
    required String op,
    required Map<String, Object?> row,
  }) async {
    final payload = Map<String, Object?>.from(row)..remove('user_id');
    final rowId = (payload[SyncTables.keyColumn(table)] ?? '').toString();
    await txn.insert('sync_queue', {
      'tbl': table,
      'op': op,
      'row_id': rowId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// [afterSeq]: lewati operasi yang sudah diproses di putaran sync ini
  /// (yang ditolak server dicoba lagi di putaran berikutnya, bukan langsung).
  Future<List<QueuedOp>> nextBatch({int limit = 200, int afterSeq = 0}) async {
    final rows = await db.query(
      'sync_queue',
      where: 'failed = 0 AND seq > ?',
      whereArgs: [afterSeq],
      orderBy: 'seq ASC',
      limit: limit,
    );
    return rows
        .map((r) => QueuedOp(
              seq: r['seq'] as int,
              table: r['tbl'] as String,
              op: r['op'] as String,
              rowId: r['row_id'] as String,
              payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              attempts: r['attempts'] as int,
            ))
        .toList();
  }

  Future<void> ack(List<int> seqs) async {
    if (seqs.isEmpty) return;
    await db.delete('sync_queue',
        where: 'seq IN (${List.filled(seqs.length, '?').join(',')})', whereArgs: seqs);
  }

  /// Operasi yang ditolak server (bukan masalah jaringan). Setelah [maxAttempts]
  /// ditandai gagal supaya tidak memblokir antrean di belakangnya.
  Future<void> markRejected(QueuedOp op, String error) async {
    final attempts = op.attempts + 1;
    await db.update(
      'sync_queue',
      {
        'attempts': attempts,
        'failed': attempts >= maxAttempts ? 1 : 0,
        'last_error': error.length > 500 ? error.substring(0, 500) : error,
      },
      where: 'seq = ?',
      whereArgs: [op.seq],
    );
  }

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_queue WHERE failed = 0')) ?? 0;

  Future<int> failedCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_queue WHERE failed = 1')) ?? 0;

  /// Coba ulang operasi yang pernah ditandai gagal.
  Future<void> retryFailed() async {
    await db.update('sync_queue', {'failed': 0, 'attempts': 0}, where: 'failed = 1');
  }

  Future<SyncCursor> cursor(String table) async {
    final rows = await db.query('sync_cursor', where: 'tbl = ?', whereArgs: [table]);
    if (rows.isEmpty) return const SyncCursor(null, null);
    return SyncCursor(rows.first['since'] as String?, rows.first['after_id'] as String?);
  }

  Future<void> saveCursor(String table, SyncCursor c) async {
    await db.insert(
      'sync_cursor',
      {'tbl': table, 'since': c.since, 'after_id': c.afterId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  final Map<String, Set<String>> _columnCache = {};

  Future<Set<String>> _localColumns(DatabaseExecutor ex, String table) async {
    final cached = _columnCache[table];
    if (cached != null) return cached;
    final info = await ex.rawQuery('PRAGMA table_info($table)');
    return _columnCache[table] = info.map((c) => c['name'] as String).toSet();
  }

  /// Terapkan baris dari server ke SQLite. Baris yang masih punya perubahan
  /// lokal di antrean DILEWATI (perubahan lokal menang sampai terkirim, lalu
  /// versi server-nya akan datang lagi di tarikan berikutnya).
  /// Mengembalikan jumlah baris lokal yang berubah.
  Future<int> applyPulled(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    final key = SyncTables.keyColumn(table);
    var changed = 0;

    await db.transaction((txn) async {
      final cols = await _localColumns(txn, table);
      final ids = rows.map((r) => r[key].toString()).toList();
      final pending = <String>{};
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        final res = await txn.query(
          'sync_queue',
          columns: ['row_id'],
          where: 'tbl = ? AND row_id IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: [table, ...chunk],
        );
        pending.addAll(res.map((r) => r['row_id'] as String));
      }

      for (final row in rows) {
        final id = row[key].toString();
        if (pending.contains(id)) continue;
        if (table == SyncTables.settings && SyncTables.deviceLocalSettingKeys.contains(id)) continue;

        if (row['deleted_at'] != null) {
          changed += await txn.delete(table, where: '$key = ?', whereArgs: [id]);
          if (table == SyncTables.orders) {
            await txn.delete(SyncTables.orderItems, where: 'order_id = ?', whereArgs: [id]);
          }
          continue;
        }

        final local = <String, Object?>{};
        row.forEach((k, v) {
          if (cols.contains(k)) local[k] = v is bool ? (v ? 1 : 0) : v;
        });
        await txn.insert(table, local, conflictAlgorithm: ConflictAlgorithm.replace);
        changed++;
      }
    });
    return changed;
  }
}
