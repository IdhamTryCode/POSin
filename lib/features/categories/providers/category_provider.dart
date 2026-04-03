import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/category_model.dart';

final categoryProvider =
    AsyncNotifierProvider<CategoryNotifier, List<CategoryModel>>(
  CategoryNotifier.new,
);

class CategoryNotifier extends AsyncNotifier<List<CategoryModel>> {
  @override
  Future<List<CategoryModel>> build() async {
    return _fetchAll();
  }

  Future<List<CategoryModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('categories', orderBy: 'created_at ASC');
    return maps.map((m) => CategoryModel.fromMap(m)).toList();
  }

  Future<void> syncFromCloud() async {
    state = const AsyncLoading();
    try {
      final remote = await SupabaseService.instance.fetchCategories();
      if (remote.isNotEmpty) {
        final db = await DatabaseHelper.instance.database;
        await db.delete('categories');
        for (final c in remote) {
          await db.insert('categories', c.toMap());
        }
      }
    } catch (_) {}
    state = AsyncData(await _fetchAll());
  }

  Future<bool> add(String name, int color) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      
      final category = CategoryModel(
        id: const Uuid().v4(),
        userId: uid,
        name: name,
        color: color,
        createdAt: DateTime.now().toIso8601String(),
      );
      
      await db.insert('categories', category.toMap());
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertCategory(category);
      if (!success) {
        debugPrint('Warning: Failed to sync category to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error adding category: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> updateCategory(CategoryModel category) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'categories',
        category.toMap(),
        where: 'id = ?',
        whereArgs: [category.id],
      );
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertCategory(category);
      if (!success) {
        debugPrint('Warning: Failed to sync category update to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error updating category: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('categories', where: 'id = ?', whereArgs: [id]);
      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.deleteCategory(id);
      if (!success) {
        debugPrint('Warning: Failed to delete category from Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting category: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }
}
