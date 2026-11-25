import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/device/device_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_store.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../models/order_totals.dart';
import 'cart_provider.dart';

final orderProvider =
    AsyncNotifierProvider<OrderNotifier, List<OrderModel>>(
  OrderNotifier.new,
);

class ProductStat {
  final String name;
  final int qty;
  final double revenue;
  const ProductStat({required this.name, required this.qty, required this.revenue});
}

/// Produk terlaris dalam rentang waktu (satu query agregasi, bukan 1 query per order).
final topProductsProvider = FutureProvider.autoDispose
    .family<List<ProductStat>, ({DateTime start, DateTime end})>((ref, range) async {
  ref.watch(orderProvider); // hitung ulang saat ada pesanan baru / void
  return ref.read(orderProvider.notifier).topProducts(range.start, range.end);
});

class OrderNotifier extends AsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() async {
    ref.watch(syncRevisionProvider); // muat ulang saat ada data dari HP lain
    return _fetchAll();
  }

  Future<List<OrderModel>> _fetchAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('orders', orderBy: 'created_at DESC');
    return maps.map((m) => OrderModel.fromMap(m)).toList();
  }

  /// Simpan pesanan. Tidak menunggu internet: pesanan + itemnya + antrean
  /// upload ditulis dalam SATU transaksi SQLite, lalu dikirim di background.
  Future<OrderModel?> checkout({
    required List<CartItem> items,
    required OrderTotals totals,
    String? taxName,
    required String paymentMethod,
    double? amountPaid,
    String? note,
    String? customerName,
  }) async {
    final total = totals.total;
    try {
      final db = await DatabaseHelper.instance.database;
      final uid = ref.read(supabaseAuthProvider).valueOrNull?.id;
      final device = ref.read(deviceSettingsProvider);
      final orderId = const Uuid().v4();
      final now = DateTime.now();

      final orderItems = [
        for (final item in items)
          OrderItemModel(
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
          ),
      ];

      late OrderModel order;
      await db.transaction((txn) async {
        final dailyNumber = await generateDailyNumber(txn, now, device);
        order = OrderModel(
          id: orderId,
          userId: uid,
          orderNumber: _generateOrderNumber(now),
          dailyNumber: dailyNumber,
          total: total,
          paymentMethod: paymentMethod,
          amountPaid: amountPaid,
          changeAmount: amountPaid != null ? amountPaid - total : null,
          note: note,
          createdAt: now.toIso8601String(),
          deviceId: device.deviceId,
          cashierName: device.cashierName.isEmpty ? null : device.cashierName,
          customerName: (customerName ?? '').trim().isEmpty ? null : customerName!.trim(),
          subtotal: totals.subtotal,
          discountAmount: totals.discount,
          taxName: totals.tax > 0 ? taxName : null,
          taxPercent: totals.tax > 0 ? totals.taxPercent : null,
          taxAmount: totals.tax,
          items: orderItems,
        );
        await txn.insert('orders', order.toMap());
        await SyncStore.enqueue(txn, table: SyncTables.orders, op: SyncOp.insert, row: order.toMap());

        for (final orderItem in orderItems) {
          await txn.insert('order_items', orderItem.toMap());
          await SyncStore.enqueue(txn,
              table: SyncTables.orderItems, op: SyncOp.insert, row: orderItem.toMap());
        }
      });

      state = AsyncData(await _fetchAll());
      ref.read(syncControllerProvider).requestSync();
      return order;
    } catch (e, st) {
      debugPrint('Error during checkout: $e\n$st');
      return null;
    }
  }

  /// Batalkan pesanan. Pesanan TIDAK dihapus: tetap tercatat sebagai "dibatalkan"
  /// beserta alasannya (jejak audit), dan tidak dihitung di omzet.
  Future<bool> voidOrder(String orderId, String reason) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        final rows = await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
        if (rows.isEmpty) throw StateError('Pesanan tidak ditemukan');
        final current = OrderModel.fromMap(rows.first);
        if (current.isVoid) return;
        final voided = current.voided(reason.trim(), DateTime.now());
        await txn.update('orders', voided.toMap(), where: 'id = ?', whereArgs: [orderId]);
        await SyncStore.enqueue(txn, table: SyncTables.orders, op: SyncOp.upsert, row: voided.toMap());
      });
      state = AsyncData(await _fetchAll());
      ref.read(syncControllerProvider).requestSync();
      return true;
    } catch (e) {
      debugPrint('Error voiding order: $e');
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

  Future<List<ProductStat>> topProducts(DateTime start, DateTime end, {int limit = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT oi.product_id, MAX(oi.product_name) AS name,
             SUM(oi.qty) AS qty, SUM(oi.subtotal) AS revenue
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE o.status = 'paid' AND o.created_at >= ? AND o.created_at < ?
      GROUP BY oi.product_id
      ORDER BY revenue DESC
      LIMIT ?
    ''', [start.toIso8601String(), end.toIso8601String(), limit]);
    return rows
        .map((r) => ProductStat(
              name: r['name'] as String,
              qty: (r['qty'] as num).toInt(),
              revenue: (r['revenue'] as num).toDouble(),
            ))
        .toList();
  }

  /// ID order unik sepanjang masa (format lama dipertahankan).
  String _generateOrderNumber(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

/// Nomor antrean harian 3 digit, reset tiap hari.
///
/// * Toko dengan 1 HP  : "001", "002", ...
/// * Toko dengan >1 HP : "A-001", "B-001", ... — setiap HP punya urutannya
///   sendiri, jadi dua kasir tidak pernah mencetak nomor yang sama walau offline.
///
/// Memakai max+1 (bukan count+1) supaya nomor tidak terpakai ulang.
@visibleForTesting
Future<String> generateDailyNumber(DatabaseExecutor db, DateTime now, DeviceSettings device) async {
  final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
  final startOfNext = DateTime(now.year, now.month, now.day + 1).toIso8601String();
  final prefix = device.queuePrefix;

  final rows = prefix.isEmpty
      ? await db.query('orders',
          columns: ['daily_number'],
          where: 'created_at >= ? AND created_at < ?',
          whereArgs: [startOfDay, startOfNext])
      : await db.query('orders',
          columns: ['daily_number'],
          where: 'created_at >= ? AND created_at < ? AND (device_id = ? OR daily_number LIKE ?)',
          whereArgs: [startOfDay, startOfNext, device.deviceId, '$prefix%']);

  var maxSeq = 0;
  final trailingDigits = RegExp(r'(\d+)$');
  for (final row in rows) {
    final match = trailingDigits.firstMatch((row['daily_number'] as String?) ?? '');
    final n = match == null ? null : int.tryParse(match.group(1)!);
    if (n != null && n > maxSeq) maxSeq = n;
  }
  return '$prefix${(maxSeq + 1).toString().padLeft(3, '0')}';
}
