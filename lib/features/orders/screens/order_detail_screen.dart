import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../printer/services/printer_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../providers/order_provider.dart';
import '../../printer/screens/print_preview_sheet.dart' show PrintPreviewSheet, ReceiptPreviewData;

class OrderDetailScreen extends ConsumerStatefulWidget {
  final OrderModel order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  List<OrderItemModel>? _items;
  bool _loadingItems = true;
  bool _printing = false;

  final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await ref.read(orderProvider.notifier).getOrderItems(widget.order.id);
    if (mounted) setState(() { _items = items; _loadingItems = false; });
  }

  Future<void> _reprint() async {
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final printerAddress = settings['printer_address'] ?? '';

    if (printerAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada printer yang dipilih. Atur di Pengaturan.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_items == null || _items!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data item tidak ditemukan'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _printing = true);
    final result = await PrinterService.instance.printReceipt(
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'] ?? '',
      storePhone: settings['store_phone'] ?? '',
      storeDescription: settings['store_description'] ?? '',
      orderNumber: widget.order.orderNumber,
      dateTime: dateFmt.format(DateTime.parse(widget.order.createdAt)),
      items: _items!.map((i) => {
        'name': i.productName,
        'qty': i.qty,
        'price': i.price,
        'subtotal': i.subtotal,
        'variant_label': i.variantLabel ?? '',
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

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Pesanan?'),
        content: Text('Pesanan #${widget.order.orderNumber} akan dihapus permanen dari riwayat dan cloud. Lanjutkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await ref.read(orderProvider.notifier).deleteOrder(widget.order.id);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesanan dihapus'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menghapus pesanan'), backgroundColor: AppColors.error),
      );
    }
  }

  void _showPreview(BuildContext context, Map<String, String> settings) {
    if (_items == null) return;
    final previewData = ReceiptPreviewData(
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'] ?? '',
      storePhone: settings['store_phone'] ?? '',
      storeDescription: settings['store_description'] ?? '',
      orderNumber: widget.order.orderNumber,
      dateTime: dateFmt.format(DateTime.parse(widget.order.createdAt)),
      items: _items!.map((i) => {
        'name': i.productName,
        'qty': i.qty,
        'price': i.price,
        'subtotal': i.subtotal,
        'variant_label': i.variantLabel ?? '',
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
    final order = widget.order;
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text('#${order.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            onPressed: (_loadingItems || _items == null) ? null : () => _showPreview(context, settings),
            tooltip: 'Preview Cetak',
          ),
          IconButton(
            icon: _printing
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined),
            onPressed: (_printing || _loadingItems) ? null : _reprint,
            tooltip: 'Cetak Ulang Struk',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _printing ? null : _confirmDelete,
            tooltip: 'Hapus Pesanan',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Store header
                    if ((settings['logo_url'] ?? '').isNotEmpty) ...[
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            settings['logo_url']!,
                            height: 72, fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Center(
                      child: Text(
                        settings['store_name'] ?? 'Toko Saya',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if ((settings['store_address'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          settings['store_address']!,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if ((settings['store_phone'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Center(
                        child: Text(
                          settings['store_phone']!,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Order info
                    _InfoRow(label: 'No. Order', value: order.orderNumber),
                    const SizedBox(height: 4),
                    _InfoRow(
                      label: 'Tanggal',
                      value: dateFmt.format(DateTime.parse(order.createdAt)),
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Items
                    if (_loadingItems)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_items == null || _items!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text('Tidak ada data item', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else
                      ..._items!.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  if (item.variantLabel != null && item.variantLabel!.isNotEmpty)
                                    Text(
                                      item.variantLabel!,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  Text(
                                    '${item.qty} x ${fmt.format(item.price)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              fmt.format(item.subtotal),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )),

                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          fmt.format(order.total),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),

                    if (order.paymentMethod == 'Tunai' && order.amountPaid != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bayar', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                          Text(fmt.format(order.amountPaid!), style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kembali', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                          Text(
                            fmt.format(order.changeAmount ?? 0),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success),
                          ),
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
                          child: Text(
                            order.paymentMethod,
                            style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),

                    if ((settings['receipt_footer'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          settings['receipt_footer']!,
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
          onPressed: (_printing || _loadingItems) ? null : _reprint,
          icon: _printing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.print_outlined),
          label: const Text('Cetak Ulang Struk'),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
