import 'package:flutter/foundation.dart';

import '../utils/format.dart';

/// Ожидаемый доход: зарплата, аванс, пенсия…
class PlannedIncome {
  final String id;
  final String name;

  /// Ожидаемая сумма.
  final double amount;

  /// Дата ближайшего поступления.
  final DateTime nextDate;

  /// Через сколько месяцев повторяется. 0 — разовый.
  final int intervalMonths;

  /// Счёт, на который приходят деньги.
  final String? accountId;

  /// Источник дохода (по имени, как в операциях).
  final String source;

  /// Основной доход — аванс или зарплата. Только до него
  /// считается дневной бюджет; подработка период не обрывает.
  final bool isMain;

  const PlannedIncome({
    required this.id,
    required this.name,
    required this.amount,
    required this.nextDate,
    this.intervalMonths = 1,
    this.accountId,
    this.source = 'Зарплата',
    this.isMain = true,
  });

  /// Для старых данных без флага: аванс и зарплата — основные.
  static bool guessMain(String name, String source) {
    final text = '$name $source'.toLowerCase();
    return text.contains('зарплат') || text.contains('аванс');
  }

  /// Даты поступлений в промежутке [from]..[to] включительно.
  List<DateTime> occurrences(DateTime from, DateTime to) {
    final result = <DateTime>[];
    final start = dateOnly(from);
    final end = dateOnly(to);
    var date = dateOnly(nextDate);
    var step = 0;

    while (!date.isAfter(end) && step < 500) {
      if (!date.isBefore(start)) {
        result.add(date);
      }
      if (intervalMonths == 0) {
        break;
      }
      step++;
      date = addMonths(dateOnly(nextDate), intervalMonths * step);
    }

    return result;
  }

  PlannedIncome copyWith({
    String? name,
    double? amount,
    DateTime? nextDate,
    int? intervalMonths,
    String? accountId,
    String? source,
    bool? isMain,
  }) {
    return PlannedIncome(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      nextDate: nextDate ?? this.nextDate,
      intervalMonths: intervalMonths ?? this.intervalMonths,
      accountId: accountId ?? this.accountId,
      source: source ?? this.source,
      isMain: isMain ?? this.isMain,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'nextDate': nextDate.toIso8601String(),
        'intervalMonths': intervalMonths,
        'accountId': accountId,
        'source': source,
        'isMain': isMain,
      };

  factory PlannedIncome.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final source = json['source'] as String? ?? 'Зарплата';

    return PlannedIncome(
      id: json['id'] as String,
      name: name,
      amount: (json['amount'] as num).toDouble(),
      nextDate: DateTime.parse(json['nextDate'] as String),
      intervalMonths: json['intervalMonths'] as int? ?? 1,
      accountId: json['accountId'] as String?,
      source: source,
      isMain: json['isMain'] as bool? ?? guessMain(name, source),
    );
  }
}

class PlannedIncomeStore extends ChangeNotifier {
  final List<PlannedIncome> _items = [];

  /// Все ожидаемые доходы по дате.
  List<PlannedIncome> get items {
    return List<PlannedIncome>.of(_items)
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
  }

  void replaceAll(Iterable<PlannedIncome> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() =>
      _items.map((item) => item.toJson()).toList();

  PlannedIncome? getById(String? id) {
    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void add(PlannedIncome item) {
    _items.add(item);
    notifyListeners();
  }

  void update(PlannedIncome item) {
    final index = _items.indexWhere((element) => element.id == item.id);
    if (index == -1) {
      return;
    }
    _items[index] = item;
    notifyListeners();
  }

  void delete(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  /// Ближайшая дата дохода строго после [date].
  /// [mainOnly] — только аванс и зарплата, без подработки.
  DateTime? nextAfter(DateTime date, {bool mainOnly = false}) {
    final day = dateOnly(date);
    DateTime? best;

    for (final item in _items) {
      if (mainOnly && !item.isMain) {
        continue;
      }
      for (final occurrence in item.occurrences(
        day.add(const Duration(days: 1)),
        addMonths(day, 13),
      )) {
        if (best == null || occurrence.isBefore(best)) {
          best = occurrence;
        }
        break;
      }
    }

    return best;
  }

  /// Доходы, которые уже должны были прийти, но не отмечены.
  List<PlannedIncome> overdue(DateTime now) {
    final today = dateOnly(now);
    return items.where((item) => dateOnly(item.nextDate).isBefore(today)).toList();
  }
}
