import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/categories/providers/category_provider.dart';
import '../../features/orders/providers/order_provider.dart';
import '../../features/products/providers/product_provider.dart';
import '../../features/products/providers/variant_provider.dart';
import '../../features/settings/providers/settings_provider.dart';

final appSyncServiceProvider = Provider<AppSyncService>(
  (ref) => AppSyncService(ref),
);

class AppSyncService {
  final Ref _ref;
  bool _isSyncing = false;

  AppSyncService(this._ref);

  Future<void> syncAllFromCloud() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await Future.wait([
        _ref.read(categoryProvider.notifier).syncFromCloud(),
        _ref.read(productProvider.notifier).syncFromCloud(),
        _ref.read(orderProvider.notifier).syncFromCloud(),
        _ref.read(settingsProvider.notifier).syncFromCloud(),
        _ref.read(variantSyncProvider).syncFromCloud(),
      ]);
    } catch (e) {
      debugPrint('Warning: full cloud sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
