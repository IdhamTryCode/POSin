import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/receipt_data.dart';

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

  Future<PrintResult> printReceipt(ReceiptData data, {required String printerAddress}) async {
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
      final bytes = _buildReceiptBytes(data);

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

  /// Isi struk sebagai teks polos (format sama persis dengan yang dicetak).
  String generateReceiptText(ReceiptData data) {
    final buf = StringBuffer();
    for (final row in _layout(data)) {
      buf.writeln(row.center ? _center(row.text) : row.text);
    }
    return buf.toString();
  }

  String _center(String text, {int width = 32}) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return '${' ' * pad}$text';
  }

  /// Tata letak struk 58mm (32 kolom). Satu sumber untuk teks & ESC/POS.
  List<_Row> _layout(ReceiptData d) {
    final rows = <_Row>[];
    void add(String t, {bool center = false, bool bold = false, bool big = false}) =>
        rows.add(_Row(t, center: center, bold: bold, big: big));

    add('');
    add(d.storeName, center: true, bold: true);
    if (d.storeAddress.isNotEmpty) add(d.storeAddress, center: true);
    if (d.storePhone.isNotEmpty) add(d.storePhone, center: true);
    if (d.storeDescription.isNotEmpty) add(d.storeDescription, center: true);
    add('');
    add(_line());
    if (d.isVoid) {
      add('*** DIBATALKAN ***', center: true, bold: true);
      add('');
    }
    if ((d.dailyNumber ?? '').isNotEmpty) {
      add('NO. PESANAN', center: true);
      add('#${d.dailyNumber}', center: true, bold: true, big: true);
      add('');
    }
    add(_col2('No:', d.orderNumber));
    add(_col2('Tgl:', d.dateTime));
    add(_line());

    for (final item in d.items) {
      final name = item.name.length > 32 ? '${item.name.substring(0, 29)}...' : item.name;
      add(name, bold: true);
      if (item.variantLabel.isNotEmpty) add('  ${item.variantLabel}');
      if (item.note.isNotEmpty) add('  * ${item.note}');
      add(_col2('  ${item.qty}x${_price(item.price)}', _price(item.subtotal)));
    }

    add(_line());
    // Toko tanpa diskon & pajak: struk tetap bersih seperti biasa.
    if (d.hasAdjustments) {
      add(_col2('Subtotal', _price(d.subtotal)));
      if (d.discount > 0) add(_col2('Diskon', '-${_price(d.discount)}'));
      if (d.tax > 0) add(_col2(d.taxLabel, _price(d.tax)));
    }
    add(_col2('TOTAL', _price(d.total)), bold: true);
    if (d.paymentMethod == 'Tunai' && d.amountPaid != null) {
      add(_col2('Bayar', _price(d.amountPaid!)));
      add(_col2('Kembali', _price(d.change ?? 0)));
    }
    add(_line());
    add(d.paymentMethod, center: true);
    add('');
    add(d.footer, center: true);
    add('');
    add('');
    return rows;
  }

  /// Seluruh struk sebagai satu byte array ESC/POS.
  Uint8List _buildReceiptBytes(ReceiptData data) {
    final buf = <int>[0x1B, 0x40]; // init printer
    for (final row in _layout(data)) {
      buf.addAll(row.center ? [0x1B, 0x61, 0x01] : [0x1B, 0x61, 0x00]);
      if (row.bold) buf.addAll([0x1B, 0x45, 0x01]);
      if (row.big) buf.addAll([0x1D, 0x21, 0x11]); // lebar + tinggi ganda
      buf.addAll(row.text.codeUnits.map((c) => c > 0xFF ? 0x3F : c)); // non-latin -> '?'
      buf.add(0x0A);
      if (row.big) buf.addAll([0x1D, 0x21, 0x00]);
      if (row.bold) buf.addAll([0x1B, 0x45, 0x00]);
    }
    buf.addAll([0x0A, 0x0A]);
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

class _Row {
  final String text;
  final bool center;
  final bool bold;
  final bool big;
  const _Row(this.text, {this.center = false, this.bold = false, this.big = false});
}
