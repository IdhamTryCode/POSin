class VariantOptionModel {
  final String id;
  final String? userId;
  final String groupId;
  final String name;
  final double priceModifier;
  final String createdAt;

  const VariantOptionModel({
    required this.id,
    this.userId,
    required this.groupId,
    required this.name,
    required this.priceModifier,
    required this.createdAt,
  });

  factory VariantOptionModel.fromMap(Map<String, dynamic> map) {
    return VariantOptionModel(
      id: map['id'],
      userId: map['user_id'],
      groupId: map['group_id'],
      name: map['name'],
      priceModifier: (map['price_modifier'] as num).toDouble(),
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'name': name,
      'price_modifier': priceModifier,
      'created_at': createdAt,
      if (userId != null) 'user_id': userId,
    };
  }


  VariantOptionModel copyWith({String? name, double? priceModifier, String? userId}) =>
      VariantOptionModel(
        id: id,
        userId: userId ?? this.userId,
        groupId: groupId,
        name: name ?? this.name,
        priceModifier: priceModifier ?? this.priceModifier,
        createdAt: createdAt,
      );
}
