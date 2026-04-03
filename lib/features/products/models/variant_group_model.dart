import 'variant_option_model.dart';

class VariantGroupModel {
  final String id;
  final String? userId;
  final String productId;
  final String name;
  final bool isRequired;
  final String createdAt;
  final List<VariantOptionModel> options;

  const VariantGroupModel({
    required this.id,
    this.userId,
    required this.productId,
    required this.name,
    required this.isRequired,
    required this.createdAt,
    this.options = const [],
  });

  factory VariantGroupModel.fromMap(Map<String, dynamic> map) {
    return VariantGroupModel(
      id: map['id'],
      userId: map['user_id'],
      productId: map['product_id'],
      name: map['name'],
      isRequired: map['is_required'] == 1 || map['is_required'] == true,
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'name': name,
      'is_required': isRequired ? 1 : 0,
      'created_at': createdAt,
      if (userId != null) 'user_id': userId,
    };
  }

  Map<String, dynamic> toMapSupabase(String uid) {
    return {
      'id': id,
      'user_id': uid,
      'product_id': productId,
      'name': name,
      'is_required': isRequired ? 1 : 0,
      'created_at': createdAt,
    };
  }

  VariantGroupModel copyWith({
    String? name,
    bool? isRequired,
    List<VariantOptionModel>? options,
    String? userId,
  }) => VariantGroupModel(
    id: id,
    userId: userId ?? this.userId,
    productId: productId,
    name: name ?? this.name,
    isRequired: isRequired ?? this.isRequired,
    createdAt: createdAt,
    options: options ?? this.options,
  );
}
