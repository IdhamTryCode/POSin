import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/variant_group_model.dart';
import '../models/variant_option_model.dart';

// Groups + options untuk 1 produk
final variantGroupProvider = AsyncNotifierProviderFamily<
    VariantGroupNotifier, List<VariantGroupModel>, String>(
  VariantGroupNotifier.new,
);

final variantSyncProvider = Provider<VariantSyncService>(
  (ref) => VariantSyncService(),
);

class VariantSyncService {
  Future<void> syncFromCloud() async {
    try {
      final remoteGroups = await SupabaseService.instance.fetchVariantGroups();
      final remoteOptions = await SupabaseService.instance.fetchVariantOptions();
      if (remoteGroups.isEmpty && remoteOptions.isEmpty) return;

      final db = await DatabaseHelper.instance.database;
      await db.delete('product_variant_options');
      await db.delete('product_variant_groups');

      for (final group in remoteGroups) {
        await db.insert('product_variant_groups', group.toMap());
      }
      for (final option in remoteOptions) {
        await db.insert('product_variant_options', option.toMap());
      }
    } catch (e) {
      debugPrint('Warning: Failed to sync variants from Supabase: $e');
    }
  }
}

class VariantGroupNotifier
    extends FamilyAsyncNotifier<List<VariantGroupModel>, String> {
  @override
  Future<List<VariantGroupModel>> build(String productId) async {
    return _fetchAll(productId);
  }

  Future<List<VariantGroupModel>> _fetchAll(String productId) async {
    final db = await DatabaseHelper.instance.database;
    final groups = await db.query(
      'product_variant_groups',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at ASC',
    );
    final result = <VariantGroupModel>[];
    for (final g in groups) {
      final group = VariantGroupModel.fromMap(g);
      final options = await db.query(
        'product_variant_options',
        where: 'group_id = ?',
        whereArgs: [group.id],
        orderBy: 'created_at ASC',
      );
      result.add(group.copyWith(
        options: options.map((o) => VariantOptionModel.fromMap(o)).toList(),
      ));
    }
    return result;
  }

  Future<VariantGroupModel?> addGroup(String name, bool isRequired) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      
      final group = VariantGroupModel(
        id: const Uuid().v4(),
        userId: uid,
        productId: arg,
        name: name,
        isRequired: isRequired,
        createdAt: DateTime.now().toIso8601String(),
      );
      
      await db.insert('product_variant_groups', group.toMap());
      state = AsyncData(await _fetchAll(arg));
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertVariantGroup(group);
      if (!success) {
        debugPrint('Warning: Failed to sync variant group to Supabase');
      }
      return group;
    } catch (e) {
      debugPrint('Error adding variant group: $e');
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }

  Future<bool> updateGroup(VariantGroupModel group) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'product_variant_groups',
        group.toMap(),
        where: 'id = ?',
        whereArgs: [group.id],
      );
      state = AsyncData(await _fetchAll(arg));
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertVariantGroup(group);
      if (!success) {
        debugPrint('Warning: Failed to sync variant group update to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error updating variant group: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> deleteGroup(String groupId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'product_variant_options',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      await db.delete(
        'product_variant_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
      state = AsyncData(await _fetchAll(arg));
      
      // Sync to Supabase
      final success = await SupabaseService.instance.deleteVariantGroup(groupId);
      if (!success) {
        debugPrint('Warning: Failed to delete variant group from Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting variant group: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> addOption(String groupId, String name, double priceModifier) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      
      final option = VariantOptionModel(
        id: const Uuid().v4(),
        userId: uid,
        groupId: groupId,
        name: name,
        priceModifier: priceModifier,
        createdAt: DateTime.now().toIso8601String(),
      );
      
      await db.insert('product_variant_options', option.toMap());
      state = AsyncData(await _fetchAll(arg));
      
      // Sync to Supabase
      final success = await SupabaseService.instance.upsertVariantOption(option);
      if (!success) {
        debugPrint('Warning: Failed to sync variant option to Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error adding variant option: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> deleteOption(String optionId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'product_variant_options',
        where: 'id = ?',
        whereArgs: [optionId],
      );
      state = AsyncData(await _fetchAll(arg));
      
      // Sync to Supabase
      final success = await SupabaseService.instance.deleteVariantOption(optionId);
      if (!success) {
        debugPrint('Warning: Failed to delete variant option from Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting variant option: $e');
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }
}
