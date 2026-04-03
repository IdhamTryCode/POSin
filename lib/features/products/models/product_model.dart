class ProductModel {
  final String id;
  final String? userId;
  final String name;
  final double price;
  final String? categoryId;
  final String? imagePath;
  final bool isActive;
  final String createdAt;

  const ProductModel({
    required this.id,
    this.userId,
    required this.name,
    required this.price,
    this.categoryId,
    this.imagePath,
    required this.isActive,
    required this.createdAt,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      userId: map['user_id'],
      name: map['name'],
      price: (map['price'] as num).toDouble(),
      categoryId: map['category_id'],
      imagePath: map['image_path'],
      isActive: map['is_active'] == 1 || map['is_active'] == true,
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'name': name,
      'price': price,
      'category_id': categoryId,
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
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
      'name': name,
      'price': price,
      'category_id': categoryId,
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  ProductModel copyWith({
    String? name,
    double? price,
    String? categoryId,
    String? imagePath,
    bool? isActive,
    String? userId,
  }) {
    return ProductModel(
      id: id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      imagePath: imagePath ?? this.imagePath,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
