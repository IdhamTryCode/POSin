import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;
  static String? _currentUserId;

  static const int schemaVersion = 8;

  DatabaseHelper._init();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._init();
    return _instance!;
  }

  static String? get currentUserId => _currentUserId;

  /// Panggil ini setelah login untuk switch ke DB user yang sesuai
  static void setUser(String userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _database = null; // reset supaya re-init dengan file baru
    }
  }

  static void clearUser() {
    _currentUserId = null;
    _database = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    final filename = _currentUserId != null ? 'posin_$_currentUserId.db' : 'posin.db';
    _database = await _initDB(filename);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, _) => createSchema(db),
      onUpgrade: upgradeSchema,
    );
  }

  /// Skema terbaru (dipakai juga oleh test).
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        category_id TEXT,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE product_variant_groups (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        is_required INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE product_variant_options (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        group_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price_modifier REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        order_number TEXT NOT NULL,
        daily_number TEXT,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        amount_paid REAL,
        change_amount REAL,
        note TEXT,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'paid',
        voided_at TEXT,
        void_reason TEXT,
        device_id TEXT,
        cashier_name TEXT,
        customer_name TEXT,
        created_at_ts TEXT,
        subtotal REAL,
        discount_amount REAL NOT NULL DEFAULT 0,
        tax_name TEXT,
        tax_percent REAL,
        tax_amount REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        price REAL NOT NULL,
        qty INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        variant_label TEXT,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createSyncTables(db);
    await _createIndexes(db);
    await _insertDefaultSettings(db);
  }

  static Future<void> _createSyncTables(DatabaseExecutor db) async {
    // Antrean perubahan lokal yang belum terkirim ke cloud (outbox).
    // Ditulis dalam transaksi yang SAMA dengan perubahan datanya, jadi tidak
    // ada perubahan yang bisa hilang walau app mati / offline.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        tbl TEXT NOT NULL,
        op TEXT NOT NULL,
        row_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        failed INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS sync_queue_row_idx ON sync_queue (tbl, row_id)');

    // Kursor tarik data per tabel: (updated_at, id) baris terakhir dari server.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursor (
        tbl TEXT PRIMARY KEY,
        since TEXT,
        after_id TEXT
      )
    ''');
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS orders_created_idx ON orders (created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS order_items_order_idx ON order_items (order_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS variant_groups_product_idx ON product_variant_groups (product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS variant_options_group_idx ON product_variant_options (group_id)');
  }

  static Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_variant_groups (
          id TEXT PRIMARY KEY,
          product_id TEXT NOT NULL,
          name TEXT NOT NULL,
          is_required INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_variant_options (
          id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          name TEXT NOT NULL,
          price_modifier REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('ALTER TABLE order_items ADD COLUMN variant_label TEXT');
      await db.insert('settings', {'key': 'logo_url', 'value': ''},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 3) {
      for (final t in ['categories', 'products', 'product_variant_groups',
                       'product_variant_options', 'orders', 'order_items']) {
        await db.execute('ALTER TABLE $t ADD COLUMN user_id TEXT');
      }
    }

    if (oldVersion < 4) {
      await db.insert('settings', {'key': 'store_description', 'value': ''},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 5) {
      await db.execute('ALTER TABLE order_items ADD COLUMN note TEXT');
    }

    if (oldVersion < 6) {
      await db.execute('ALTER TABLE orders ADD COLUMN daily_number TEXT');
    }

    // Version 6 -> 7: sinkronisasi berbasis antrean + void order + identitas HP.
    if (oldVersion < 7) {
      await db.execute("ALTER TABLE orders ADD COLUMN status TEXT NOT NULL DEFAULT 'paid'");
      for (final col in ['voided_at', 'void_reason', 'device_id', 'cashier_name',
                         'customer_name', 'created_at_ts']) {
        await db.execute('ALTER TABLE orders ADD COLUMN $col TEXT');
      }
      await _createSyncTables(db);
      await _createIndexes(db);
      await _enqueueExistingRowsForReconcile(db);
    }

    // Version 7 -> 8: diskon & pajak opsional.
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE orders ADD COLUMN subtotal REAL');
      await db.execute('ALTER TABLE orders ADD COLUMN discount_amount REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE orders ADD COLUMN tax_name TEXT');
      await db.execute('ALTER TABLE orders ADD COLUMN tax_percent REAL');
      await db.execute('ALTER TABLE orders ADD COLUMN tax_amount REAL NOT NULL DEFAULT 0');
    }
  }

  /// Versi lama mengirim data ke cloud sekali jalan tanpa retry, jadi bisa saja
  /// ada pesanan/menu yang belum pernah ter-upload. Saat upgrade, semua baris
  /// lokal dimasukkan antrean sebagai `insert` — server hanya menambahkan yang
  /// BELUM ada (yang sudah ada / sudah dihapus di cloud tidak disentuh).
  static Future<void> _enqueueExistingRowsForReconcile(Database db) async {
    const tables = ['categories', 'products', 'product_variant_groups',
                    'product_variant_options', 'orders', 'order_items'];
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final t in tables) {
      for (final row in await db.query(t)) {
        final payload = Map<String, Object?>.from(row)..remove('user_id');
        batch.insert('sync_queue', {
          'tbl': t,
          'op': 'insert',
          'row_id': row['id'],
          'payload': jsonEncode(payload),
          'created_at': now,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _insertDefaultSettings(Database db) async {
    const defaults = {
      'store_name': 'Toko Saya',
      'store_address': '',
      'store_phone': '',
      'store_description': '',
      'receipt_footer': 'Terima kasih!',
      'logo_url': '',
    };
    for (final e in defaults.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
