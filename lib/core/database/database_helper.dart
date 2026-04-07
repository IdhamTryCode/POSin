import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;
  static String? _currentUserId;

  DatabaseHelper._init();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._init();
    return _instance!;
  }

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
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Categories table with user_id
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Products table with user_id
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

    // Variant groups table with user_id
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

    // Variant options table with user_id
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

    // Orders table with user_id
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        order_number TEXT NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        amount_paid REAL,
        change_amount REAL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Order items table with user_id
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
        variant_label TEXT
      )
    ''');

    // Settings table (local only, no user_id needed)
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _insertDefaultSettings(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Version 1 to 2: Add variant tables and variant_label column
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
      await db.execute(
        'ALTER TABLE order_items ADD COLUMN variant_label TEXT',
      );
      await db.insert(
        'settings',
        {'key': 'logo_url', 'value': ''},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Version 2 to 3: Add user_id column to all tables
    if (oldVersion < 3) {
      // Add user_id to categories
      await db.execute('ALTER TABLE categories ADD COLUMN user_id TEXT');
      
      // Add user_id to products
      await db.execute('ALTER TABLE products ADD COLUMN user_id TEXT');
      
      // Add user_id to variant groups
      await db.execute('ALTER TABLE product_variant_groups ADD COLUMN user_id TEXT');
      
      // Add user_id to variant options
      await db.execute('ALTER TABLE product_variant_options ADD COLUMN user_id TEXT');
      
      // Add user_id to orders
      await db.execute('ALTER TABLE orders ADD COLUMN user_id TEXT');
      
      // Add user_id to order items
      await db.execute('ALTER TABLE order_items ADD COLUMN user_id TEXT');
    }

    if (oldVersion < 4) {
      await db.insert(
        'settings',
        {'key': 'store_description', 'value': ''},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _insertDefaultSettings(Database db) async {
    const defaults = {
      'store_name': 'Toko Saya',
      'store_address': '',
      'store_phone': '',
      'store_description': '',
      'receipt_footer': 'Terima kasih!',
      'printer_address': '',
      'printer_name': '',
      'logo_url': '',
    };
    for (final e in defaults.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value});
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
