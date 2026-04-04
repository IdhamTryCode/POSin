import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';

/// Structured receipt data for preview rendering.
class ReceiptPreviewData {
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeDescription;
  final String orderNumber;
  final String dateTime;
  final List<Map<String, dynamic>> items; // name, qty, price, subtotal, variant_label?
  final double total;
  final String paymentMethod;
  final double? amountPaid;
  final double? change;
  final String footer;

  const ReceiptPreviewData({
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    required this.storeDescription,
    required this.orderNumber,
    required this.dateTime,
    required this.items,
    required this.total,
    required this.paymentMethod,
    this.amountPaid,
    this.change,
    required this.footer,
  });
}

class PrintPreviewSheet extends StatelessWidget {
  final ReceiptPreviewData data;
  const PrintPreviewSheet({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('Preview Struk (58mm)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Center(
                child: Container(
                  width: 230,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDE7),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: _ReceiptContent(data: data),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ReceiptContent extends StatelessWidget {
  final ReceiptPreviewData data;
  const _ReceiptContent({required this.data});

  static const _style = TextStyle(fontFamily: 'monospace', fontSize: 9.5, height: 1.4, color: Colors.black87);
  static const _bold = TextStyle(fontFamily: 'monospace', fontSize: 9.5, height: 1.4, color: Colors.black87, fontWeight: FontWeight.bold);
  static const _dim = TextStyle(fontFamily: 'monospace', fontSize: 8.5, height: 1.4, color: Colors.black54);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Store header
        Text(data.storeName, style: _bold.copyWith(fontSize: 10.5), textAlign: TextAlign.center),
        if (data.storeAddress.isNotEmpty)
          Text(data.storeAddress, style: _dim, textAlign: TextAlign.center),
        if (data.storePhone.isNotEmpty)
          Text(data.storePhone, style: _dim, textAlign: TextAlign.center),
        if (data.storeDescription.isNotEmpty)
          Text(data.storeDescription, style: _dim, textAlign: TextAlign.center),

        const SizedBox(height: 6),
        _Divider(),
        const SizedBox(height: 4),

        // Order info
        _Row2('No:', data.orderNumber, style: _style),
        _Row2('Tgl:', data.dateTime, style: _style),

        const SizedBox(height: 4),
        _Divider(),
        const SizedBox(height: 4),

        // Items
        for (final item in data.items) ...[
          Text(item['name'] as String, style: _bold),
          if ((item['variant_label'] as String? ?? '').isNotEmpty)
            Text(item['variant_label'] as String, style: _dim),
          _Row2(
            '  ${item['qty']}x${fmt.format(item['price'] as double)}',
            fmt.format(item['subtotal'] as double),
            style: _style,
          ),
          const SizedBox(height: 2),
        ],

        _Divider(),
        const SizedBox(height: 4),

        // Total
        _Row2('TOTAL', fmt.format(data.total), style: _bold.copyWith(fontSize: 10.5)),

        if (data.paymentMethod == 'Tunai' && data.amountPaid != null) ...[
          const SizedBox(height: 2),
          _Row2('Bayar', fmt.format(data.amountPaid!), style: _style),
          _Row2('Kembali', fmt.format(data.change ?? 0), style: _style),
        ],

        const SizedBox(height: 4),
        _Divider(),
        const SizedBox(height: 4),

        Text(data.paymentMethod, style: _style, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(data.footer, style: _dim, textAlign: TextAlign.center),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      '--------------------------------',
      style: TextStyle(fontFamily: 'monospace', fontSize: 9.5, height: 1, color: Colors.black54),
      overflow: TextOverflow.visible,
    );
  }
}

class _Row2 extends StatelessWidget {
  final String left;
  final String right;
  final TextStyle style;
  const _Row2(this.left, this.right, {required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: Text(left, style: style)),
        const SizedBox(width: 4),
        Text(right, style: style, textAlign: TextAlign.right),
      ],
    );
  }
}
