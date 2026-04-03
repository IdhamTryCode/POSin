import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../settings/providers/settings_provider.dart';
import '../services/printer_service.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  List<BluetoothDeviceInfo> _devices = [];
  bool _scanning = false;
  String? _connectedAddress;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    _connectedAddress = settings['printer_address'];
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _scanError = null; _devices = []; });
    try {
      final devices = await PrinterService.instance.getBondedDevices();
      setState(() {
        _devices = devices;
        _scanning = false;
      });
      if (devices.isEmpty) {
        _showNoPairedDialog();
      }
    } catch (e) {
      setState(() { _scanning = false; _scanError = e.toString(); });
    }
  }

  void _showNoPairedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Belum Ada Printer Ter-pair'),
        content: const Text(
          'Kamu perlu pair printer Bluetooth terlebih dahulu di Pengaturan HP.\n\n'
          '1. Hidupkan printer\n'
          '2. Buka Pengaturan Bluetooth HP\n'
          '3. Pair dengan printer\n'
          '4. Kembali ke sini dan cari lagi',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Nanti'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Buka halaman Bluetooth settings Android
              final uri = Uri.parse('android-settings:bluetooth');
              if (!await launchUrl(uri)) {
                // Fallback: buka settings umum
                await launchUrl(Uri.parse('android.settings.BLUETOOTH_SETTINGS'));
              }
            },
            child: const Text('Buka Pengaturan Bluetooth'),
          ),
        ],
      ),
    );
  }

  Future<void> _select(BluetoothDeviceInfo device) async {
    await ref.read(settingsProvider.notifier).setSetting('printer_address', device.address);
    await ref.read(settingsProvider.notifier).setSetting('printer_name', device.name);
    setState(() => _connectedAddress = device.address);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer "${device.name}" dipilih'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _testPrint(BluetoothDeviceInfo device) async {
    final result = await PrinterService.instance.printReceipt(
      storeName: 'TEST PRINT',
      storeAddress: 'POSin',
      storePhone: '',
      orderNumber: 'TEST-001',
      dateTime: DateTime.now().toString().substring(0, 16),
      items: [{'name': 'Test Item', 'qty': 1, 'price': 10000.0, 'subtotal': 10000.0}],
      total: 10000,
      paymentMethod: 'Tunai',
      footer: 'Printer berfungsi dengan baik!',
      printerAddress: device.address,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? '✓ Test print berhasil!' : '✗ ${result.error}'),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final savedName = settings['printer_name'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Bluetooth')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Printer aktif
          if (savedName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Printer Aktif', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
                  Text(savedName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ])),
              ]),
            ),

          // Tombol scan
          ElevatedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? 'Mencari...' : 'Cari Printer Bluetooth'),
          ),

          // Error scan
          if (_scanError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_scanError!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
              ]),
            ),
          ],

          // Daftar device
          if (_devices.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Perangkat Ter-pair', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Pilih printer ESC/POS 58mm atau 80mm', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ..._devices.map((device) {
              final isSelected = _connectedAddress == device.address;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  ListTile(
                    leading: Icon(Icons.print_outlined,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary),
                    title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(device.address, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.primary)
                        : ElevatedButton(
                            onPressed: () => _select(device),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(72, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            child: const Text('Pilih'),
                          ),
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _testPrint(device),
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text('Test Print'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 36),
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ],

          const SizedBox(height: 24),

          // Tombol buka Bluetooth settings
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse('android-settings:bluetooth');
              if (!await launchUrl(uri)) {
                await launchUrl(Uri.parse('android.settings.BLUETOOTH_SETTINGS'));
              }
            },
            icon: const Icon(Icons.settings_bluetooth, size: 18),
            label: const Text('Buka Pengaturan Bluetooth HP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
            ),
          ),

          const SizedBox(height: 16),
          const _PrinterTips(),
        ],
      ),
    );
  }
}

class _PrinterTips extends StatelessWidget {
  const _PrinterTips();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Cara Setup Printer', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          ]),
          SizedBox(height: 10),
          Text(
            '1. Hidupkan printer Bluetooth\n'
            '2. Tap "Buka Pengaturan Bluetooth HP" di atas\n'
            '3. Pair printer (biasanya muncul sebagai "POS58", "RPP02", dll)\n'
            '4. Kembali ke sini → tap "Cari Printer Bluetooth"\n'
            '5. Pilih printer → Test Print\n\n'
            '✓ Support semua printer ESC/POS 58mm & 80mm\n'
            '✓ POS58B, RPP02, XP-P300, Epson TM, dll',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}
