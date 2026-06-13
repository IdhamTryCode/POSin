import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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

  static const MethodChannel _channel = MethodChannel('posin/printer');

  /// Android 12+ butuh izin runtime ini. Di Android 11 ke bawah otomatis granted
  /// (permission_handler langsung mengembalikan granted tanpa dialog).
  Future<void> _ensurePermissions() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
  }

  Future<List<BluetoothDeviceInfo>> getBondedDevices() async {
    try {
      await _ensurePermissions();
      final res = await _channel.invokeMethod<List<dynamic>>('getBondedDevices');
      return (res ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) =>
              (m['name'] as String?)?.isNotEmpty == true &&
              (m['address'] as String?)?.isNotEmpty == true)
          .map((m) => BluetoothDeviceInfo(
                name: m['name'] as String,
                address: m['address'] as String,
              ))
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
    String? dailyNumber,
    required String dateTime,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
    double? amountPaid,
    double? change,
    required String footer,
    required String printerAddress,
  }) async {
    await _ensurePermissions();

    // Pastikan tidak ada koneksi aktif sebelumnya
    await _safeDisconnect();

    try {
      // Buka koneksi lewat native: secure → insecure → reflection channel-1.
      final connectRes = await _channel.invokeMethod<dynamic>(
        'connect',
        {'address': printerAddress},
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => {
          'connected': false,
          'error':
              'Koneksi timeout. Pastikan printer menyala dan dalam jangkauan Bluetooth.',
        },
      );
      final cm = Map<String, dynamic>.from(connectRes as Map? ?? {});
      if (cm['connected'] != true) {
        await _safeDisconnect();
        return PrintResult.fail((cm['error'] as String?) ??
            'Gagal terhubung ke printer. Pastikan printer menyala dan tidak sedang digunakan.');
      }

      // Bangun seluruh receipt sebagai satu byte array lalu kirim sekaligus.
      // Ini jauh lebih reliable daripada print berkali-kali karena tidak ada
      // gap antar perintah yang bisa menyebabkan koneksi putus.
      final bytes = _buildReceiptBytes(
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        storeDescription: storeDescription,
        orderNumber: orderNumber,
        dailyNumber: dailyNumber,
        dateTime: dateTime,
        items: items,
        total: total,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
        change: change,
        footer: footer,
      );

      final writeRes =
          await _channel.invokeMethod<dynamic>('writeBytes', {'bytes': bytes});
      final wm = Map<String, dynamic>.from(writeRes as Map? ?? {});

      // tunggu sampai semua byte ter-flush sebelum disconnect
      await Future.delayed(const Duration(milliseconds: 1500));
      await _safeDisconnect();

      if (wm['ok'] != true) {
        return PrintResult.fail(
            _friendlyError((wm['error'] as String?) ?? 'Gagal mencetak'));
      }
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
    String? dailyNumber,
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
    if (dailyNumber != null && dailyNumber.isNotEmpty) {
      buf.writeln(_center('NO. PESANAN'));
      buf.writeln(_center('#$dailyNumber'));
      buf.writeln();
    }
    buf.writeln(_col2('No:', orderNumber));
    buf.writeln(_col2('Tgl:', dateTime));
    buf.writeln(_line());
    for (final item in items) {
      final name = item['name'] as String;
      final displayName = name.length > 32 ? '${name.substring(0, 29)}...' : name;
      buf.writeln(displayName);
      final variantLabel = item['variant_label'] as String? ?? '';
      if (variantLabel.isNotEmpty) buf.writeln('  $variantLabel');
      final note = item['note'] as String? ?? '';
      if (note.isNotEmpty) buf.writeln('  * $note');
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

  /// Builds the entire receipt as a single ESC/POS byte array.
  Uint8List _buildReceiptBytes({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String storeDescription,
    required String orderNumber,
    String? dailyNumber,
    required String dateTime,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
    double? amountPaid,
    double? change,
    required String footer,
  }) {
    final buf = <int>[];

    // ESC/POS helpers
    void esc(List<int> cmd) => buf.addAll(cmd);
    void nl() => buf.add(0x0A);
    void txt(String s) => buf.addAll(s.codeUnits);
    void line(String s) { txt(s); nl(); }
    void center() => esc([0x1B, 0x61, 0x01]);
    void left() => esc([0x1B, 0x61, 0x00]);
    void boldOn() => esc([0x1B, 0x45, 0x01]);
    void boldOff() => esc([0x1B, 0x45, 0x00]);

    // Initialize printer
    esc([0x1B, 0x40]);

    // ── Header ────────────────────────────────────────────────
    nl();
    center(); boldOn(); line(storeName); boldOff();
    if (storeAddress.isNotEmpty) { center(); line(storeAddress); }
    if (storePhone.isNotEmpty)   { center(); line(storePhone); }
    if (storeDescription.isNotEmpty) { center(); line(storeDescription); }
    nl();
    left(); line(_line());
    if (dailyNumber != null && dailyNumber.isNotEmpty) {
      center(); line('NO. PESANAN');
      // Double size for the daily number
      esc([0x1D, 0x21, 0x11]); // GS ! n — double width + height
      center(); boldOn(); line('#$dailyNumber'); boldOff();
      esc([0x1D, 0x21, 0x00]); // reset size
      left(); nl();
    }
    line(_col2('No:', orderNumber));
    line(_col2('Tgl:', dateTime));
    line(_line());

    // ── Items ─────────────────────────────────────────────────
    for (final item in items) {
      final name = item['name'] as String;
      final displayName = name.length > 32 ? '${name.substring(0, 29)}...' : name;
      boldOn(); line(displayName); boldOff();
      final variantLabel = item['variant_label'] as String? ?? '';
      if (variantLabel.isNotEmpty) line('  $variantLabel');
      final note = item['note'] as String? ?? '';
      if (note.isNotEmpty) line('  * $note');
      final qtyPrice = '  ${item['qty']}x${_price(item['price'] as double)}';
      line(_col2(qtyPrice, _price(item['subtotal'] as double)));
    }

    // ── Total ─────────────────────────────────────────────────
    line(_line());
    boldOn(); line(_col2('TOTAL', _price(total))); boldOff();
    if (paymentMethod == 'Tunai' && amountPaid != null) {
      line(_col2('Bayar', _price(amountPaid)));
      line(_col2('Kembali', _price(change ?? 0)));
    }

    // ── Footer ────────────────────────────────────────────────
    line(_line());
    center(); line(paymentMethod);
    nl();
    line(footer);
    nl(); nl(); nl();

    return Uint8List.fromList(buf);
  }

  Future<void> _safeDisconnect() async {
    try { await _channel.invokeMethod('disconnect'); } catch (_) {}
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
