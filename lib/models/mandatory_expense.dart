enum ExpensePeriod {
  once,
  monthly,
  yearly,
  custom,
}

/// Запись в журнале резерва: сколько отложено (или снято) и когда.
class ReserveEntry {
  final DateTime date;
  final double amount;

  const ReserveEntry({required this.date, required this.amount});

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'amount': amount,
      };

  factory ReserveEntry.fromJson(Map<String, dynamic> json) {
    return ReserveEntry(
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

class MandatoryExpense {
  final String id;
  final String name;

  /// Планируемая сумма.
  /// Для переменных платежей это ориентировочная сумма.
  final double amount;

  /// Дата ближайшего платежа.
  final DateTime dueDate;

  /// Периодичность платежа.
  final ExpensePeriod period;

  /// Используется только для custom.
  /// Например, 2 = каждые 2 месяца.
  final int? customIntervalMonths;

  /// true — если сумма каждый раз может отличаться.
  /// Например, коммунальные услуги.
  final bool isVariableAmount;

  final String comment;

  /// Оплачен ли разовый платёж.
  /// Повторяющиеся платежи после оплаты просто
  /// переносятся на следующую дату.
  final bool isPaid;

  /// Счёт, с которого обычно платится.
  final String? accountId;

  /// Категория и подкатегория расхода при оплате.
  /// null — «Обязательные платежи».
  final String? category;
  final String? subcategory;

  /// Журнал резерва для редких платежей (ОСАГО и т.п.).
  final List<ReserveEntry> reserveLog;

  /// Счёт, на котором лежит резерв. null — на доступных счетах.
  final String? reserveAccountId;

  const MandatoryExpense({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueDate,
    required this.period,
    this.customIntervalMonths,
    this.isVariableAmount = false,
    this.comment = '',
    this.isPaid = false,
    this.accountId,
    this.category,
    this.subcategory,
    this.reserveLog = const [],
    this.reserveAccountId,
  });

  /// Редкий платёж: реже раза в месяц или разовый.
  /// На такие платежи откладывают заранее.
  bool get isRare => period != ExpensePeriod.monthly && intervalMonths != 1;

  /// Сколько уже отложено.
  double get reserved {
    final sum = reserveLog.fold(0.0, (total, entry) => total + entry.amount);

    return (sum * 100).roundToDouble() / 100;
  }

  /// Отложено в указанном месяце.
  double reservedInMonth(int year, int month) {
    return reserveLog
        .where((entry) => entry.date.year == year && entry.date.month == month)
        .fold(0.0, (total, entry) => total + entry.amount);
  }

  /// Через сколько месяцев повторяется платёж.
  /// 0 — разовый.
  int get intervalMonths {
    switch (period) {
      case ExpensePeriod.once:
        return 0;
      case ExpensePeriod.monthly:
        return 1;
      case ExpensePeriod.yearly:
        return 12;
      case ExpensePeriod.custom:
        return customIntervalMonths ?? 1;
    }
  }

  String get periodText {
    switch (period) {
      case ExpensePeriod.once:
        return 'один раз';
      case ExpensePeriod.monthly:
        return 'каждый месяц';
      case ExpensePeriod.yearly:
        return 'каждый год';
      case ExpensePeriod.custom:
        final months = customIntervalMonths ?? 1;
        final word = months == 1
            ? 'месяц'
            : (months >= 2 && months <= 4 ? 'месяца' : 'месяцев');
        return 'каждые $months $word';
    }
  }

  MandatoryExpense copyWith({
    String? id,
    String? name,
    double? amount,
    DateTime? dueDate,
    ExpensePeriod? period,
    int? customIntervalMonths,
    bool? isVariableAmount,
    String? comment,
    bool? isPaid,
    String? accountId,
    String? category,
    String? subcategory,
    bool clearCategory = false,
    List<ReserveEntry>? reserveLog,
    String? reserveAccountId,
  }) {
    return MandatoryExpense(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      period: period ?? this.period,
      customIntervalMonths:
          customIntervalMonths ?? this.customIntervalMonths,
      isVariableAmount: isVariableAmount ?? this.isVariableAmount,
      comment: comment ?? this.comment,
      isPaid: isPaid ?? this.isPaid,
      accountId: accountId ?? this.accountId,
      category: clearCategory ? null : (category ?? this.category),
      subcategory: clearCategory ? null : (subcategory ?? this.subcategory),
      reserveLog: reserveLog ?? this.reserveLog,
      reserveAccountId: reserveAccountId ?? this.reserveAccountId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'dueDate': dueDate.toIso8601String(),
      'period': period.name,
      'customIntervalMonths': customIntervalMonths,
      'isVariableAmount': isVariableAmount,
      'comment': comment,
      'isPaid': isPaid,
      'accountId': accountId,
      'category': category,
      'subcategory': subcategory,
      'reserveLog': reserveLog.map((entry) => entry.toJson()).toList(),
      'reserveAccountId': reserveAccountId,
    };
  }

  factory MandatoryExpense.fromJson(Map<String, dynamic> json) {
    return MandatoryExpense(
      id: json['id'] as String,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      dueDate: DateTime.parse(json['dueDate'] as String),
      period: ExpensePeriod.values.byName(json['period'] as String),
      customIntervalMonths: json['customIntervalMonths'] as int?,
      isVariableAmount: json['isVariableAmount'] as bool? ?? false,
      comment: json['comment'] as String? ?? '',
      isPaid: json['isPaid'] as bool? ?? false,
      accountId: json['accountId'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      reserveLog: (json['reserveLog'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ReserveEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      reserveAccountId: json['reserveAccountId'] as String?,
    );
  }
}
