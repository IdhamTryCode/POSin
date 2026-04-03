import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/supabase/supabase_service.dart';
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
    final local = await _fetchAll();
    syncFromCloud().ignore();
    return local;
  }

  Future<List<ProductModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('products', orderBy: 'created_at ASC');
    return maps.map((m) => ProductModel.fromMap(m)).toList();
  }

  Future<void> syncFromCloud() async {
    state = const AsyncLoading();
    try {
      final remote = await SupabaseService.instance.fetchProducts();
      if (remote.isNotEmpty) {
        final db = await DatabaseHelper.instance.database;
        await db.delete('products');
        for (final p in remote) {
          await db.insert('products', p.toMap());
        }
      }
    } catch (_) {}
    state = AsyncData(await _fetchAll());
  }

  Future<bool> add({
    required String name,
    required double price,
    String? categoryId,
    String? imagePath,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      
      final product = ProductModel(
        id: const Uuid().v4(),
        userId: uid,
        name: name,
        price: price,
        categoryId: categoryId,
        imagePath: imagePath,
        isActive: true,
        createdAt: DateTime.now().toIso8601String(),
      );
      
      await db.insert('products', product.toMap());
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertProduct(product);
      if (!success) {
        debugPrint('Warning: Failed to sync product to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error adding product: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> updateProduct(ProductModel product) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'products',
        product.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertProduct(product);
      if (!success) {
        debugPrint('Warning: Failed to sync product update to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error updating product: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products', where: 'id = ?', whereArgs: [id]);
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.deleteProduct(id);
      if (!success) {
        debugPrint('Warning: Failed to delete product from Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting product: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }
}
