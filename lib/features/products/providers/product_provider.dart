import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_store.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/product_model.dart';

final productProvider =
    AsyncNotifierProvider<ProductNotifier, List<ProductModel>>(
  ProductNotifier.new,
);

final filteredProductProvider = Provider.family<List<ProductModel>, String?>(
  (ref, categoryId) {
    final products = ref.watch(productProvider).valueOrNull ?? [];
    if (categoryId == null) return products.where((p) => p.isActive).toList();
    return products
        .where((p) => p.isActive && p.categoryId == categoryId)
        .toList();
  },
);

class ProductNotifier extends AsyncNotifier<List<ProductModel>> {
  @override
  Future<List<ProductModel>> build() async {
    ref.watch(syncRevisionProvider);
    return _fetchAll();
  }

  Future<List<ProductModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('products', orderBy: 'created_at ASC');
    return maps.map((m) => ProductModel.fromMap(m)).toList();
  }

  Future<bool> _write(Future<void> Function(Transaction txn) body) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction(body);
      state = AsyncData(await _fetchAll());
      ref.read(syncControllerProvider).requestSync();
      return true;
    } catch (e) {
      debugPrint('Error writing product: $e');
      return false;
    }
  }

  Future<bool> add({
    String? id,
    required String name,
    required double price,
    String? categoryId,
    String? imagePath,
  }) {
    final product = ProductModel(
      id: id ?? const Uuid().v4(),
      userId: ref.read(supabaseAuthProvider).valueOrNull?.id,
      name: name,
      price: price,
      categoryId: categoryId,
      imagePath: imagePath,
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
    );
    return _write((txn) async {
      await txn.insert('products', product.toMap());
      await SyncStore.enqueue(txn, table: SyncTables.products, op: SyncOp.upsert, row: product.toMap());
    });
  }

  Future<bool> updateProduct(ProductModel product) => _write((txn) async {
        await txn.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
        await SyncStore.enqueue(txn, table: SyncTables.products, op: SyncOp.upsert, row: product.toMap());
      });

  /// Hapus menu beserta grup & opsi variannya (di cloud: soft delete).
  Future<bool> delete(String id) => _write((txn) async {
        final groups = await txn.query('product_variant_groups',
            columns: ['id'], where: 'product_id = ?', whereArgs: [id]);
        for (final g in groups) {
          final groupId = g['id'] as String;
          final options = await txn.query('product_variant_options',
              columns: ['id'], where: 'group_id = ?', whereArgs: [groupId]);
          for (final o in options) {
            await SyncStore.enqueue(txn,
                table: SyncTables.variantOptions, op: SyncOp.delete, row: {'id': o['id']});
          }
          await txn.delete('product_variant_options', where: 'group_id = ?', whereArgs: [groupId]);
          await SyncStore.enqueue(txn,
              table: SyncTables.variantGroups, op: SyncOp.delete, row: {'id': groupId});
        }
        await txn.delete('product_variant_groups', where: 'product_id = ?', whereArgs: [id]);
        await txn.delete('products', where: 'id = ?', whereArgs: [id]);
        await SyncStore.enqueue(txn, table: SyncTables.products, op: SyncOp.delete, row: {'id': id});
      });
}
