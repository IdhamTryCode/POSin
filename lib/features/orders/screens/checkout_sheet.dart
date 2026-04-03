import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/cart_provider.dart';
import '../providers/order_provider.dart';
import 'receipt_screen.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  final double total;
  final List<CartItem> cart;

  const CheckoutSheet({super.key, required this.total, required this.cart});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  String _paymentMethod = 'Tunai';
  final _amountController = TextEditingController();
  bool _loading = false;

  final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  double get _amountPaid => double.tryParse(_amountController.text.replaceAll('.', '')) ?? 0;
  double get _change => _amountPaid - widget.total;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (_paymentMethod == 'Tunai' && _amountPaid < widget.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah bayar kurang dari total'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _loading = true);
    final order = await ref.read(orderProvider.notifier).checkout(
      items: widget.cart,
      total: widget.total,
      paymentMethod: _paymentMethod,
      amountPaid: _paymentMethod == 'Tunai' ? _amountPaid : null,
    );
    setState(() => _loading = false);

    if (order == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuat order'), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    
    ref.read(cartProvider.notifier).clear();

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(order: order, items: widget.cart)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Pembayaran', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // Total
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Tagihan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(fmt.format(widget.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Payment method
              const Text('Metode Pembayaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: ['Tunai', 'QRIS'].map((method) {
                  final selected = _paymentMethod == method;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _paymentMethod = method),
                      child: Container(
                        margin: EdgeInsets.only(right: method == 'Tunai' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(method == 'Tunai' ? Icons.payments_outlined : Icons.qr_code,
                              color: selected ? Colors.white : AppColors.textSecondary, size: 20),
                            const SizedBox(width: 8),
                            Text(method, style: TextStyle(
                              color: selected ? Colors.white : AppColors.textSecondary,
                              fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              // Tunai input
              if (_paymentMethod == 'Tunai') ...[
                const SizedBox(height: 20),
                const Text('Jumlah Bayar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    prefixText: 'Rp ',
                    prefixStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    hintText: '0',
                    hintStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                ),
                if (_amountPaid >= widget.total) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembalian', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(fmt.format(_change),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.success)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Quick amount buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _quickAmounts().map((amount) => ActionChip(
                    label: Text(fmt.format(amount),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    side: const BorderSide(color: AppColors.primary, width: 1),
                    onPressed: () => _amountController.text = amount.toInt().toString(),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _checkout,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_paymentMethod == 'QRIS' ? 'Konfirmasi Pembayaran' : 'Proses Pembayaran'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<double> _quickAmounts() {
    final t = widget.total;
    final amounts = <double>[];
    for (final multiplier in [1, 2, 5, 10]) {
      final rounded = (t / (multiplier * 5000)).ceil() * multiplier * 5000.0;
      if (!amounts.contains(rounded)) amounts.add(rounded);
      if (amounts.length >= 4) break;
    }
    return amounts;
  }
}
