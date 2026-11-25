import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/device/device_settings.dart';
import '../../printer/services/printer_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../providers/order_provider.dart';
import '../../printer/screens/print_preview_sheet.dart' show PrintPreviewSheet, ReceiptData;

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

    if (_items == null || _items!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data item tidak ditemukan'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _printing = true);
    final result = await PrinterService.instance.printReceipt(
      ReceiptData.fromOrder(_currentOrder(), _items!, settings),
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

  Future<void> _confirmVoid() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _VoidReasonDialog(),
    );
    if (reason == null) return;

    final ok = await ref.read(orderProvider.notifier).voidOrder(widget.order.id, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Pesanan dibatalkan' : 'Gagal membatalkan pesanan'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  void _showPreview(BuildContext context, Map<String, String> settings) {
    if (_items == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrintPreviewSheet(data: ReceiptData.fromOrder(_currentOrder(), _items!, settings)),
    );
  }

  /// Versi terbaru order (mis. sudah dibatalkan dari HP lain).
  OrderModel _currentOrder() =>
      (ref.read(orderProvider).valueOrNull ?? const <OrderModel>[])
          .where((o) => o.id == widget.order.id)
          .firstOrNull ??
      widget.order;

  @override
  Widget build(BuildContext context) {
    // Selalu tampilkan versi terbaru (mis. dibatalkan dari HP lain).
    final order = (ref.watch(orderProvider).valueOrNull ?? const <OrderModel>[])
            .where((o) => o.id == widget.order.id)
            .firstOrNull ??
        widget.order;
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (order.dailyNumber ?? '').isNotEmpty
              ? '#${order.dailyNumber}'
              : '#${order.orderNumber}',
        ),
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
          if (!order.isVoid)
            IconButton(
              icon: const Icon(Icons.block_outlined),
              onPressed: _printing ? null : _confirmVoid,
              tooltip: 'Batalkan Pesanan',
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
                    if (order.isVoid) ...[
                      _VoidBanner(order: order),
                      const SizedBox(height: 16),
                    ],
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

                    if ((order.dailyNumber ?? '').isNotEmpty) ...[
                      const Center(
                        child: Text('NO. PESANAN',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 2),
                      Center(
                        child: Text('#${order.dailyNumber}',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Order info
                    _InfoRow(label: 'No. Order', value: order.orderNumber),
                    const SizedBox(height: 4),
                    _InfoRow(
                      label: 'Tanggal',
                      value: dateFmt.format(order.createdAtLocal),
                    ),
                    if ((order.customerName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _InfoRow(label: 'Pelanggan', value: order.customerName!),
                    ],
                    if ((order.cashierName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _InfoRow(label: 'Kasir', value: order.cashierName!),
                    ],

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
                                  if (item.note != null && item.note!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '* ${item.note!}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.warning, fontStyle: FontStyle.italic),
                                      ),
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

                    // Subtotal / diskon / pajak — hanya kalau ada.
                    if (order.hasAdjustments) ...[
                      _InfoRow(label: 'Subtotal', value: fmt.format(order.itemsSubtotal)),
                      if (order.discountAmount > 0) ...[
                        const SizedBox(height: 4),
                        _InfoRow(label: 'Diskon', value: '-${fmt.format(order.discountAmount)}'),
                      ],
                      if (order.taxAmount > 0) ...[
                        const SizedBox(height: 4),
                        _InfoRow(
                          label: ReceiptData.fromOrder(order, const [], const {}).taxLabel,
                          value: fmt.format(order.taxAmount),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],

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

class _VoidBanner extends StatelessWidget {
  final OrderModel order;
  const _VoidBanner({required this.order});

  @override
  Widget build(BuildContext context) {
    final at = order.voidedAt == null
        ? ''
        : DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(DateTime.parse(order.voidedAt!).toLocal());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.block, size: 16, color: AppColors.error),
          SizedBox(width: 6),
          Text('PESANAN DIBATALKAN',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.error)),
        ]),
        if ((order.voidReason ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Alasan: ${order.voidReason}', style: const TextStyle(fontSize: 13)),
        ],
        if (at.isNotEmpty)
          Text(at, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        const Text('Tidak dihitung dalam omzet laporan.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog();

  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
  final _controller = TextEditingController();
  static const _quickReasons = ['Salah input', 'Pelanggan batal', 'Pesanan dobel', 'Menu habis'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Batalkan Pesanan?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Pesanan tetap tersimpan di riwayat sebagai "dibatalkan" dan tidak dihitung di omzet. '
          'Tindakan ini tidak bisa diurungkan.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: _quickReasons.map((r) => ActionChip(
          label: Text(r, style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _controller.text = r),
        )).toList()),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Alasan pembatalan (wajib)'),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kembali')),
        TextButton(
          onPressed: valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Batalkan Pesanan'),
        ),
      ],
    );
  }
}
