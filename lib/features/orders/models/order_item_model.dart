class OrderItemModel {
  final String id;
  final String? userId;
  final String orderId;
  final String productId;
  final String productName;
  final double price;
  final int qty;
  final double subtotal;
  final String? variantLabel;

  const OrderItemModel({
    required this.id,
    this.userId,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.price,
    required this.qty,
    required this.subtotal,
    this.variantLabel,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      id: map['id'],
      userId: map['user_id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      productName: map['product_name'],
      price: (map['price'] as num).toDouble(),
      qty: map['qty'] is int ? map['qty'] : int.parse(map['qty'].toString()),
      subtotal: (map['subtotal'] as num).toDouble(),
      variantLabel: map['variant_label'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'qty': qty,
      'subtotal': subtotal,
      'variant_label': variantLabel,
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
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'qty': qty,
      'subtotal': subtotal,
      'variant_label': variantLabel,
    };
  }
}
