class ExpenseCategory {
  final String id;
  final String name;
  final bool isDefault;

  /// ID родительской категории. null — категория верхнего уровня.
  final String? parentId;

  /// План расходов на месяц (только для верхнего уровня).
  /// null — без лимита.
  final double? monthlyLimit;

  const ExpenseCategory({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.parentId,
    this.monthlyLimit,
  });

  bool get isTopLevel => parentId == null;

  ExpenseCategory copyWith({
    String? id,
    String? name,
    bool? isDefault,
    String? parentId,
    double? monthlyLimit,
    bool clearLimit = false,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      parentId: parentId ?? this.parentId,
      monthlyLimit: clearLimit ? null : (monthlyLimit ?? this.monthlyLimit),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'parentId': parentId,
      'monthlyLimit': monthlyLimit,
    };
  }

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      parentId: json['parentId'] as String?,
      monthlyLimit: (json['monthlyLimit'] as num?)?.toDouble(),
    );
  }
}
