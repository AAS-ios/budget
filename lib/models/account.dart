import '../utils/format.dart';

enum AccountType {
  debitCard,
  savings,
  deposit,
  cash,
}

extension AccountTypeTitle on AccountType {
  String get title {
    switch (this) {
      case AccountType.debitCard:
        return 'Расходный счёт';
      case AccountType.savings:
        return 'Накопительный счёт';
      case AccountType.deposit:
        return 'Вклад';
      case AccountType.cash:
        return 'Наличные';
    }
  }

  /// Пояснение при выборе типа.
  String get hint {
    switch (this) {
      case AccountType.debitCard:
        return 'Карта или счёт для повседневных расходов';
      case AccountType.savings:
        return 'Учитывается отдельно, но деньги можно снять';
      case AccountType.deposit:
        return 'Вложенные деньги: не входят в свободные, на них '
            'начисляются проценты';
      case AccountType.cash:
        return 'Деньги в кошельке';
    }
  }

  /// Заголовок группы на экране счетов.
  String get groupTitle {
    switch (this) {
      case AccountType.debitCard:
        return 'Расходные счета';
      case AccountType.savings:
        return 'Накопления';
      case AccountType.deposit:
        return 'Вклады';
      case AccountType.cash:
        return 'Наличные';
    }
  }
}

/// Как часто начисляются проценты по вкладу.
enum InterestPeriod {
  monthly,
  quarterly,
  yearly,
  atEnd,
}

extension InterestPeriodTitle on InterestPeriod {
  String get title {
    switch (this) {
      case InterestPeriod.monthly:
        return 'Каждый месяц';
      case InterestPeriod.quarterly:
        return 'Раз в квартал';
      case InterestPeriod.yearly:
        return 'Раз в год';
      case InterestPeriod.atEnd:
        return 'В конце срока';
    }
  }

  /// Шаг в месяцах. 0 — только в конце срока.
  int get months {
    switch (this) {
      case InterestPeriod.monthly:
        return 1;
      case InterestPeriod.quarterly:
        return 3;
      case InterestPeriod.yearly:
        return 12;
      case InterestPeriod.atEnd:
        return 0;
    }
  }
}

/// Условия вклада.
class DepositInfo {
  final String bank;

  /// Сколько было внесено при открытии.
  final double initialAmount;

  /// Процентная ставка, % годовых.
  final double rate;

  /// Дата окончания (null — бессрочный).
  final DateTime? endDate;

  final InterestPeriod period;

  /// Число месяца, когда начисляются проценты.
  final int payoutDay;

  /// true — проценты прибавляются к вкладу.
  final bool capitalization;

  final bool canTopUp;
  final bool canWithdraw;

  /// Куда приходят проценты без капитализации.
  final String? interestAccountId;

  /// До какой даты (включительно) проценты уже начислены.
  final DateTime lastAccrualDate;

  const DepositInfo({
    this.bank = '',
    required this.initialAmount,
    required this.rate,
    this.endDate,
    this.period = InterestPeriod.monthly,
    required this.payoutDay,
    this.capitalization = true,
    this.canTopUp = true,
    this.canWithdraw = false,
    this.interestAccountId,
    required this.lastAccrualDate,
  });

  DepositInfo copyWith({
    String? bank,
    double? initialAmount,
    double? rate,
    DateTime? endDate,
    bool clearEndDate = false,
    InterestPeriod? period,
    int? payoutDay,
    bool? capitalization,
    bool? canTopUp,
    bool? canWithdraw,
    String? interestAccountId,
    bool clearInterestAccount = false,
    DateTime? lastAccrualDate,
  }) {
    return DepositInfo(
      bank: bank ?? this.bank,
      initialAmount: initialAmount ?? this.initialAmount,
      rate: rate ?? this.rate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      period: period ?? this.period,
      payoutDay: payoutDay ?? this.payoutDay,
      capitalization: capitalization ?? this.capitalization,
      canTopUp: canTopUp ?? this.canTopUp,
      canWithdraw: canWithdraw ?? this.canWithdraw,
      interestAccountId: clearInterestAccount
          ? null
          : (interestAccountId ?? this.interestAccountId),
      lastAccrualDate: lastAccrualDate ?? this.lastAccrualDate,
    );
  }

