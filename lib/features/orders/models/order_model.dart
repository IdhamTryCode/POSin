import 'order_item_model.dart';

class OrderModel {
  static const statusPaid = 'paid';
  static const statusVoid = 'void';

  final String id;
  final String? userId;
  final String orderNumber;
  final String? dailyNumber;
  final double total;
  final String paymentMethod;
  final double? amountPaid;
  final double? changeAmount;
  final String? note;

  /// Waktu lokal tanpa zona (format lama, tetap dipakai untuk kompatibilitas APK lama).
  final String createdAt;
  final String status;
  final String? voidedAt;
  final String? voidReason;
  final String? deviceId;
  final String? cashierName;
  final String? customerName;

  /// Diskon & pajak (opsional). Order lama / toko tanpa pajak: 0.
  final double? subtotal;
  final double discountAmount;
  final String? taxName;
  final double? taxPercent;
  final double taxAmount;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    this.userId,
    required this.orderNumber,
    this.dailyNumber,
    required this.total,
    required this.paymentMethod,
    this.amountPaid,
    this.changeAmount,
    this.note,
    required this.createdAt,
    this.status = statusPaid,
    this.voidedAt,
    this.voidReason,
    this.deviceId,
    this.cashierName,
    this.customerName,
    this.subtotal,
    this.discountAmount = 0,
    this.taxName,
    this.taxPercent,
    this.taxAmount = 0,
    this.items = const [],
  });

  bool get isVoid => status == statusVoid;

  /// Subtotal sebelum diskon & pajak (order lama tidak menyimpannya).
  double get itemsSubtotal => subtotal ?? (total + discountAmount - taxAmount);
  bool get hasAdjustments => discountAmount > 0 || taxAmount > 0;

  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  static double? _num(Object? v) => v == null ? null : (v as num).toDouble();

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'],
      userId: map['user_id'],
      orderNumber: map['order_number'],
      dailyNumber: map['daily_number'],
      total: _num(map['total'])!,
      paymentMethod: map['payment_method'],
      amountPaid: _num(map['amount_paid']),
      changeAmount: _num(map['change_amount']),
      note: map['note'],
      createdAt: map['created_at'],
      status: (map['status'] as String?) ?? statusPaid,
      voidedAt: map['voided_at'],
      voidReason: map['void_reason'],
      deviceId: map['device_id'],
      cashierName: map['cashier_name'],
      customerName: map['customer_name'],
      subtotal: _num(map['subtotal']),
      discountAmount: _num(map['discount_amount']) ?? 0,
      taxName: map['tax_name'],
      taxPercent: _num(map['tax_percent']),
      taxAmount: _num(map['tax_amount']) ?? 0,
    );
  }

  /// Baris SQLite lokal (juga payload yang dikirim ke server).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'daily_number': dailyNumber,
      'total': total,
      'payment_method': paymentMethod,
      'amount_paid': amountPaid,
      'change_amount': changeAmount,
      'note': note,
      'created_at': createdAt,
      'created_at_ts': DateTime.parse(createdAt).toUtc().toIso8601String(),
      'status': status,
      'voided_at': voidedAt,
      'void_reason': voidReason,
      'device_id': deviceId,
      'cashier_name': cashierName,
      'customer_name': customerName,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'tax_name': taxName,
      'tax_percent': taxPercent,
      'tax_amount': taxAmount,
      if (userId != null) 'user_id': userId,
    };
  }

  OrderModel voided(String reason, DateTime at) => OrderModel(
        id: id,
        userId: userId,
        orderNumber: orderNumber,
        dailyNumber: dailyNumber,
        total: total,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
        changeAmount: changeAmount,
        note: note,
        createdAt: createdAt,
        status: statusVoid,
        voidedAt: at.toUtc().toIso8601String(),
        voidReason: reason,
        deviceId: deviceId,
        cashierName: cashierName,
        customerName: customerName,
        subtotal: subtotal,
        discountAmount: discountAmount,
        taxName: taxName,
        taxPercent: taxPercent,
        taxAmount: taxAmount,
        items: items,
      );
}
