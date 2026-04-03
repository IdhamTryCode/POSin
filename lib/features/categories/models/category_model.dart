class CategoryModel {
  final String id;
  final String? userId;
  final String name;
  final int color;
  final String createdAt;

  const CategoryModel({
    required this.id,
    this.userId,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'],
      userId: map['user_id'],
      name: map['name'],
      color: map['color'] is int ? map['color'] : int.parse(map['color'].toString()),
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'created_at': createdAt,
      if (userId != null) 'user_id': userId,
    };
  }

  Map<String, dynamic> toMapSupabase(String uid) {
    return {
      'id': id,
      'user_id': uid,
      'name': name,
      'color': color,
      'created_at': createdAt,
    };
  }

  CategoryModel copyWith({String? name, int? color, String? userId}) {
    return CategoryModel(
      id: id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt,
    );
  }
}
