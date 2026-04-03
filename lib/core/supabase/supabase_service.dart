import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/categories/models/category_model.dart';
import '../../features/orders/models/order_item_model.dart';
import '../../features/orders/models/order_model.dart';
import '../../features/products/models/product_model.dart';
import '../../features/products/models/variant_group_model.dart';
import '../../features/products/models/variant_option_model.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  // ── Storage ───────────────────────────────────────────────────────────────

  Future<String?> uploadProductImage(String productId, File file) async {
    if (_uid == null) return null;
    try {
      final ext = file.path.split('.').last;
      final path = '$_uid/$productId.$ext';
      await _client.storage
          .from('product-images')
          .upload(path, file, fileOptions: FileOptions(upsert: true));
      return _client.storage.from('product-images').getPublicUrl(path);
    } catch (e) {
      _log('Error uploading product image: $e');
      return null;
    }
  }

  Future<String?> uploadStoreLogo(File file) async {
    if (_uid == null) return null;
    try {
      final ext = file.path.split('.').last;
      final path = '$_uid/logo.$ext';
      await _client.storage
          .from('store-assets')
          .upload(path, file, fileOptions: FileOptions(upsert: true));
      return _client.storage.from('store-assets').getPublicUrl(path);
    } catch (e) {
      _log('Error uploading store logo: $e');
      return null;
    }
  }

  // ── Categories ────────────────────────────────────────────────────────────

  Future<bool> upsertCategory(CategoryModel c) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _client.from('categories').upsert(c.toMapSupabase(uid));
      return true;
    } catch (e) {
      _log('Error upserting category: $e');
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    if (_uid == null) return false;
    try {
      await _client.from('categories').delete().eq('id', id);
      return true;
    } catch (e) {
      _log('Error deleting category: $e');
      return false;
    }
  }

  Future<List<CategoryModel>> fetchCategories() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('categories')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true);
      return rows.map((r) => CategoryModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching categories: $e');
      return [];
    }
  }

  // ── Products ──────────────────────────────────────────────────────────────

  Future<bool> upsertProduct(ProductModel p) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _client.from('products').upsert(p.toMapSupabase(uid));
      return true;
    } catch (e) {
      _log('Error upserting product: $e');
      return false;
    }
  }

  Future<bool> deleteProduct(String id) async {
    if (_uid == null) return false;
    try {
      await _client.from('products').delete().eq('id', id);
      return true;
    } catch (e) {
      _log('Error deleting product: $e');
      return false;
    }
  }

  Future<List<ProductModel>> fetchProducts() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('products')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return rows.map((r) => ProductModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching products: $e');
      return [];
    }
  }

  // ── Variants ──────────────────────────────────────────────────────────────

  Future<bool> upsertVariantGroup(VariantGroupModel g) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _client.from('product_variant_groups').upsert(g.toMapSupabase(uid));
      return true;
    } catch (e) {
      _log('Error upserting variant group: $e');
      return false;
    }
  }

  Future<bool> deleteVariantGroup(String id) async {
    if (_uid == null) return false;
    try {
      await _client.from('product_variant_groups').delete().eq('id', id);
      return true;
    } catch (e) {
      _log('Error deleting variant group: $e');
      return false;
    }
  }

  Future<List<VariantGroupModel>> fetchVariantGroups() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('product_variant_groups')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true);
      return rows.map((r) => VariantGroupModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching variant groups: $e');
      return [];
    }
  }

  Future<bool> upsertVariantOption(VariantOptionModel o) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _client.from('product_variant_options').upsert(o.toMapSupabase(uid));
      return true;
    } catch (e) {
      _log('Error upserting variant option: $e');
      return false;
    }
  }

  Future<bool> deleteVariantOption(String id) async {
    if (_uid == null) return false;
    try {
      await _client.from('product_variant_options').delete().eq('id', id);
      return true;
    } catch (e) {
      _log('Error deleting variant option: $e');
      return false;
    }
  }

  Future<List<VariantOptionModel>> fetchVariantOptions() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('product_variant_options')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true);
      return rows.map((r) => VariantOptionModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching variant options: $e');
      return [];
    }
  }

  // ── Orders ────────────────────────────────────────────────────────────────

  Future<bool> syncOrder(OrderModel order, List<OrderItemModel> items) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // Insert order
      await _client.from('orders').upsert(order.toMapSupabase(uid));
      
      // Insert order items
      for (final item in items) {
        await _client.from('order_items').upsert(item.toMapSupabase(uid));
      }
      return true;
    } catch (e) {
      _log('Error syncing order: $e');
      return false;
    }
  }

  Future<bool> deleteOrder(String id) async {
    if (_uid == null) return false;
    try {
      // Delete order items first (cascade will handle this if setup in DB)
      await _client.from('order_items').delete().eq('order_id', id);
      await _client.from('orders').delete().eq('id', id);
      return true;
    } catch (e) {
      _log('Error deleting order: $e');
      return false;
    }
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<List<OrderModel>> fetchOrders({
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('orders')
          .select()
          .eq('user_id', uid)
          .gte('created_at', start.toIso8601String())
          .lte('created_at', end.toIso8601String())
          .order('created_at', ascending: false);
      return rows.map((r) => OrderModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching orders: $e');
      return [];
    }
  }

  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('order_items')
          .select()
          .eq('user_id', uid)
          .eq('order_id', orderId);
      return rows.map((r) => OrderItemModel.fromMap(r)).toList();
    } catch (e) {
      _log('Error fetching order items: $e');
      return [];
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> upsertSetting(String key, String value) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client.from('settings').upsert({'user_id': uid, 'key': key, 'value': value});
    } catch (e) {
      _log('Error upserting setting: $e');
    }
  }

  Future<Map<String, String>> fetchSettings() async {
    final uid = _uid;
    if (uid == null) return {};
    try {
      final rows = await _client.from('settings').select().eq('user_id', uid);
      return {for (final r in rows) r['key'] as String: r['value'] as String};
    } catch (e) {
      _log('Error fetching settings: $e');
      return {};
    }
  }
}

// Helper for logging
void _log(String message) {
  // ignore: avoid_print
  print('[SupabaseService] $message');
}
