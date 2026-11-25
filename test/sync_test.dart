import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posin/core/database/database_helper.dart';
import 'package:posin/core/device/device_settings.dart';
import 'package:posin/core/sync/sync_engine.dart';
import 'package:posin/core/sync/sync_remote.dart';
import 'package:posin/core/sync/sync_store.dart';
import 'package:posin/features/orders/providers/order_provider.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Server tiruan: menyimpan baris per tabel dengan updated_at dari "jam server".
class FakeRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {
    for (final t in SyncTables.all) t: {},
  };
  final List<List<Map<String, dynamic>>> pushes = [];
  DateTime clock = DateTime.utc(2026, 11, 25, 8);
  bool offline = false;
  Set<String> rejectRowIds = {};

  DateTime tick() => clock = clock.add(const Duration(seconds: 1));

  void serverWrite(String table, Map<String, dynamic> row, {bool deleted = false}) {
    final key = row[SyncTables.keyColumn(table)].toString();
    tables[table]![key] = {
      ...row,
      'updated_at': tick().toIso8601String(),
      'deleted_at': deleted ? clock.toIso8601String() : null,
    };
  }

  @override
  Future<void> push(List<Map<String, dynamic>> ops) async {
    if (offline) throw Exception('SocketException: offline');
    if (ops.any((o) => rejectRowIds.contains((o['r'] as Map)['id']))) {
      throw const SyncRejected('invalid row');
    }
    pushes.add(ops);
    for (final op in ops) {
      final t = op['t'] as String;
      final r = Map<String, dynamic>.from(op['r'] as Map);
      final key = r[SyncTables.keyColumn(t)].toString();
      final existing = tables[t]![key];
      switch (op['k']) {
        case 'insert':
          if (existing == null) serverWrite(t, r);
        case 'upsert':
          if (existing == null || existing['deleted_at'] == null) serverWrite(t, {...?existing, ...r});
        case 'delete':
          if (existing != null) serverWrite(t, existing, deleted: true);
      }
    }
  }

  @override
  Future<PullPage> pull(String table, {String? since, String? afterId, int limit = 500}) async {
    if (offline) throw Exception('SocketException: offline');
    final key = SyncTables.keyColumn(table);
    final rows = tables[table]!.values.where((r) {
      if (since == null) return true;
      final c = (r['updated_at'] as String).compareTo(since);
      return c > 0 || (c == 0 && (r[key] as String).compareTo(afterId ?? '') > 0);
    }).toList()
      ..sort((a, b) {
        final c = (a['updated_at'] as String).compareTo(b['updated_at'] as String);
        return c != 0 ? c : (a[key] as String).compareTo(b[key] as String);
      });
    return PullPage(rows.take(limit).toList(), clock.add(const Duration(minutes: 1)));
  }

  @override
  Future<DeviceRegistration> registerDevice(String deviceId, String? name) async =>
      const DeviceRegistration('A', 1);
}

Future<Database> openTestDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.schemaVersion,
        onCreate: (db, _) => DatabaseHelper.createSchema(db),
        singleInstance: false,
      ),
    );

Map<String, Object?> order(String id, {String created = '2026-11-25T10:00:00.000', String? daily, String? device}) => {
      'id': id,
      'order_number': 'N-$id',
      'daily_number': daily,
      'total': 10000.0,
      'payment_method': 'Tunai',
      'created_at': created,
      'status': 'paid',
      'device_id': device,
    };

