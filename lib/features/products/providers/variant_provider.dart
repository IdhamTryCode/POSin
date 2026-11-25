import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_store.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/variant_group_model.dart';
import '../models/variant_option_model.dart';

// Groups + options untuk 1 produk
final variantGroupProvider = AsyncNotifierProviderFamily<
    VariantGroupNotifier, List<VariantGroupModel>, String>(
  VariantGroupNotifier.new,
);

class VariantGroupNotifier
    extends FamilyAsyncNotifier<List<VariantGroupModel>, String> {
  @override
  Future<List<VariantGroupModel>> build(String productId) async {
    ref.watch(syncRevisionProvider);
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

  String? get _uid => ref.read(supabaseAuthProvider).valueOrNull?.id;

  Future<bool> _write(Future<void> Function(Transaction txn) body) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction(body);
      state = AsyncData(await _fetchAll(arg));
      ref.read(syncControllerProvider).requestSync();
      return true;
    } catch (e) {
      debugPrint('Error writing variant: $e');
      return false;
    }
  }

  Future<VariantGroupModel?> addGroup(String name, bool isRequired) async {
    final group = VariantGroupModel(
      id: const Uuid().v4(),
      userId: _uid,
      productId: arg,
      name: name,
      isRequired: isRequired,
      createdAt: DateTime.now().toIso8601String(),
    );
    final ok = await _write((txn) async {
      await txn.insert('product_variant_groups', group.toMap());
      await SyncStore.enqueue(txn, table: SyncTables.variantGroups, op: SyncOp.upsert, row: group.toMap());
    });
    return ok ? group : null;
  }

  Future<bool> updateGroup(VariantGroupModel group) => _write((txn) async {
        await txn.update('product_variant_groups', group.toMap(),
            where: 'id = ?', whereArgs: [group.id]);
        await SyncStore.enqueue(txn, table: SyncTables.variantGroups, op: SyncOp.upsert, row: group.toMap());
      });

  Future<bool> deleteGroup(String groupId) => _write((txn) async {
        final options = await txn.query('product_variant_options',
            columns: ['id'], where: 'group_id = ?', whereArgs: [groupId]);
        for (final o in options) {
          await SyncStore.enqueue(txn,
              table: SyncTables.variantOptions, op: SyncOp.delete, row: {'id': o['id']});
        }
        await txn.delete('product_variant_options', where: 'group_id = ?', whereArgs: [groupId]);
        await txn.delete('product_variant_groups', where: 'id = ?', whereArgs: [groupId]);
        await SyncStore.enqueue(txn, table: SyncTables.variantGroups, op: SyncOp.delete, row: {'id': groupId});
      });

  Future<bool> addOption(String groupId, String name, double priceModifier) {
    final option = VariantOptionModel(
      id: const Uuid().v4(),
      userId: _uid,
      groupId: groupId,
      name: name,
      priceModifier: priceModifier,
      createdAt: DateTime.now().toIso8601String(),
    );
    return _write((txn) async {
      await txn.insert('product_variant_options', option.toMap());
      await SyncStore.enqueue(txn, table: SyncTables.variantOptions, op: SyncOp.upsert, row: option.toMap());
    });
  }

  Future<bool> deleteOption(String optionId) => _write((txn) async {
        await txn.delete('product_variant_options', where: 'id = ?', whereArgs: [optionId]);
        await SyncStore.enqueue(txn, table: SyncTables.variantOptions, op: SyncOp.delete, row: {'id': optionId});
      });
}
