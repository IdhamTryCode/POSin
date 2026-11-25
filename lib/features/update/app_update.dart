import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/device/device_settings.dart';

/// Info versi dari tabel `app_config` (diatur dari admin-panel).
class AppUpdateInfo {
  final int currentCode;
  final String currentName;
  final int latestCode;
  final String latestName;
  final int minCode;
  final String releaseNotes;
  final String packageName;

  const AppUpdateInfo({
    required this.currentCode,
    required this.currentName,
    required this.latestCode,
    required this.latestName,
    required this.minCode,
    required this.releaseNotes,
    required this.packageName,
  });

  /// Versi ini sudah tidak didukung → wajib update.
  bool get isRequired => currentCode < minCode;

  /// Ada versi lebih baru di Play Store (opsional).
  bool get isAvailable => currentCode < latestCode;
}

/// Cek sekali saat app dibuka, dan lagi saat app kembali dibuka kalau sudah
/// lewat 6 jam. Gagal (offline) = diam saja, tidak mengganggu kasir.
final appUpdateProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  final checkedAt = DateTime.now();
  final listener = AppLifecycleListener(onResume: () {
    if (DateTime.now().difference(checkedAt) > const Duration(hours: 6)) ref.invalidateSelf();
  });
  ref.onDispose(listener.dispose);

  try {
    final info = await PackageInfo.fromPlatform();
    final row = await Supabase.instance.client
        .from('app_config')
        .select()
        .eq('id', 1)
        .maybeSingle()
        .timeout(const Duration(seconds: 6));
    if (row == null) return null;
    return AppUpdateInfo(
      currentCode: int.tryParse(info.buildNumber) ?? 0,
      currentName: info.version,
      latestCode: (row['latest_version_code'] as num).toInt(),
      latestName: (row['latest_version_name'] as String?) ?? '',
      minCode: (row['min_version_code'] as num).toInt(),
      releaseNotes: (row['release_notes'] as String?) ?? '',
      packageName: info.packageName,
    );
  } catch (e) {
    debugPrint('[update] cek versi gagal: $e');
    return null;
  }
});

Future<void> openPlayStore(BuildContext context, String packageName) async {
  final market = Uri.parse('market://details?id=$packageName');
  final web = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
  for (final uri in [market, web]) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak bisa membuka Play Store')),
    );
  }
}

/// Popup "versi baru tersedia" — muncul sekali per versi (bisa ditunda).
Future<void> maybeShowUpdateDialog(BuildContext context, WidgetRef ref, AppUpdateInfo info) async {
  if (!info.isAvailable || info.isRequired) return;
  final prefs = ref.read(sharedPrefsProvider);
  const key = 'update_dismissed_code';
  if (prefs.getInt(key) == info.latestCode) return;
  await prefs.setInt(key, info.latestCode);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 36),
      title: Text(info.latestName.isEmpty ? 'Versi baru tersedia' : 'POSin ${info.latestName} tersedia'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kamu memakai versi ${info.currentName}. Update untuk mendapatkan perbaikan & fitur terbaru.'),
        if (info.releaseNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Yang baru:', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(info.releaseNotes, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nanti')),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            openPlayStore(context, info.packageName);
          },
          child: const Text('Update Sekarang'),
        ),
      ],
    ),
  );
}

/// Layar penuh untuk versi yang sudah tidak didukung.
class ForceUpdateScreen extends StatelessWidget {
  final AppUpdateInfo info;
  const ForceUpdateScreen({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_rounded, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('Update Diperlukan',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Versi ${info.currentName} sudah tidak didukung. Update POSin ke versi terbaru '
              'untuk melanjutkan. Data kamu tetap aman.',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(info.releaseNotes,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => openPlayStore(context, info.packageName),
                icon: const Icon(Icons.shop_rounded),
                label: const Text('Update di Play Store'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
