enum TransactionType {
  expense,
  income,
  transfer,

  /// Исправление баланса. Сумма со знаком: +500 или −500.
  adjustment,
}

enum TransactionPriority {
  necessary,
  need,
  want,
}

extension TransactionPriorityTitle on TransactionPriority {
  String get title {
    switch (this) {
      case TransactionPriority.necessary:
        return 'Необходимо';
      case TransactionPriority.need:
        return 'Нужно';
      case TransactionPriority.want:
        return 'Можно было не брать';
    }
  }

  String get emoji {
    switch (this) {
      case TransactionPriority.necessary:
        return '🔴';
      case TransactionPriority.need:
        return '🟠';
      case TransactionPriority.want:
        return '🔵';
    }
  }

  String get description {
    switch (this) {
      case TransactionPriority.necessary:
        return 'Без этого расхода действительно нельзя обойтись';
      case TransactionPriority.need:
        return 'Полезно и желательно, но можно было отложить';
      case TransactionPriority.want:
        return 'Покупка была скорее желанием';
    }
  }
}

class Transaction {
  final String id;
  final TransactionType type;

  /// Сумма операции в рублях.
  final double amount;

  /// Дата и время операции.
  final DateTime date;

  /// Для расхода — счёт, с которого списали деньги.
  /// Для дохода — счёт, на который пришли деньги.
  /// Для перевода — счёт-источник.
  final String accountId;

  /// Только для перевода.
  /// Счёт, на который переводятся деньги.
  final String? destinationAccountId;

  /// Категория обычного расхода.
  /// Например: продукты, транспорт, образование.
  final String? category;

  /// Подкатегория расхода (необязательно).
  final String? subcategory;

  /// Только для обычного расхода.
  final TransactionPriority? priority;

  /// Источник дохода.
  /// Например: зарплата, подработка, кэшбэк.
  final String? incomeSource;

  /// Комментарий к операции.
  final String comment;

  /// Если операция — оплата обязательного платежа,
  /// здесь ID этого платежа.
  final String? mandatoryExpenseId;

  /// Если это начисление процентов — ID вклада.
  final String? depositInterestFor;

  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.accountId,
    this.destinationAccountId,
    this.category,
    this.subcategory,
    this.priority,
    this.incomeSource,
    this.comment = '',
    this.mandatoryExpenseId,
    this.depositInterestFor,
  });

  bool get isMandatoryPayment => mandatoryExpenseId != null;

  bool get isInterest => depositInterestFor != null;

  /// «Еда · Кафе» или «Еда».
  String get categoryLabel {
    final main = category ?? 'Без категории';

    if (subcategory == null || subcategory!.isEmpty) {
      return main;
    }

    return '$main · $subcategory';
  }

  /// Как операция меняет баланс счёта [accountId].
  double effectOn(String accountId) {
    switch (type) {
      case TransactionType.expense:
        return this.accountId == accountId ? -amount : 0;
      case TransactionType.income:
      case TransactionType.adjustment:
        return this.accountId == accountId ? amount : 0;
      case TransactionType.transfer:
        var effect = 0.0;
        if (this.accountId == accountId) {
          effect -= amount;
        }
        if (destinationAccountId == accountId) {
          effect += amount;
        }
        return effect;
    }
  }

  Transaction copyWith({
    double? amount,
    DateTime? date,
    String? accountId,
    String? category,
    String? subcategory,
    String? comment,
  }) {
    return Transaction(
      id: id,
      type: type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      accountId: accountId ?? this.accountId,
      destinationAccountId: destinationAccountId,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      priority: priority,
      incomeSource: incomeSource,
      comment: comment ?? this.comment,
      mandatoryExpenseId: mandatoryExpenseId,
      depositInterestFor: depositInterestFor,
    );
  }

  /// Заголовок для списков.
  String get title {
    switch (type) {
      case TransactionType.expense:
        if (isMandatoryPayment && comment.isNotEmpty) {
          return comment;
        }
        if (subcategory != null && subcategory!.isNotEmpty) {
          return subcategory!;
        }
        return category ?? 'Расход';
      case TransactionType.income:
        return incomeSource ?? 'Доход';
      case TransactionType.transfer:
        return 'Перевод';
      case TransactionType.adjustment:
        return 'Корректировка баланса';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'date': date.toIso8601String(),
      'accountId': accountId,
      'destinationAccountId': destinationAccountId,
      'category': category,
      'subcategory': subcategory,
      'priority': priority?.name,
      'incomeSource': incomeSource,
      'comment': comment,
      'mandatoryExpenseId': mandatoryExpenseId,
      'depositInterestFor': depositInterestFor,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final priority = json['priority'] as String?;

    return Transaction(
      id: json['id'] as String,
      type: TransactionType.values.byName(json['type'] as String),
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      accountId: json['accountId'] as String,
      destinationAccountId: json['destinationAccountId'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      priority: priority == null
          ? null
          : TransactionPriority.values.byName(priority),
      incomeSource: json['incomeSource'] as String?,
      comment: json['comment'] as String? ?? '',
      mandatoryExpenseId: json['mandatoryExpenseId'] as String?,
      depositInterestFor: json['depositInterestFor'] as String?,
    );
  }
}
