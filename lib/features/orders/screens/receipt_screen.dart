import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/device/device_settings.dart';
import '../../printer/screens/print_preview_sheet.dart';
import '../../printer/services/printer_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/order_model.dart';

/// Struk setelah pembayaran. `order.items` wajib terisi.
class ReceiptScreen extends ConsumerStatefulWidget {
  final OrderModel order;

  const ReceiptScreen({super.key, required this.order});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    // Cetak otomatis (diatur per HP di Pengaturan → Printer).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final device = ref.read(deviceSettingsProvider);
      if (device.autoPrint && device.printerAddress.isNotEmpty) _print();
    });
  }

  ReceiptData _data() => ReceiptData.fromOrder(
        widget.order,
        widget.order.items,
        ref.read(settingsProvider).valueOrNull ?? {},
      );

  Future<void> _print() async {
    final printerAddress = ref.read(deviceSettingsProvider).printerAddress;
    if (printerAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada printer yang dipilih. Atur di Pengaturan.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _printing = true);
    final result = await PrinterService.instance.printReceipt(_data(), printerAddress: printerAddress);
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? 'Struk berhasil dicetak' : (result.error ?? 'Gagal mencetak')),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
        duration: Duration(seconds: result.success ? 2 : 6),
        action: result.success
            ? null
            : SnackBarAction(label: 'Coba Lagi', textColor: Colors.white, onPressed: _print),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final data = ReceiptData.fromOrder(widget.order, widget.order.items, settings);
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    const secondary = TextStyle(fontSize: 13, color: AppColors.textSecondary);

    Widget row(String label, String value, {TextStyle? labelStyle, TextStyle? valueStyle}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: labelStyle ?? secondary),
              Text(value, style: valueStyle ?? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk Pembayaran'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => PrintPreviewSheet(data: _data()),
            ),
            tooltip: 'Preview Cetak',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
                    const SizedBox(height: 8),
                    const Text('Pembayaran Berhasil',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.success)),
                    const SizedBox(height: 16),
                    if ((settings['logo_url'] ?? '').isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(settings['logo_url']!, height: 72, fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(data.storeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (data.storeAddress.isNotEmpty)
                      Text(data.storeAddress, style: secondary, textAlign: TextAlign.center),
                    if (data.storePhone.isNotEmpty) Text(data.storePhone, style: secondary),
                    if (data.storeDescription.isNotEmpty)
                      Text(data.storeDescription,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if ((data.dailyNumber ?? '').isNotEmpty) ...[
                      const Text('NO. PESANAN',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 1)),
                      Text('#${data.dailyNumber}',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      const SizedBox(height: 10),
                    ],
                    row('No. Order', data.orderNumber),
                    row('Tanggal', data.dateTime),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    for (final item in data.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                  if (item.variantLabel.isNotEmpty)
                                    Text(item.variantLabel,
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  if (item.note.isNotEmpty)
                                    Text('* ${item.note}',
                                        style: const TextStyle(
                                            fontSize: 11, color: AppColors.warning, fontStyle: FontStyle.italic)),
                                  Text('${item.qty} x ${fmt.format(item.price)}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Text(fmt.format(item.subtotal),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if (data.hasAdjustments) ...[
                      row('Subtotal', fmt.format(data.subtotal)),
                      if (data.discount > 0)
                        row('Diskon', '-${fmt.format(data.discount)}',
                            valueStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                      if (data.tax > 0) row(data.taxLabel, fmt.format(data.tax)),
                      const SizedBox(height: 4),
                    ],
                    row('TOTAL', fmt.format(data.total),
                        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        valueStyle: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    if (data.paymentMethod == 'Tunai' && data.amountPaid != null) ...[
                      row('Bayar', fmt.format(data.amountPaid!)),
                      row('Kembali', fmt.format(data.change ?? 0),
                          valueStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success)),
                    ],
                    row('Pembayaran', data.paymentMethod),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(data.footer, style: secondary, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: Text(_printing ? 'Mencetak...' : 'Cetak Struk'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Pesanan Baru'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
