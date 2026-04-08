import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../printer/screens/print_preview_sheet.dart' show PrintPreviewSheet, ReceiptPreviewData;
import '../../printer/services/printer_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/order_model.dart';
import '../providers/cart_provider.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final OrderModel order;
  final List<CartItem> items;

  const ReceiptScreen({super.key, required this.order, required this.items});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _printing = false;

  Future<void> _print() async {
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final printerAddress = settings['printer_address'] ?? '';

    if (printerAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada printer yang dipilih. Atur di Pengaturan.'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _printing = true);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    final result = await PrinterService.instance.printReceipt(
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'] ?? '',
      storePhone: settings['store_phone'] ?? '',
      storeDescription: settings['store_description'] ?? '',
      orderNumber: widget.order.orderNumber,
      dailyNumber: widget.order.dailyNumber,
      dateTime: dateFmt.format(DateTime.parse(widget.order.createdAt)),
      items: widget.items.map((i) => {
        'name': i.product.name,
        'qty': i.qty,
        'price': i.effectivePrice,
        'subtotal': i.subtotal,
        'variant_label': i.variantLabel,
        'note': i.note ?? '',
      }).toList(),
      total: widget.order.total,
      paymentMethod: widget.order.paymentMethod,
      amountPaid: widget.order.amountPaid,
      change: widget.order.changeAmount,
      footer: settings['receipt_footer'] ?? 'Terima kasih!',
      printerAddress: printerAddress,
    );

    setState(() => _printing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? 'Struk berhasil dicetak' : (result.error ?? 'Gagal mencetak')),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
        duration: Duration(seconds: result.success ? 2 : 6),
      ),
    );
  }

  void _showPrintPreview({
    required BuildContext context,
    required Map<String, String> settings,
    required DateFormat dateFmt,
  }) {
    final previewData = ReceiptPreviewData(
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'] ?? '',
      storePhone: settings['store_phone'] ?? '',
      storeDescription: settings['store_description'] ?? '',
      orderNumber: widget.order.orderNumber,
      dailyNumber: widget.order.dailyNumber,
      dateTime: dateFmt.format(DateTime.parse(widget.order.createdAt)),
      items: widget.items.map((i) => {
        'name': i.product.name,
        'qty': i.qty,
        'price': i.effectivePrice,
        'subtotal': i.subtotal,
        'variant_label': i.variantLabel,
        'note': i.note ?? '',
      }).toList(),
      total: widget.order.total,
      paymentMethod: widget.order.paymentMethod,
      amountPaid: widget.order.amountPaid,
      change: widget.order.changeAmount,
      footer: settings['receipt_footer'] ?? 'Terima kasih!',
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrintPreviewSheet(data: previewData),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final storeName = settings['store_name'] ?? 'Toko Saya';
    final storeAddress = settings['store_address'] ?? '';
    final storePhone = settings['store_phone'] ?? '';
    final storeDescription = settings['store_description'] ?? '';
    final footer = settings['receipt_footer'] ?? 'Terima kasih!';
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk Pembayaran'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => _showPrintPreview(
              context: context,
              settings: settings,
              dateFmt: dateFmt,
            ),
            tooltip: 'Preview Cetak',
          ),
          IconButton(
            icon: _printing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined),
            onPressed: _printing ? null : _print,
            tooltip: 'Cetak Struk',
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
                    if ((settings['logo_url'] ?? '').isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(settings['logo_url']!, height: 72, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(storeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (storeAddress.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(storeAddress, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
                    ],
                    if (storePhone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(storePhone, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                    if (storeDescription.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(storeDescription, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if ((widget.order.dailyNumber ?? '').isNotEmpty) ...[
                      const Text('NO. PESANAN',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 1),
                        textAlign: TextAlign.center),
                      const SizedBox(height: 2),
                      Text('#${widget.order.dailyNumber}',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary),
                        textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('No. Order', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(widget.order.orderNumber, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tanggal', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(dateFmt.format(DateTime.parse(widget.order.createdAt)),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    ...widget.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                if (item.variantLabel.isNotEmpty)
                                  Text(item.variantLabel, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                Text('${item.qty} x ${fmt.format(item.effectivePrice)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text(fmt.format(item.subtotal), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(fmt.format(widget.order.total),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                    if (widget.order.paymentMethod == 'Tunai' && widget.order.amountPaid != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bayar', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                          Text(fmt.format(widget.order.amountPaid!), style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kembali', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                          Text(fmt.format(widget.order.changeAmount ?? 0),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pembayaran', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(widget.order.paymentMethod,
                            style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(footer, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: const Icon(Icons.home_outlined),
          label: const Text('Kembali ke Kasir'),
        ),
      ),
    );
  }
}

