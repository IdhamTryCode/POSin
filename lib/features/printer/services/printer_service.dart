import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class BluetoothDeviceInfo {
  final String name;
  final String address;
  const BluetoothDeviceInfo({required this.name, required this.address});
}

class PrintResult {
  final bool success;
  final String? error;
  const PrintResult.ok() : success = true, error = null;
  const PrintResult.fail(this.error) : success = false;
}

class PrinterService {
  static final PrinterService instance = PrinterService._();
  PrinterService._();

  final _printer = BlueThermalPrinter.instance;

  Future<List<BluetoothDeviceInfo>> getBondedDevices() async {
    try {
      final devices = await _printer.getBondedDevices();
      return devices
          .where((d) => d.name != null && d.address != null)
          .map((d) => BluetoothDeviceInfo(name: d.name!, address: d.address!))
          .toList();
    } catch (e) {
      throw PrinterException('Gagal mengambil daftar perangkat Bluetooth: $e');
    }
  }

  Future<PrintResult> printReceipt({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String storeDescription = '',
    required String orderNumber,
    required String dateTime,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
    double? amountPaid,
    double? change,
    required String footer,
    required String printerAddress,
  }) async {
    // Pastikan tidak ada koneksi aktif sebelumnya
    try {
      final isConnected = await _printer.isConnected;
      if (isConnected == true) await _printer.disconnect();
    } catch (_) {}

    try {
      final devices = await _printer.getBondedDevices();

      if (devices.isEmpty) {
        return const PrintResult.fail('Tidak ada perangkat Bluetooth yang ter-pair. Silakan pair printer di Pengaturan Bluetooth HP terlebih dahulu.');
      }

      final device = devices.firstWhere(
        (d) => d.address == printerAddress,
        orElse: () => throw PrinterException('Printer tidak ditemukan dalam daftar paired devices. Coba pair ulang printer di Pengaturan Bluetooth HP.'),
      );

      await _printer.connect(device).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw PrinterException('Koneksi timeout. Pastikan printer menyala dan dalam jangkauan Bluetooth.'),
      );

      await Future.delayed(const Duration(milliseconds: 600));

      final isConnected = await _printer.isConnected;
      if (isConnected != true) {
        return const PrintResult.fail('Gagal terhubung ke printer. Pastikan printer menyala dan tidak sedang digunakan.');
      }

      // ── Print header ───────────────────────────────────────────
      await _printer.printNewLine();
      await _printer.printCustom(storeName, 1, 1); // bold, center
      if (storeAddress.isNotEmpty) await _printer.printCustom(storeAddress, 0, 1);
      if (storePhone.isNotEmpty) await _printer.printCustom(storePhone, 0, 1);
      if (storeDescription.isNotEmpty) await _printer.printCustom(storeDescription, 0, 1);
      await _printer.printNewLine();
      await _printer.printCustom(_line(), 0, 1);
      await _printer.printCustom(_col2('No:', orderNumber), 0, 0);
      await _printer.printCustom(_col2('Tgl:', dateTime), 0, 0);
      await _printer.printCustom(_line(), 0, 1);

      // ── Items ──────────────────────────────────────────────────
      for (final item in items) {
        final name = item['name'] as String;
        final displayName = name.length > 32 ? '${name.substring(0, 29)}...' : name;
        await _printer.printCustom(displayName, 0, 0);
        final variantLabel = item['variant_label'] as String? ?? '';
        if (variantLabel.isNotEmpty) await _printer.printCustom('  $variantLabel', 0, 0);
        final qtyPrice = '  ${item['qty']}x${_price(item['price'] as double)}';
        await _printer.printCustom(_col2(qtyPrice, _price(item['subtotal'] as double)), 0, 0);
      }

      // ── Total ──────────────────────────────────────────────────
      await _printer.printCustom(_line(), 0, 1);
      await _printer.printCustom(_col2('TOTAL', _price(total)), 1, 0); // bold

      if (paymentMethod == 'Tunai' && amountPaid != null) {
        await _printer.printCustom(_col2('Bayar', _price(amountPaid)), 0, 0);
        await _printer.printCustom(_col2('Kembali', _price(change ?? 0)), 0, 0);
      }

      // ── Footer ─────────────────────────────────────────────────
      await _printer.printCustom(_line(), 0, 1);
      await _printer.printCustom(paymentMethod, 0, 1);
      await _printer.printNewLine();
      await _printer.printCustom(footer, 0, 1);
      await _printer.printNewLine();
      await _printer.printNewLine();
      await _printer.printNewLine();

      await Future.delayed(const Duration(milliseconds: 500));
      await _printer.disconnect();
      return const PrintResult.ok();
    } on PrinterException catch (e) {
      await _safeDisconnect();
      return PrintResult.fail(e.message);
    } catch (e) {
      await _safeDisconnect();
      // Terjemahkan error umum jadi pesan yang dimengerti
      final msg = _friendlyError(e.toString());
      return PrintResult.fail(msg);
    }
  }

  /// Generates the receipt as plain text (same format as printed).
  /// Use this to preview without a physical printer.
  String generateReceiptText({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String storeDescription = '',
    required String orderNumber,
    required String dateTime,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
    double? amountPaid,
    double? change,
    required String footer,
  }) {
    final buf = StringBuffer();
    buf.writeln();
    buf.writeln(_center(storeName));
    if (storeAddress.isNotEmpty) buf.writeln(_center(storeAddress));
    if (storePhone.isNotEmpty) buf.writeln(_center(storePhone));
    if (storeDescription.isNotEmpty) buf.writeln(_center(storeDescription));
    buf.writeln();
    buf.writeln(_line());
    buf.writeln(_col2('No:', orderNumber));
    buf.writeln(_col2('Tgl:', dateTime));
    buf.writeln(_line());
    for (final item in items) {
      final name = item['name'] as String;
      final displayName = name.length > 32 ? '${name.substring(0, 29)}...' : name;
      buf.writeln(displayName);
      final variantLabel = item['variant_label'] as String? ?? '';
      if (variantLabel.isNotEmpty) buf.writeln('  $variantLabel');
      final qtyPrice = '  ${item['qty']}x${_price(item['price'] as double)}';
      buf.writeln(_col2(qtyPrice, _price(item['subtotal'] as double)));
    }
    buf.writeln(_line());
    buf.writeln(_col2('TOTAL', _price(total)));
    if (paymentMethod == 'Tunai' && amountPaid != null) {
      buf.writeln(_col2('Bayar', _price(amountPaid)));
      buf.writeln(_col2('Kembali', _price(change ?? 0)));
    }
    buf.writeln(_line());
    buf.writeln(_center(paymentMethod));
    buf.writeln();
    buf.writeln(_center(footer));
    buf.writeln();
    buf.writeln();
    return buf.toString();
  }

  String _center(String text, {int width = 32}) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return '${' ' * pad}$text';
  }

  Future<void> _safeDisconnect() async {
    try { await _printer.disconnect(); } catch (_) {}
  }

  String _friendlyError(String raw) {
    if (raw.contains('TimeoutException') || raw.contains('timeout')) {
      return 'Koneksi timeout. Pastikan printer menyala dan dekat dengan HP.';
    }
    if (raw.contains('BLUETOOTH') || raw.contains('permission')) {
      return 'Izin Bluetooth belum diberikan. Buka Pengaturan → Izin Aplikasi → POSin → aktifkan Bluetooth.';
    }
    if (raw.contains('connect') || raw.contains('socket')) {
      return 'Gagal terhubung ke printer. Coba matikan dan hidupkan kembali printer, lalu coba lagi.';
    }
    if (raw.contains('read failed') || raw.contains('broken pipe')) {
      return 'Koneksi terputus saat mencetak. Pastikan printer tidak dimatikan saat proses print.';
    }
    return 'Gagal mencetak: $raw';
  }

  // 32 karakter untuk kertas 58mm
  String _line() => '--------------------------------';

  String _col2(String left, String right, {int width = 32}) {
    final spaces = width - left.length - right.length;
    if (spaces <= 0) return '$left $right';
    return '$left${' ' * spaces}$right';
  }

  String _price(double price) {
    return 'Rp${price.toInt().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => message;
}
