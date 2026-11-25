import 'package:intl/intl.dart';

import '../../orders/models/order_item_model.dart';
import '../../orders/models/order_model.dart';

class ReceiptLine {
  final String name;
  final int qty;
  final double price;
  final double subtotal;
  final String variantLabel;
  final String note;

  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.price,
    required this.subtotal,
    this.variantLabel = '',
    this.note = '',
  });
}

/// Satu-satunya sumber isi struk: dipakai layar struk, detail pesanan,
/// preview cetak, dan printer Bluetooth — supaya isinya selalu sama.
class ReceiptData {
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeDescription;
  final String orderNumber;
  final String? dailyNumber;
  final String dateTime;
  final List<ReceiptLine> items;
  final double subtotal;
  final double discount;
  final String taxName;
  final double? taxPercent;
  final double tax;
  final double total;
  final String paymentMethod;
  final double? amountPaid;
  final double? change;
  final String footer;
  final bool isVoid;

  const ReceiptData({
    required this.storeName,
    this.storeAddress = '',
    this.storePhone = '',
    this.storeDescription = '',
    required this.orderNumber,
    this.dailyNumber,
    required this.dateTime,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.taxName = 'Pajak',
    this.taxPercent,
    this.tax = 0,
    required this.total,
    required this.paymentMethod,
    this.amountPaid,
    this.change,
    this.footer = '',
    this.isVoid = false,
  });

  /// Baris Subtotal/Diskon/Pajak hanya muncul kalau memang ada.
  bool get hasAdjustments => discount > 0 || tax > 0;

  String get taxLabel {
    final p = taxPercent;
    if (p == null || p <= 0) return taxName;
    final pct = p == p.roundToDouble() ? p.toInt().toString() : p.toString();
    return '$taxName $pct%';
  }

  factory ReceiptData.fromOrder(
    OrderModel order,
    List<OrderItemModel> items,
    Map<String, String> settings,
  ) {
    return ReceiptData(
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'] ?? '',
      storePhone: settings['store_phone'] ?? '',
      storeDescription: settings['store_description'] ?? '',
      orderNumber: order.orderNumber,
      dailyNumber: order.dailyNumber,
      dateTime: DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(order.createdAtLocal),
      items: items
          .map((i) => ReceiptLine(
                name: i.productName,
                qty: i.qty,
                price: i.price,
                subtotal: i.subtotal,
                variantLabel: i.variantLabel ?? '',
                note: i.note ?? '',
              ))
          .toList(),
      subtotal: order.itemsSubtotal,
      discount: order.discountAmount,
      taxName: order.taxName ?? 'Pajak',
      taxPercent: order.taxPercent,
      tax: order.taxAmount,
      total: order.total,
      paymentMethod: order.paymentMethod,
      amountPaid: order.amountPaid,
      change: order.changeAmount,
      footer: settings['receipt_footer'] ?? 'Terima kasih!',
      isVoid: order.isVoid,
    );
  }
}