  /// Ближайшая дата начисления после [after].
  /// null — начислений больше не будет.
  DateTime? nextPayoutAfter(DateTime after, DateTime openDate) {
    final last = dateOnly(after);
    final end = endDate == null ? null : dateOnly(endDate!);

    if (end != null && !end.isAfter(last)) {
      return null;
    }

    if (period == InterestPeriod.atEnd) {
      return end;
    }

    final step = period.months;
    final start = DateTime(openDate.year, openDate.month);

    // Пропускаем заведомо прошедшие периоды.
    var k = ((monthIndex(last) - monthIndex(start)) ~/ step) - 1;
    if (k < 0) {
      k = 0;
    }

    while (true) {
      final candidate = withDay(addMonths(start, k * step), payoutDay);

      if (candidate.isAfter(last) && candidate.isAfter(dateOnly(openDate))) {
        if (end != null && candidate.isAfter(end)) {
          return end;
        }
        return candidate;
      }

      k++;
    }
  }

  /// Последняя дата начисления не позже [date] (или дата открытия).
  DateTime lastPayoutOnOrBefore(DateTime date, DateTime openDate) {
    var current = dateOnly(openDate);

    while (true) {
      final next = nextPayoutAfter(current, openDate);

      if (next == null || next.isAfter(dateOnly(date))) {
        return current;
      }

      current = next;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'bank': bank,
      'initialAmount': initialAmount,
      'rate': rate,
      'endDate': endDate?.toIso8601String(),
      'period': period.name,
      'payoutDay': payoutDay,
      'capitalization': capitalization,
      'canTopUp': canTopUp,
      'canWithdraw': canWithdraw,
      'interestAccountId': interestAccountId,
      'lastAccrualDate': lastAccrualDate.toIso8601String(),
    };
  }

  factory DepositInfo.fromJson(Map<String, dynamic> json) {
    final endDate = json['endDate'] as String?;
    final period = json['period'] as String?;

    return DepositInfo(
      bank: json['bank'] as String? ?? '',
      initialAmount: (json['initialAmount'] as num? ?? 0).toDouble(),
      rate: (json['rate'] as num? ?? 0).toDouble(),
      endDate: endDate == null ? null : DateTime.parse(endDate),
      period: period == null
          ? InterestPeriod.monthly
          : InterestPeriod.values.byName(period),
      payoutDay: json['payoutDay'] as int? ?? 1,
      capitalization: json['capitalization'] as bool? ?? true,
      canTopUp: json['canTopUp'] as bool? ?? true,
      canWithdraw: json['canWithdraw'] as bool? ?? false,
      interestAccountId: json['interestAccountId'] as String?,
      lastAccrualDate: DateTime.parse(json['lastAccrualDate'] as String),
    );
  }
}

class Account {
  final String id;
  final String name;
  final AccountType type;
  double balance;
  final bool includeInAvailableMoney;

  /// Код валюты: RUB, USD, EUR, CNY.
  final String currency;

  final DateTime? openDate;
  final String comment;
  final bool isClosed;

  /// Условия вклада (только для типа «Вклад»).
  final DepositInfo? deposit;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.includeInAvailableMoney,
    this.currency = 'RUB',
    this.openDate,
    this.comment = '',
    this.isClosed = false,
    this.deposit,
  });

  bool get isRub => currency == 'RUB';

  /// Счёт участвует в общих суммах (открыт и в рублях).
  bool get countsInTotals => !isClosed && isRub;

  bool get isDeposit => type == AccountType.deposit && deposit != null;

  String money(double amount) => formatMoney(amount, currency: currency);

  Account copyWith({
    String? name,
    AccountType? type,
    double? balance,
    bool? includeInAvailableMoney,
    String? currency,
    DateTime? openDate,
    String? comment,
    bool? isClosed,
    DepositInfo? deposit,
    bool clearDeposit = false,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      includeInAvailableMoney:
          includeInAvailableMoney ?? this.includeInAvailableMoney,
      currency: currency ?? this.currency,
      openDate: openDate ?? this.openDate,
      comment: comment ?? this.comment,
      isClosed: isClosed ?? this.isClosed,
      deposit: clearDeposit ? null : (deposit ?? this.deposit),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'balance': balance,
      'includeInAvailableMoney': includeInAvailableMoney,
      'currency': currency,
      'openDate': openDate?.toIso8601String(),
      'comment': comment,
      'isClosed': isClosed,
      'deposit': deposit?.toJson(),
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    final openDate = json['openDate'] as String?;
    final deposit = json['deposit'];

    return Account(
      id: json['id'] as String,
      name: json['name'] as String,
      type: AccountType.values.byName(json['type'] as String),
      balance: (json['balance'] as num).toDouble(),
      includeInAvailableMoney:
          json['includeInAvailableMoney'] as bool? ?? true,
      currency: json['currency'] as String? ?? 'RUB',
      openDate: openDate == null ? null : DateTime.parse(openDate),
      comment: json['comment'] as String? ?? '',
      isClosed: json['isClosed'] as bool? ?? false,
      deposit: deposit is Map
          ? DepositInfo.fromJson(Map<String, dynamic>.from(deposit))
          : null,
    );
  }
}
