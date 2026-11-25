import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Upload file ke Supabase Storage. Sinkronisasi data ada di core/sync/.
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
          .upload(path, file, fileOptions: FileOptions(upsert: true))
          .timeout(const Duration(seconds: 30));
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
          .upload(path, file, fileOptions: FileOptions(upsert: true))
          .timeout(const Duration(seconds: 30));
      return _client.storage.from('store-assets').getPublicUrl(path);
    } catch (e) {
      _log('Error uploading store logo: $e');
      return null;
    }
  }

}

// Helper for logging
void _log(String message) {
  // ignore: avoid_print
  print('[SupabaseService] $message');
}
