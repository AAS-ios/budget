class IncomeSource {
  final String id;
  final String name;
  final bool isDefault;

  const IncomeSource({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  IncomeSource copyWith({
    String? id,
    String? name,
    bool? isDefault,
  }) {
    return IncomeSource(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
    };
  }

  factory IncomeSource.fromJson(Map<String, dynamic> json) {
    return IncomeSource(
      id: json['id'] as String,
      name: json['name'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
