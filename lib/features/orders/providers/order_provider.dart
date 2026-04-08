import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import 'cart_provider.dart';

final orderProvider =
    AsyncNotifierProvider<OrderNotifier, List<OrderModel>>(
  OrderNotifier.new,
);

class OrderNotifier extends AsyncNotifier<List<OrderModel>> {
  bool _isSyncing = false;

  @override
  Future<List<OrderModel>> build() async {
    final local = await _fetchAll();
    syncFromCloud().ignore();
    return local;
  }

  Future<List<OrderModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('orders', orderBy: 'created_at DESC');
    return maps.map((m) => OrderModel.fromMap(m)).toList();
  }

  Future<void> syncFromCloud() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final now = DateTime.now();
      final start = DateTime(2000, 1, 1);
      final remoteOrders = await SupabaseService.instance.fetchOrders(
        start: start,
        end: now.add(const Duration(days: 1)),
      );

      if (remoteOrders.isEmpty) {
        state = AsyncData(await _fetchAll());
        return;
      }

      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        await txn.delete('order_items');
        await txn.delete('orders');

        for (final order in remoteOrders) {
          await txn.insert(
            'orders',
            order.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        for (final order in remoteOrders) {
          final items = await SupabaseService.instance.fetchOrderItems(order.id);
          for (final item in items) {
            await txn.insert(
              'order_items',
              item.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('Warning: Failed to sync orders from Supabase: $e');
    } finally {
      _isSyncing = false;
    }
    state = AsyncData(await _fetchAll());
  }

  Future<OrderModel?> checkout({
    required List<CartItem> items,
    required double total,
    required String paymentMethod,
    double? amountPaid,
    String? note,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      final orderId = const Uuid().v4();
      final now = DateTime.now();
      final orderNumber = _generateOrderNumber(now);
      final dailyNumber = await _generateDailyOrderNumber(db, now);

      final order = OrderModel(
        id: orderId,
        userId: uid,
        orderNumber: orderNumber,
        dailyNumber: dailyNumber,
        total: total,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
        changeAmount: amountPaid != null ? amountPaid - total : null,
        note: note,
        createdAt: now.toIso8601String(),
      );

      await db.insert('orders', order.toMap());

      final orderItems = <OrderItemModel>[];
      for (final item in items) {
        final orderItem = OrderItemModel(
          id: const Uuid().v4(),
          userId: uid,
          orderId: orderId,
          productId: item.product.id,
          productName: item.product.name,
          price: item.effectivePrice,
          qty: item.qty,
          subtotal: item.subtotal,
          variantLabel: item.variantLabel.isNotEmpty ? item.variantLabel : null,
          note: item.note,
        );
        await db.insert('order_items', orderItem.toMap());
        orderItems.add(orderItem);
      }

      state = AsyncData(await _fetchAll());
      
      // Sync to Supabase
      final success = await SupabaseService.instance.syncOrder(order, orderItems);
      if (!success) {
        debugPrint('Warning: Failed to sync order to Supabase');
      }
      
      return order;
    } catch (e) {
      debugPrint('Error during checkout: $e');
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }

  Future<bool> deleteOrder(String orderId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        await txn.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
        await txn.delete('orders', where: 'id = ?', whereArgs: [orderId]);
      });
      state = AsyncData(await _fetchAll());

      // Sync delete to Supabase (best-effort)
      final ok = await SupabaseService.instance.deleteOrder(orderId);
      if (!ok) {
        debugPrint('Warning: Failed to delete order on Supabase');
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting order: $e');
      return false;
    }
  }

  Future<List<OrderItemModel>> getOrderItems(String orderId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      return maps.map((m) => OrderItemModel.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching order items: $e');
      return [];
    }
  }

  Future<List<OrderModel>> getOrdersByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'orders',
        where: 'created_at BETWEEN ? AND ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'created_at DESC',
      );
      return maps.map((m) => OrderModel.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching orders by date range: $e');
      return [];
    }
  }

  /// Original order ID format (unique across all time).
  String _generateOrderNumber(DateTime now) {
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final hms =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '$ymd-$hms';
  }

  /// 3-digit sequential number that resets daily (001, 002, ...).
  /// Uses max+1 of today's daily_number so deletes don't reuse numbers.
  Future<String> _generateDailyOrderNumber(Database db, DateTime now) async {
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final startOfNext = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final rows = await db.query(
      'orders',
      columns: ['daily_number'],
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [startOfDay, startOfNext],
    );
    int maxSeq = 0;
    for (final row in rows) {
      final raw = (row['daily_number'] as String?) ?? '';
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > maxSeq) maxSeq = parsed;
    }
    return (maxSeq + 1).toString().padLeft(3, '0');
  }
}
