import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Di-override di main() dengan instance yang sudah dimuat.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider harus di-override di main()'),
);

/// Pengaturan yang melekat ke HP ini (bukan ke akun), jadi TIDAK ikut sinkron:
/// printer Bluetooth, nama kasir, ID & kode perangkat.
class DeviceSettings {
  final String deviceId;
  final String printerAddress;
  final String printerName;
  final String cashierName;
  final bool autoPrint;

  /// Kode HP dari server (A, B, C...) per akun — dipakai untuk nomor antrean.
  final String? deviceCode;

  /// Jumlah HP yang terdaftar di akun ini (dari server, terakhir diketahui).
  final int deviceCount;

  const DeviceSettings({
    required this.deviceId,
    this.printerAddress = '',
    this.printerName = '',
    this.cashierName = '',
    this.autoPrint = false,
    this.deviceCode,
    this.deviceCount = 1,
  });

  /// Prefix nomor antrean. Kosong kalau toko cuma pakai 1 HP, supaya tetap "#001".
  String get queuePrefix =>
      (deviceCount > 1 && (deviceCode ?? '').isNotEmpty) ? '$deviceCode-' : '';
}

class DeviceSettingsNotifier extends Notifier<DeviceSettings> {
  static const _kDeviceId = 'device_id';
  static const _kPrinterAddress = 'printer_address';
  static const _kPrinterName = 'printer_name';
  static const _kCashierName = 'cashier_name';
  static const _kAutoPrint = 'auto_print';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  /// Kode & jumlah HP disimpan per akun (HP yang sama bisa dipakai beberapa akun).
  String? _userId;

  @override
  DeviceSettings build() {
    var id = _prefs.getString(_kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_kDeviceId, id);
    }
    return DeviceSettings(
      deviceId: id,
      printerAddress: _prefs.getString(_kPrinterAddress) ?? '',
      printerName: _prefs.getString(_kPrinterName) ?? '',
      cashierName: _prefs.getString(_kCashierName) ?? '',
      autoPrint: _prefs.getBool(_kAutoPrint) ?? false,
    );
  }

  DeviceSettings _copy({
    String? printerAddress,
    String? printerName,
    String? cashierName,
    bool? autoPrint,
    String? deviceCode,
    int? deviceCount,
    bool clearCode = false,
  }) =>
      DeviceSettings(
        deviceId: state.deviceId,
        printerAddress: printerAddress ?? state.printerAddress,
        printerName: printerName ?? state.printerName,
        cashierName: cashierName ?? state.cashierName,
        autoPrint: autoPrint ?? state.autoPrint,
        deviceCode: clearCode ? null : (deviceCode ?? state.deviceCode),
        deviceCount: deviceCount ?? (clearCode ? 1 : state.deviceCount),
      );

  /// Dipanggil saat user login/ganti akun: muat kode HP untuk akun tersebut.
  void bindUser(String? userId) {
    _userId = userId;
    if (userId == null) {
      state = _copy(clearCode: true);
      return;
    }
    final code = _prefs.getString('device_code_$userId');
    final count = _prefs.getInt('device_count_$userId') ?? 1;
    state = code == null ? _copy(clearCode: true) : _copy(deviceCode: code, deviceCount: count);
  }

  Future<void> setRegistration(String code, int deviceCount) async {
    final uid = _userId;
    if (uid == null) return;
    await _prefs.setString('device_code_$uid', code);
    await _prefs.setInt('device_count_$uid', deviceCount);
    state = _copy(deviceCode: code, deviceCount: deviceCount);
  }

  Future<void> setPrinter(String address, String name) async {
    await _prefs.setString(_kPrinterAddress, address);
    await _prefs.setString(_kPrinterName, name);
    state = _copy(printerAddress: address, printerName: name);
  }

  Future<void> setCashierName(String name) async {
    await _prefs.setString(_kCashierName, name.trim());
    state = _copy(cashierName: name.trim());
  }

  Future<void> setAutoPrint(bool value) async {
    await _prefs.setBool(_kAutoPrint, value);
    state = _copy(autoPrint: value);
  }

  /// Versi lama menyimpan printer di tabel settings (ikut sync ke cloud).
  /// Pindahkan sekali ke penyimpanan lokal HP.
  Future<void> migrateLegacyPrinter(Map<String, String> legacySettings) async {
    if (state.printerAddress.isNotEmpty) return;
    final address = legacySettings['printer_address'] ?? '';
    if (address.isEmpty) return;
    await setPrinter(address, legacySettings['printer_name'] ?? '');
  }
}

final deviceSettingsProvider =
    NotifierProvider<DeviceSettingsNotifier, DeviceSettings>(DeviceSettingsNotifier.new);
