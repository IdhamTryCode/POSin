import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/device/device_settings.dart';
import '../models/plan_model.dart';
import '../services/plan_service.dart';

final planServiceProvider = Provider<PlanService>(
  (ref) => PlanService(Supabase.instance.client, ref.watch(sharedPrefsProvider)),
);

final planProvider =
    AsyncNotifierProvider.family<PlanNotifier, PlanStatus, String>(PlanNotifier.new);

/// Status langganan per user.
///
/// * Ada cache → app LANGSUNG terbuka (kasir tidak menunggu internet), lalu
///   diverifikasi ke server di background.
/// * Tidak ada cache (login pertama) → tunggu server maks. 8 detik.
/// * Dicek ulang: saat app dibuka lagi, tiap 30 menit, dan status dihitung
///   ulang tiap menit (kunci langsung aktif begitu masa aktif lewat).
class PlanNotifier extends FamilyAsyncNotifier<PlanStatus, String> {
  PlanSnapshot? _snapshot;
  bool _fromCache = true;
  DateTime? _lastServerCheck;

  static const _serverRecheck = Duration(minutes: 30);

  PlanService get _service => ref.read(planServiceProvider);

  @override
  Future<PlanStatus> build(String userId) async {
    final ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    final lifecycle = AppLifecycleListener(onResume: () => refresh());
    ref.onDispose(() {
      ticker.cancel();
      lifecycle.dispose();
    });

    final cached = _service.cached(userId);
    if (cached != null) {
      _snapshot = cached;
      _fromCache = true;
      Future.microtask(refresh); // verifikasi di background
      return _evaluate();
    }

    _snapshot = await _service.fetchFromServer(userId);
    _fromCache = false;
    _lastServerCheck = DateTime.now();
    return _evaluate();
  }

  PlanStatus _evaluate() {
    final s = _snapshot!;
    return evaluatePlan(
      plan: s.plan,
      serverNow: s.serverNow,
      deviceNowAtFetch: s.deviceNowAtFetch,
      deviceNow: DateTime.now(),
      fromCache: _fromCache,
    );
  }

  void _tick() {
    if (_snapshot == null) return;
    final next = _evaluate();
    final current = state.valueOrNull;
    if (current == null || current.isActive != next.isActive || current.daysLeft != next.daysLeft) {
      state = AsyncData(next);
    }
    final last = _lastServerCheck;
    if (last == null || DateTime.now().difference(last) > _serverRecheck) {
      refresh();
    }
  }

  /// Cek ke server. Kalau gagal (offline), status dari cache tetap dipakai dan
  /// fungsi ini mengembalikan null.
  Future<PlanStatus?> refresh() async {
    try {
      _snapshot = await _service.fetchFromServer(arg);
      _fromCache = false;
      _lastServerCheck = DateTime.now();
      final status = _evaluate();
      state = AsyncData(status);
      return status;
    } catch (e) {
      debugPrint('[plan] cek langganan gagal, pakai cache: $e');
      _lastServerCheck = DateTime.now(); // jangan spam saat offline
      return null;
    }
  }
}
