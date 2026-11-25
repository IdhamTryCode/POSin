import 'package:supabase_flutter/supabase_flutter.dart';

class PullPage {
  final List<Map<String, dynamic>> rows;
  final DateTime serverTime;
  const PullPage(this.rows, this.serverTime);
}

class DeviceRegistration {
  final String code;
  final int deviceCount;
  const DeviceRegistration(this.code, this.deviceCount);
}

/// Server menolak operasi (data tidak valid, RLS, dll.) — BUKAN masalah jaringan.
/// Operasi seperti ini tidak akan berhasil walau diulang terus.
class SyncRejected implements Exception {
  final String message;
  const SyncRejected(this.message);
  @override
  String toString() => message;
}

/// Kontrak ke server. Dipisah supaya SyncEngine bisa dites tanpa internet.
abstract class SyncRemote {
  Future<void> push(List<Map<String, dynamic>> ops);
  Future<PullPage> pull(String table, {String? since, String? afterId, int limit});
  Future<DeviceRegistration> registerDevice(String deviceId, String? name);
}

class SupabaseSyncRemote implements SyncRemote {
  final SupabaseClient client;
  static const _timeout = Duration(seconds: 20);

  SupabaseSyncRemote(this.client);

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn().timeout(_timeout);
    } on PostgrestException catch (e) {
      // Kode error Postgres (5 karakter) = server menolak datanya, KECUALI kelas
      // yang sifatnya sementara (koneksi, deadlock, timeout, kehabisan resource).
      // Kode PostgREST (PGRSTxxx, mis. JWT kedaluwarsa) dianggap sementara.
      final code = e.code ?? '';
      const transientClasses = ['08', '40', '53', '57'];
      final isPgCode = RegExp(r'^[0-9A-Z]{5}$').hasMatch(code);
      if (isPgCode && !transientClasses.contains(code.substring(0, 2))) {
        throw SyncRejected('${e.message} ($code)');
      }
      rethrow;
    }
  }

  @override
  Future<void> push(List<Map<String, dynamic>> ops) =>
      _call(() => client.rpc('push_changes', params: {'p_ops': ops}));

  @override
  Future<PullPage> pull(String table, {String? since, String? afterId, int limit = 500}) async {
    final res = await _call(() => client.rpc('pull_changes', params: {
          'p_table': table,
          'p_since': since,
          'p_after_id': afterId,
          'p_limit': limit,
        }));
    final map = Map<String, dynamic>.from(res as Map);
    final rows = (map['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    return PullPage(rows, DateTime.parse(map['server_time'] as String));
  }

  @override
  Future<DeviceRegistration> registerDevice(String deviceId, String? name) async {
    final res = await _call(() => client.rpc('register_device', params: {
          'p_device_id': deviceId,
          'p_name': name,
        }));
    final map = Map<String, dynamic>.from(res as Map);
    return DeviceRegistration(map['code'] as String, (map['device_count'] as num).toInt());
  }
}