void main() {
  setUpAll(sqfliteFfiInit);

  group('SyncStore', () {
    late Database db;
    late SyncStore store;
    setUp(() async {
      db = await openTestDb();
      store = SyncStore(db);
    });
    tearDown(() => db.close());

    test('enqueue dalam transaksi ikut rollback kalau transaksi gagal', () async {
      await expectLater(
        db.transaction((txn) async {
          await txn.insert('orders', order('o1'));
          await SyncStore.enqueue(txn, table: 'orders', op: SyncOp.insert, row: order('o1'));
          throw Exception('crash di tengah checkout');
        }),
        throwsException,
      );
      expect(await store.pendingCount(), 0);
      expect(await db.query('orders'), isEmpty);
    });

    test('baris dari server tidak menimpa perubahan lokal yang belum terkirim', () async {
      await db.insert('products', {'id': 'p1', 'name': 'Lokal', 'price': 1, 'created_at': 'x'});
      await SyncStore.enqueue(db, table: 'products', op: SyncOp.upsert,
          row: {'id': 'p1', 'name': 'Lokal', 'price': 1, 'created_at': 'x'});

      await store.applyPulled('products', [
        {'id': 'p1', 'name': 'Server', 'price': 2, 'created_at': 'x', 'updated_at': 't', 'deleted_at': null},
        {'id': 'p2', 'name': 'Baru', 'price': 3, 'created_at': 'x', 'updated_at': 't', 'deleted_at': null},
      ]);
      final rows = {for (final r in await db.query('products')) r['id']: r['name']};
      expect(rows, {'p1': 'Lokal', 'p2': 'Baru'});
    });

    test('tombstone menghapus baris lokal (dan item order-nya)', () async {
      await db.insert('orders', order('o1'));
      await db.insert('order_items', {
        'id': 'i1', 'order_id': 'o1', 'product_id': 'p', 'product_name': 'x',
        'price': 1, 'qty': 1, 'subtotal': 1,
      });
      await store.applyPulled('orders', [
        {...order('o1'), 'updated_at': 't', 'deleted_at': 't'},
      ]);
      expect(await db.query('orders'), isEmpty);
      expect(await db.query('order_items'), isEmpty);
    });

    test('setting printer dari cloud diabaikan (milik masing-masing HP)', () async {
      await store.applyPulled('settings', [
        {'key': 'printer_address', 'value': 'HP-LAIN', 'updated_at': 't', 'deleted_at': null},
        {'key': 'store_name', 'value': 'Toko Baru', 'updated_at': 't', 'deleted_at': null},
      ]);
      final rows = {for (final r in await db.query('settings')) r['key']: r['value']};
      expect(rows['store_name'], 'Toko Baru');
      expect(rows.containsKey('printer_address'), isFalse);
    });

    test('kolom server yang tidak ada di SQLite diabaikan', () async {
      await store.applyPulled('orders', [
        {...order('o1'), 'updated_at': 't', 'deleted_at': null, 'kolom_baru_server': 1},
      ]);
      expect((await db.query('orders')).single['id'], 'o1');
    });
  });

  group('SyncEngine', () {
    late Database db;
    late SyncStore store;
    late FakeRemote remote;
    late SyncEngine engine;
    setUp(() async {
      db = await openTestDb();
      store = SyncStore(db);
      remote = FakeRemote();
      engine = SyncEngine(store, remote);
    });
    tearDown(() => db.close());

    test('offline: antrean tetap utuh, terkirim setelah online', () async {
      await SyncStore.enqueue(db, table: 'orders', op: SyncOp.insert, row: order('o1'));
      remote.offline = true;
      await expectLater(engine.run(), throwsException);
      expect(await store.pendingCount(), 1);

      remote.offline = false;
      final res = await engine.run();
      expect(res.pushed, 1);
      expect(await store.pendingCount(), 0);
      expect(remote.tables['orders']!.containsKey('o1'), isTrue);
    });

    test('satu operasi ditolak server tidak memblokir yang lain', () async {
      for (final id in ['o1', 'bad', 'o3']) {
        await SyncStore.enqueue(db, table: 'orders', op: SyncOp.insert, row: order(id));
      }
      remote.rejectRowIds = {'bad'};
      final res = await engine.run();
      expect(res.pushed, 2);
      expect(res.rejected, 1);
      expect(remote.tables['orders']!.keys, containsAll(['o1', 'o3']));
      expect(await store.pendingCount(), 1); // dicoba lagi nanti

      for (var i = 0; i < SyncStore.maxAttempts; i++) {
        await engine.run();
      }
      expect(await store.pendingCount(), 0);
      expect(await store.failedCount(), 1); // ditandai gagal, tidak memblokir
    });

    test('pesanan dari HP lain masuk ke HP ini (termasuk pembatalan)', () async {
      remote.serverWrite('orders', order('dari-hp-lain'));
      await engine.run();
      expect((await db.query('orders')).map((r) => r['id']), ['dari-hp-lain']);

      remote.serverWrite('orders', {...order('dari-hp-lain'), 'status': 'void', 'void_reason': 'batal'});
      await engine.run();
      expect((await db.query('orders')).single['status'], 'void');
    });

    test('paginasi: lebih dari 1 halaman tetap tertarik semua', () async {
      for (var i = 0; i < SyncEngine.pullPageSize + 120; i++) {
        remote.serverWrite('orders', order('o${i.toString().padLeft(4, '0')}'));
      }
      await engine.run();
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM orders')),
          SyncEngine.pullPageSize + 120);
    });

    test('sync ulang tidak menarik data yang sama berkali-kali (kursor maju)', () async {
      remote.serverWrite('products', {'id': 'p1', 'name': 'Kopi', 'price': 1, 'created_at': 'x'});
      remote.clock = remote.clock.add(const Duration(hours: 1)); // jauh melewati overlap
      await engine.run();
      final changed = await engine.pullAll();
      expect(changed, 0);
    });

    test('upgrade dari versi lama: data lokal lama dikirim tanpa menimpa cloud', () async {
      // Simulasikan DB versi 6 dengan satu order yang belum pernah ter-upload.
      final legacy = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      // Skema persis versi 6 (sebelum Tahap 1).
      for (final ddl in [
        'CREATE TABLE categories (id TEXT PRIMARY KEY, user_id TEXT, name TEXT NOT NULL, color INTEGER NOT NULL, created_at TEXT NOT NULL)',
        'CREATE TABLE products (id TEXT PRIMARY KEY, user_id TEXT, name TEXT NOT NULL, price REAL NOT NULL, category_id TEXT, image_path TEXT, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)',
        'CREATE TABLE product_variant_groups (id TEXT PRIMARY KEY, user_id TEXT, product_id TEXT NOT NULL, name TEXT NOT NULL, is_required INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)',
        'CREATE TABLE product_variant_options (id TEXT PRIMARY KEY, user_id TEXT, group_id TEXT NOT NULL, name TEXT NOT NULL, price_modifier REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL)',
        'CREATE TABLE orders (id TEXT PRIMARY KEY, user_id TEXT, order_number TEXT NOT NULL, daily_number TEXT, total REAL NOT NULL, payment_method TEXT NOT NULL, amount_paid REAL, change_amount REAL, note TEXT, created_at TEXT NOT NULL)',
        'CREATE TABLE order_items (id TEXT PRIMARY KEY, user_id TEXT, order_id TEXT NOT NULL, product_id TEXT NOT NULL, product_name TEXT NOT NULL, price REAL NOT NULL, qty INTEGER NOT NULL, subtotal REAL NOT NULL, variant_label TEXT, note TEXT)',
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      ]) {
        await legacy.execute(ddl);
      }
      await legacy.insert('orders', {'id': 'offline-1', 'order_number': 'n', 'total': 5000,
          'payment_method': 'Tunai', 'created_at': '2026-11-20T09:00:00.000', 'user_id': 'u'});

      await DatabaseHelper.upgradeSchema(legacy, 6, 7);
      final q = await SyncStore(legacy).nextBatch();
      expect(q.single.op, SyncOp.insert);
      expect(q.single.payload['id'], 'offline-1');
      expect(q.single.payload.containsKey('user_id'), isFalse);
      expect(jsonEncode(q.single.payload), contains('"status":"paid"'));
      await legacy.close();
    });
  });

  group('Nomor antrean harian', () {
    late Database db;
    setUp(() async => db = await openTestDb());
    tearDown(() => db.close());

    final now = DateTime(2026, 11, 25, 12);
    const single = DeviceSettings(deviceId: 'dev-a', deviceCode: 'A', deviceCount: 1);
    const multiA = DeviceSettings(deviceId: 'dev-a', deviceCode: 'A', deviceCount: 2);
    const multiB = DeviceSettings(deviceId: 'dev-b', deviceCode: 'B', deviceCount: 2);

    test('1 HP: 001, 002, ... dan reset tiap hari', () async {
      expect(await generateDailyNumber(db, now, single), '001');
      await db.insert('orders', order('o1', daily: '001'));
      await db.insert('orders', order('o2', daily: '002'));
      await db.insert('orders', order('kemarin', created: '2026-11-24T23:59:00.000', daily: '050'));
      expect(await generateDailyNumber(db, now, single), '003');
    });

    test('nomor tidak dipakai ulang setelah ada yang dibatalkan/dihapus', () async {
      await db.insert('orders', order('o5', daily: '005'));
      expect(await generateDailyNumber(db, now, single), '006');
    });

    test('2 HP: masing-masing punya urutan sendiri, tidak pernah bentrok', () async {
      await db.insert('orders', order('a1', daily: 'A-001', device: 'dev-a'));
      await db.insert('orders', order('a2', daily: 'A-002', device: 'dev-a'));
      await db.insert('orders', order('b1', daily: 'B-001', device: 'dev-b'));
      expect(await generateDailyNumber(db, now, multiA), 'A-003');
      expect(await generateDailyNumber(db, now, multiB), 'B-002');
    });

    test('HP yang baru berubah jadi multi-HP melanjutkan urutannya sendiri', () async {
      await db.insert('orders', order('a1', daily: '004', device: 'dev-a'));
      expect(await generateDailyNumber(db, now, multiA), 'A-005');
    });
  });
}
