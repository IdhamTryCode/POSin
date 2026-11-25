import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_model.dart';

/// Hasil cek langganan dari server (beserta jam server saat itu).
class PlanSnapshot {
  final PlanModel plan;
  final DateTime serverNow;
  final DateTime deviceNowAtFetch;

  const PlanSnapshot({
    required this.plan,
    required this.serverNow,
    required this.deviceNowAtFetch,
  });

  Map<String, dynamic> toJson() => {
        'plan_type': plan.isPremium ? 'premium' : 'free',
        'expires_at': plan.trialExpiresAt.toUtc().toIso8601String(),
        'server_now': serverNow.toUtc().toIso8601String(),
        'device_now': deviceNowAtFetch.toUtc().toIso8601String(),
      };

  static PlanSnapshot fromJson(String userId, Map<String, dynamic> j) => PlanSnapshot(
        plan: PlanModel(
          userId: userId,
          planType: j['plan_type'] == 'premium' ? PlanType.premium : PlanType.free,
          trialExpiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
        ),
        serverNow: DateTime.parse(j['server_now'] as String),
        deviceNowAtFetch: DateTime.parse(j['device_now'] as String),
      );
}

class PlanService {
  final SupabaseClient _client;
  final SharedPreferences _prefs;

  /// Jangan biarkan kasir menunggu lama di splash karena sinyal lemah.
  static const timeout = Duration(seconds: 8);

  PlanService(this._client, this._prefs);

  /// Profil (termasuk trial 3 bulan) dibuat oleh trigger `handle_new_user` di
  /// database saat user mendaftar. Client hanya bisa MEMBACA statusnya.
  Future<PlanSnapshot> fetchFromServer(String userId) async {
    final res = await _client.rpc('get_my_plan').timeout(timeout);
    if (res == null) {
      throw StateError('Profil langganan tidak ditemukan');
    }
    final map = Map<String, dynamic>.from(res as Map);
    final snapshot = PlanSnapshot(
      plan: PlanModel(
        userId: userId,
        planType: map['plan_type'] == 'premium' ? PlanType.premium : PlanType.free,
        trialExpiresAt: DateTime.parse(map['expires_at'] as String).toLocal(),
      ),
      serverNow: DateTime.parse(map['server_now'] as String),
      deviceNowAtFetch: DateTime.now(),
    );
    await _prefs.setString(_key(userId), jsonEncode(snapshot.toJson()));
    return snapshot;
  }

  PlanSnapshot? cached(String userId) {
    final raw = _prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      return PlanSnapshot.fromJson(userId, jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _key(String userId) => 'plan_cache_$userId';
}
