import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/rupiah_input_formatter.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/order_totals.dart';
import '../providers/cart_provider.dart';
import '../providers/order_provider.dart';
import 'receipt_screen.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  final List<CartItem> cart;

  const CheckoutSheet({super.key, required this.cart});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  String _paymentMethod = 'Tunai';
  final _amountController = TextEditingController();
  final _discountController = TextEditingController();
  bool _discountIsPercent = false;
  bool _loading = false;

  final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  double get _subtotal => widget.cart.fold(0, (s, i) => s + i.subtotal);
  double get _amountPaid => RupiahInputFormatter.parse(_amountController.text);

  TaxDiscountSettings get _config =>
      TaxDiscountSettings.fromSettings(ref.watch(settingsProvider).valueOrNull ?? {});

  OrderTotals _totals(TaxDiscountSettings config) => OrderTotals.compute(
        subtotal: _subtotal,
        discountValue: config.discountEnabled ? RupiahInputFormatter.parse(_discountController.text) : 0,
        discountIsPercent: _discountIsPercent,
        taxPercent: config.activeTaxPercent,
      );

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _discountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _checkout(OrderTotals totals, TaxDiscountSettings config) async {
    if (_paymentMethod == 'Tunai' && _amountPaid < totals.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah bayar kurang dari total'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _loading = true);
    final order = await ref.read(orderProvider.notifier).checkout(
          items: widget.cart,
          totals: totals,
          taxName: totals.tax > 0 ? config.taxName : null,
          paymentMethod: _paymentMethod,
          amountPaid: _paymentMethod == 'Tunai' ? _amountPaid : null,
        );
    if (!mounted) return;
    setState(() => _loading = false);

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan pesanan'), backgroundColor: AppColors.error),
      );
      return;
    }

    ref.read(cartProvider.notifier).clear();
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final totals = _totals(config);
    final total = totals.total;
    final enough = _amountPaid >= total;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Pembayaran', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // ── Diskon (opsional, aktif dari Pengaturan) ──
              if (config.discountEnabled) ...[
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _discountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: _discountIsPercent
                          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]
                          : [const RupiahInputFormatter(maxDigits: 9)],
                      decoration: InputDecoration(
                        labelText: 'Diskon (opsional)',
                        prefixText: _discountIsPercent ? null : 'Rp ',
                        suffixText: _discountIsPercent ? '%' : null,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Rp')),
                      ButtonSegment(value: true, label: Text('%')),
                    ],
                    selected: {_discountIsPercent},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() {
                      _discountIsPercent = v.first;
                      _discountController.clear();
                    }),
                  ),
                ]),
                const SizedBox(height: 16),
              ],

              // ── Ringkasan total ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  if (totals.hasAdjustments) ...[
                    _SummaryRow('Subtotal', fmt.format(totals.subtotal)),
                    if (totals.discount > 0)
                      _SummaryRow('Diskon', '-${fmt.format(totals.discount)}', color: AppColors.success),
                    if (totals.tax > 0)
                      _SummaryRow(
                          '${config.taxName} ${_pct(config.taxPercent)}%', fmt.format(totals.tax)),
                    const Divider(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Tagihan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(fmt.format(total),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Metode pembayaran ──
              Row(
                children: ['Tunai', 'QRIS'].map((method) {
                  final selected = _paymentMethod == method;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _paymentMethod = method),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
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
                            Text(method,
                                style: TextStyle(
                                    color: selected ? Colors.white : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // ── Uang tunai ──
              if (_paymentMethod == 'Tunai') ...[
                const SizedBox(height: 16),
                // Tombol cepat: "Uang Pas" dulu (paling sering), lalu pecahan bulat.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AmountChip(
                      label: 'Uang Pas',
                      highlighted: true,
                      onTap: () => _amountController.text = RupiahInputFormatter.format(total),
                    ),
                    for (final amount in quickCashAmounts(total))
                      _AmountChip(
                        label: fmt.format(amount),
                        onTap: () => _amountController.text = RupiahInputFormatter.format(amount),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [RupiahInputFormatter(maxDigits: 10)],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Uang Diterima',
                    prefixText: 'Rp ',
                    prefixStyle: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    suffixIcon: _amountController.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear), onPressed: _amountController.clear),
                  ),
                ),
                const SizedBox(height: 12),
                if (_amountController.text.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: (enough ? AppColors.success : AppColors.error).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(enough ? 'Kembalian' : 'Kurang',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(fmt.format((_amountPaid - total).abs()),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: enough ? AppColors.success : AppColors.error)),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading || (_paymentMethod == 'Tunai' && !enough)
                      ? null
                      : () => _checkout(totals, config),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _paymentMethod == 'QRIS'
                              ? 'Konfirmasi Pembayaran QRIS'
                              : (_amountController.text.isEmpty
                                  ? 'Isi Uang Diterima'
                                  : (enough ? 'Proses Pembayaran' : 'Uang Belum Cukup')),
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pct(double p) => p == p.roundToDouble() ? p.toInt().toString() : p.toString();
}

/// Pecahan uang yang umum diterima kasir di atas [total] (tanpa duplikat,
/// tidak termasuk total itu sendiri — itu tombol "Uang Pas").
List<double> quickCashAmounts(double total) {
  final result = <double>{};
  for (final step in const [5000, 10000, 20000, 50000, 100000]) {
    final rounded = (total / step).ceil() * step.toDouble();
    if (rounded > total) result.add(rounded);
  }
  final sorted = result.toList()..sort();
  return sorted.take(4).toList();
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );
}

class _AmountChip extends StatelessWidget {
  final String label;
  final bool highlighted;
  final VoidCallback onTap;
  const _AmountChip({required this.label, required this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(label,
              style: TextStyle(
                  color: highlighted ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ),
      ),
    );
  }
}
