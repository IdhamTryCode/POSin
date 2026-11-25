import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Satu-satunya sumber harga & kontak langganan POSin.
/// Ubah di sini saja — semua layar (Upgrade, Pengaturan) membaca dari sini.
/// Admin-panel punya konstanta yang sama di `admin-panel/src/lib/pricing.js`.
class PlanConfig {
  PlanConfig._();

  /// Harga Premium per bulan (Rupiah).
  static const int monthlyPrice = 10000;

  /// Lama trial gratis untuk user baru (diatur trigger `handle_new_user` di DB).
  static const int trialMonths = 3;

  static const String waNumber = '6281329064923';

  /// "Rp 10.000"
  static String get monthlyPriceLabel =>
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
          .format(monthlyPrice);

  static String waMessage(String? email) {
    final account = (email == null || email.isEmpty) ? '' : '\nEmail akun: $email';
    return 'Halo, saya mau berlangganan POSin Premium '
        '($monthlyPriceLabel/bulan). Mohon informasi pembayarannya. 🙏$account';
  }

  static Future<void> openUpgradeWhatsApp(BuildContext context, {String? email}) async {
    final uri = Uri.parse(
      'https://wa.me/$waNumber?text=${Uri.encodeComponent(waMessage(email))}',
    );
    // Langsung coba buka (canLaunchUrl bisa salah "false" di Android 11+).
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka WhatsApp')),
      );
    }
  }
}
