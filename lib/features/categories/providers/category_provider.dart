import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_store.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/category_model.dart';

final categoryProvider =
    AsyncNotifierProvider<CategoryNotifier, List<CategoryModel>>(
  CategoryNotifier.new,
);

class CategoryNotifier extends AsyncNotifier<List<CategoryModel>> {
  @override
  Future<List<CategoryModel>> build() async {
    ref.watch(syncRevisionProvider);
    return _fetchAll();
  }

  Future<List<CategoryModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('categories', orderBy: 'created_at ASC');
    return maps.map((m) => CategoryModel.fromMap(m)).toList();
  }

  Future<bool> _write(Future<void> Function(Transaction txn) body) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction(body);
      state = AsyncData(await _fetchAll());
      ref.read(syncControllerProvider).requestSync();
      return true;
    } catch (e) {
      debugPrint('Error writing category: $e');
      return false;
    }
  }

  Future<bool> add(String name, int color) {
    final category = CategoryModel(
      id: const Uuid().v4(),
      userId: ref.read(supabaseAuthProvider).valueOrNull?.id,
      name: name,
      color: color,
      createdAt: DateTime.now().toIso8601String(),
    );
    return _write((txn) async {
      await txn.insert('categories', category.toMap());
      await SyncStore.enqueue(txn, table: SyncTables.categories, op: SyncOp.upsert, row: category.toMap());
    });
  }

  Future<bool> updateCategory(CategoryModel category) => _write((txn) async {
        await txn.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
        await SyncStore.enqueue(txn, table: SyncTables.categories, op: SyncOp.upsert, row: category.toMap());
      });

  Future<bool> delete(String id) => _write((txn) async {
        await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
        await SyncStore.enqueue(txn, table: SyncTables.categories, op: SyncOp.delete, row: {'id': id});
      });
}
