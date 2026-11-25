import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import '../device/device_settings.dart';
import 'sync_remote.dart';
import 'sync_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Engine: logika kirim/tarik, tanpa penjadwalan & tanpa Riverpod (mudah dites).
// ─────────────────────────────────────────────────────────────────────────────

class SyncRunResult {
  final int pushed;
  final int rejected;
  final int pulledChanges;
  const SyncRunResult({this.pushed = 0, this.rejected = 0, this.pulledChanges = 0});
}

class SyncEngine {
  final SyncStore store;
  final SyncRemote remote;

  static const pushBatchSize = 200;
  static const pullPageSize = 500;

  /// Baris yang berubah di server dalam rentang ini ditarik ulang setiap sync.
  /// Menangani transaksi server yang commit sedikit terlambat (updated_at-nya
  /// lebih kecil dari kursor). Aman karena penerapan baris bersifat idempotent.
  static const overlap = Duration(seconds: 10);

  SyncEngine(this.store, this.remote);

  /// Kirim antrean lalu tarik perubahan. Error jaringan dilempar ke pemanggil.
  Future<SyncRunResult> run() async {
    final push = await pushAll();
    final pulled = await pullAll();
    return SyncRunResult(pushed: push.$1, rejected: push.$2, pulledChanges: pulled);
  }

  Future<(int, int)> pushAll() async {
    var pushed = 0;
    var rejected = 0;
    var lastSeq = 0;
    while (true) {
      final batch = await store.nextBatch(limit: pushBatchSize, afterSeq: lastSeq);
      if (batch.isEmpty) break;
      lastSeq = batch.last.seq;
      try {
        await remote.push(batch.map((o) => o.toRpc()).toList());
        await store.ack(batch.map((o) => o.seq).toList());
        pushed += batch.length;
      } on SyncRejected {
        // Satu operasi buruk tidak boleh memblokir yang lain: kirim satu per satu.
        for (final op in batch) {
          try {
            await remote.push([op.toRpc()]);
            await store.ack([op.seq]);
            pushed++;
          } on SyncRejected catch (e) {
            await store.markRejected(op, e.message);
            rejected++;
            debugPrint('[sync] ditolak server: ${op.table}/${op.rowId}: $e');
          }
        }
      }
    }
    return (pushed, rejected);
  }

