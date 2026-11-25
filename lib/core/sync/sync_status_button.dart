import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import 'sync_engine.dart';

/// Ikon awan di app bar: hijau = tersinkron, angka = menunggu dikirim,
/// coret = offline. Tap untuk detail & sinkron manual.
class SyncStatusButton extends ConsumerWidget {
  final Color color;
  const SyncStatusButton({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);

    final IconData icon;
    final String tooltip;
    if (s.syncing) {
      icon = Icons.cloud_sync_outlined;
      tooltip = 'Menyinkronkan...';
    } else if (s.failed > 0) {
      icon = Icons.cloud_off_outlined;
      tooltip = '${s.failed} perubahan gagal dikirim';
    } else if (s.isOffline) {
      icon = Icons.cloud_off_outlined;
      tooltip = s.pending > 0 ? 'Offline • ${s.pending} menunggu' : 'Offline';
    } else if (s.pending > 0) {
      icon = Icons.cloud_upload_outlined;
      tooltip = '${s.pending} perubahan menunggu dikirim';
    } else {
      icon = Icons.cloud_done_outlined;
      tooltip = 'Semua data tersinkron';
    }

    final badge = s.failed > 0 ? s.failed : s.pending;
    return IconButton(
      tooltip: tooltip,
      onPressed: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _SyncSheet(),
      ),
      icon: Badge(
        isLabelVisible: badge > 0,
        backgroundColor: s.failed > 0 ? AppColors.error : AppColors.warning,
        label: Text('$badge'),
        child: Icon(icon, color: color),
      ),
    );
  }
}

class _SyncSheet extends ConsumerWidget {
  const _SyncSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    final controller = ref.read(syncControllerProvider);
    final time = s.lastSyncedAt == null
        ? 'belum pernah'
        : DateFormat('HH:mm:ss', 'id_ID').format(s.lastSyncedAt!);

    final (String title, String subtitle, Color color, IconData icon) = switch (s) {
      _ when s.failed > 0 => (
          '${s.failed} perubahan ditolak server',
          'Data tetap aman di HP ini. Coba kirim ulang; kalau tetap gagal, hubungi admin.',
          AppColors.error,
          Icons.error_outline,
        ),
      _ when s.isOffline => (
          s.pending > 0 ? 'Offline • ${s.pending} perubahan menunggu' : 'Sedang offline',
          'Tetap bisa jualan seperti biasa. Data akan terkirim otomatis saat internet kembali.',
          AppColors.warning,
          Icons.wifi_off_rounded,
        ),
      _ when s.pending > 0 => (
          '${s.pending} perubahan sedang dikirim',
          'Pesanan sudah tersimpan di HP ini.',
          AppColors.warning,
          Icons.cloud_upload_outlined,
        ),
      _ => (
          'Semua data tersinkron',
          'Pesanan & menu di semua HP sudah sama.',
          AppColors.success,
          Icons.cloud_done_outlined,
        ),
    };

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Terakhir sinkron: $time', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (s.lastError != null) ...[
              const SizedBox(height: 4),
              Text(s.lastError!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: s.syncing
                    ? null
                    : () => s.failed > 0 ? controller.retryFailed() : controller.syncNow(),
                icon: s.syncing
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: Text(s.syncing
                    ? 'Menyinkronkan...'
                    : (s.failed > 0 ? 'Kirim Ulang' : 'Sinkronkan Sekarang')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
