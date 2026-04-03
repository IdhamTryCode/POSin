import 'order_item_model.dart';

class OrderModel {
  final String id;
  final String? userId;
  final String orderNumber;
  final double total;
  final String paymentMethod;
  final double? amountPaid;
  final double? changeAmount;
  final String? note;
  final String createdAt;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    this.userId,
    required this.orderNumber,
    required this.total,
    required this.paymentMethod,
    this.amountPaid,
    this.changeAmount,
    this.note,
    required this.createdAt,
    this.items = const [],
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'],
      userId: map['user_id'],
      orderNumber: map['order_number'],
      total: (map['total'] as num).toDouble(),
      paymentMethod: map['payment_method'],
      amountPaid: map['amount_paid'] != null ? (map['amount_paid'] as num).toDouble() : null,
      changeAmount: map['change_amount'] != null ? (map['change_amount'] as num).toDouble() : null,
      note: map['note'],
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'order_number': orderNumber,
      'total': total,
      'payment_method': paymentMethod,
      'amount_paid': amountPaid,
      'change_amount': changeAmount,
      'note': note,
      'created_at': createdAt,
    };
    if (userId != null) {
      map['user_id'] = userId;
    }
    return map;
  }

  Map<String, dynamic> toMapSupabase(String uid) {
    return {
      'id': id,
      'user_id': uid,
      'order_number': orderNumber,
      'total': total,
      'payment_method': paymentMethod,
      'amount_paid': amountPaid,
      'change_amount': changeAmount,
      'note': note,
      'created_at': createdAt,
    };
  }
}