  Future<int> pullAll() async {
    var changed = 0;
    for (final table in SyncTables.all) {
      var cursor = await store.cursor(table);
      while (true) {
        final page = await remote.pull(table,
            since: cursor.since, afterId: cursor.afterId, limit: pullPageSize);
        changed += await store.applyPulled(table, page.rows);

        if (page.rows.length >= pullPageSize) {
          final last = page.rows.last;
          cursor = SyncCursor(last['updated_at'] as String,
              last[SyncTables.keyColumn(table)].toString());
          await store.saveCursor(table, cursor);
          continue;
        }

        // Halaman terakhir: simpan kursor, tapi jangan lebih maju dari
        // (waktu server - overlap).
        final safeEdge = page.serverTime.subtract(overlap);
        if (page.rows.isNotEmpty) {
          final last = page.rows.last;
          final lastTs = DateTime.parse(last['updated_at'] as String);
          cursor = lastTs.isBefore(safeEdge)
              ? SyncCursor(last['updated_at'] as String, last[SyncTables.keyColumn(table)].toString())
              : SyncCursor(safeEdge.toUtc().toIso8601String(), null);
          await store.saveCursor(table, cursor);
        }
        break;
      }
    }
    return changed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status untuk UI
// ─────────────────────────────────────────────────────────────────────────────

class SyncStatus {
  final bool syncing;
  final int pending;
  final int failed;
  final DateTime? lastSyncedAt;

  /// Error terakhir (null kalau sync terakhir berhasil).
  final String? lastError;

  const SyncStatus({
    this.syncing = false,
    this.pending = 0,
    this.failed = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  bool get isOffline => lastError != null;

  SyncStatus copyWith({
    bool? syncing,
    int? pending,
    int? failed,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncStatus(
        syncing: syncing ?? this.syncing,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

final syncStatusProvider = StateProvider<SyncStatus>((ref) => const SyncStatus());

/// Naik setiap kali data dari HP lain masuk ke SQLite. Provider data
/// (menu, kategori, pesanan, setting) me-watch ini untuk memuat ulang.
final syncRevisionProvider = StateProvider<int>((ref) => 0);

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref);
  ref.onDispose(controller.stop);
  return controller;
});

// ─────────────────────────────────────────────────────────────────────────────
// Controller: kapan sync dijalankan.
//   * segera setelah ada perubahan lokal (debounce)
//   * saat ada perubahan dari HP lain (Realtime)
//   * saat app kembali dibuka (resume) & berkala setiap 5 menit (cadangan)
//   * retry dengan backoff saat offline
// ─────────────────────────────────────────────────────────────────────────────

class SyncController with WidgetsBindingObserver {
  final Ref _ref;
  SyncController(this._ref);

  String? _uid;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _periodic;
  Timer? _retry;
  int _retryStep = 0;
  bool _running = false;
  bool _again = false;
  bool _observing = false;
  Completer<SyncRunResult?>? _inFlight;

  /// Jeda retry saat offline. Maks 30 detik supaya data cepat terkirim
  /// begitu internet kembali (tanpa membebani baterai/kuota).
  static const _retryDelays = [3, 5, 10, 20, 30];

  SupabaseClient get _client => Supabase.instance.client;

  Future<Database> _db() => DatabaseHelper.instance.database;

  void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;

    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _startPeriodic();
    _subscribeRealtime(uid);
    _registerDevice();
    refreshCounts();
    requestSync(immediate: true);
  }

  void stop() {
    _uid = null;
    _debounce?.cancel();
    _periodic?.cancel();
    _retry?.cancel();
    _retryStep = 0;
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  /// Cadangan saja — pemicu utama adalah Realtime & perubahan lokal.
  /// 5 menit menjaga pemakaian kuota Supabase tetap kecil.
  static const _periodicInterval = Duration(minutes: 5);

  void _startPeriodic() {
    _periodic?.cancel();
    _periodic = Timer.periodic(_periodicInterval, (_) {
      _registerDevice(); // perbarui jumlah HP (untuk prefix nomor antrean)
      requestSync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_uid == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startPeriodic();
        _registerDevice();
        requestSync(immediate: true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Di background: hemat baterai & kuota. Antrean tetap aman di SQLite.
        _periodic?.cancel();
      default:
        break;
    }
  }

  /// Panggil setelah setiap perubahan lokal (sudah masuk antrean).
  void requestSync({bool immediate = false}) {
    if (_uid == null) return;
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 400), () {
      syncNow();
    });
    refreshCounts();
  }

  /// Jalankan sync sekarang dan tunggu hasilnya (dipakai tombol "Sinkronkan").
  Future<SyncRunResult?> syncNow() async {
    if (_uid == null) return null;
    if (_running) {
      _again = true;
      return _inFlight?.future;
    }
    _running = true;
    _inFlight = Completer<SyncRunResult?>();
    _setStatus((s) => s.copyWith(syncing: true));

    SyncRunResult? result;
    try {
      do {
        _again = false;
        final uidAtStart = _uid;
        final engine = SyncEngine(SyncStore(await _db()), SupabaseSyncRemote(_client));
        result = await engine.run();
        if (_uid != uidAtStart) break; // ganti akun di tengah jalan

        if (result.pulledChanges > 0) {
          _ref.read(syncRevisionProvider.notifier).state++;
        }
        if (result.pushed > 0) _broadcastChanged();
      } while (_again);

      _retryStep = 0;
      _retry?.cancel();
      _setStatus((s) => s.copyWith(lastSyncedAt: DateTime.now(), clearError: true));
    } catch (e) {
      debugPrint('[sync] gagal (akan dicoba lagi): $e');
      _setStatus((s) => s.copyWith(lastError: _friendlyError(e)));
      _scheduleRetry();
    } finally {
      _running = false;
      _setStatus((s) => s.copyWith(syncing: false));
      await refreshCounts();
      _inFlight?.complete(result);
      _inFlight = null;
    }
    return result;
  }

  Future<void> refreshCounts() async {
    if (_uid == null) return;
    try {
      final store = SyncStore(await _db());
      final pending = await store.pendingCount();
      final failed = await store.failedCount();
      _setStatus((s) => s.copyWith(pending: pending, failed: failed));
    } catch (_) {}
  }

  Future<void> retryFailed() async {
    final store = SyncStore(await _db());
    await store.retryFailed();
    requestSync(immediate: true);
  }

  void _scheduleRetry() {
    if (_uid == null) return;
    _retry?.cancel();
    final secs = _retryDelays[_retryStep.clamp(0, _retryDelays.length - 1)];
    _retryStep++;
    _retry = Timer(Duration(seconds: secs), () => syncNow());
  }

  void _setStatus(SyncStatus Function(SyncStatus) update) {
    final notifier = _ref.read(syncStatusProvider.notifier);
    notifier.state = update(notifier.state);
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') ||
        s.contains('TimeoutException') || s.contains('Failed host lookup')) {
      return 'Tidak ada koneksi internet';
    }
    return 'Gagal sinkron: ${s.length > 120 ? s.substring(0, 120) : s}';
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime(String uid) {
    final myDevice = _ref.read(deviceSettingsProvider).deviceId;
    var channel = _client.channel('posin-sync-$uid');

    // Perubahan dari APK versi lama (tidak mengirim broadcast) & dari admin.
    for (final table in SyncTables.all) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) => requestSync(),
      );
    }

    // "Colekan" dari HP lain (app versi baru) — termasuk void & hapus.
    channel = channel.onBroadcast(
      event: 'changed',
      callback: (payload) {
        if (payload['device'] != myDevice) requestSync();
      },
    );

    _channel = channel.subscribe((status, error) {
      // Tersambung (lagi) setelah putus → kejar perubahan yang terlewat.
      if (status == RealtimeSubscribeStatus.subscribed) requestSync();
    });
  }

  void _broadcastChanged() {
    final ch = _channel;
    if (ch == null) return;
    ch
        .sendBroadcastMessage(
          event: 'changed',
          payload: {'device': _ref.read(deviceSettingsProvider).deviceId},
        )
        .ignore();
  }

  // ── Registrasi HP (kode A/B/C untuk nomor antrean) ────────────────────────

  Future<void> _registerDevice() async {
    final uid = _uid;
    if (uid == null) return;
    final device = _ref.read(deviceSettingsProvider);
    try {
      final reg = await SupabaseSyncRemote(_client).registerDevice(
        device.deviceId,
        device.cashierName.isEmpty ? null : device.cashierName,
      );
      if (_uid != uid) return;
      await _ref.read(deviceSettingsProvider.notifier).setRegistration(reg.code, reg.deviceCount);
    } catch (e) {
      debugPrint('[sync] registrasi HP tertunda: $e');
    }
  }
}
