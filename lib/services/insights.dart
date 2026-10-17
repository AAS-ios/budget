import '../models/account.dart';
import '../models/mandatory_expense.dart';
import '../models/mandatory_expense_store.dart';
import '../models/transaction.dart';
import '../utils/format.dart';
import 'app_data.dart';

/// Итоги месяца.
class MonthSummary {
  final DateTime month;

  /// Доходы без процентов по вкладам.
  final double income;
  final double interest;
  final double expense;

  /// Сколько переведено с расходных счетов в накопления и вклады.
  final double savings;

  const MonthSummary({
    required this.month,
    required this.income,
    required this.interest,
    required this.expense,
    required this.savings,
  });

  double get remainder => income - expense - savings;
}

/// Сумма по категории с разбивкой по подкатегориям.
class CategoryTotal {
  final String name;
  double total = 0;
  final Map<String, double> subs = {};

  CategoryTotal(this.name);

  List<MapEntry<String, double>> get sortedSubs =>
      subs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Расход, который повторяется из месяца в месяц.
class RecurringItem {
  final String title;
  final String? category;
  final String? subcategory;
  final double averageMonthly;
  final int monthsSeen;
  final int monthsChecked;
  final double averageCount;
  final int typicalDay;

  const RecurringItem({
    required this.title,
    this.category,
    this.subcategory,
    required this.averageMonthly,
    required this.monthsSeen,
    required this.monthsChecked,
    required this.averageCount,
    required this.typicalDay,
  });

  /// Похоже на регулярный платёж (раз в месяц), а не на частые покупки.
  bool get looksLikePayment => averageCount <= 1.5;
}

class DepositStats {
  final Account account;
  final double deposited;
  final double interestTotal;
  final double interestThisMonth;
  final double interestThisYear;

  /// Фактическая доходность, % годовых.
  final double? effectiveYield;
  final ({DateTime date, double amount})? nextPayout;

  /// Прогноз к концу срока (или через год для бессрочных).
  final DepositProjection projection;
  final DateTime projectionDate;

  const DepositStats({
    required this.account,
    required this.deposited,
    required this.interestTotal,
    required this.interestThisMonth,
    required this.interestThisYear,
    required this.effectiveYield,
    required this.nextPayout,
    required this.projection,
    required this.projectionDate,
  });
}

class ForecastPoint {
  final int months;
  final DateTime date;
  final double available;
  final double savings;
  final double deposits;
  final double depositInterest;
  final double incomes;
  final double mandatory;
  final double spending;

  const ForecastPoint({
    required this.months,
    required this.date,
    required this.available,
    required this.savings,
    required this.deposits,
    required this.depositInterest,
    required this.incomes,
    required this.mandatory,
    required this.spending,
  });

  double get capital => available + savings + deposits;
}

enum EventKind {
  payment,
  income,
  interest,
  goal,
  depositEnd,
  pastIncome,
  pastExpense,
}

/// Событие финансового календаря.
class FinEvent {
  final DateTime date;
  final String title;
  final double? amount;
  final EventKind kind;
  final bool overdue;

  const FinEvent({
    required this.date,
    required this.title,
    this.amount,
    required this.kind,
    this.overdue = false,
  });

  bool get isIncoming =>
      kind == EventKind.income ||
      kind == EventKind.interest ||
      kind == EventKind.pastIncome;
}

enum WarningLevel {
  danger,
  warning,
  info,
}

class FinWarning {
  final WarningLevel level;
  final String text;

  const FinWarning(this.level, this.text);
}

/// Аналитика, прогноз, календарь и предупреждения.
///
/// Только чтение: ничего не меняет в данных.
class Insights {
  final AppData data;
  final DateTime now;

  Insights(this.data, DateTime now) : now = dateOnly(now);

  List<Transaction> get _all => data.transactions.transactions;

  // ─────────────────────────────
  // ИСТОРИЯ
  // ─────────────────────────────

  DateTime? get firstDate {
    final list = _all
        .where((t) => t.type != TransactionType.adjustment && !t.isInterest);
    if (list.isEmpty) {
      return null;
    }
    return dateOnly(list.last.date);
  }

  /// Сколько месяцев истории (включая текущий).
  int get historyMonths {
    final first = firstDate;
    if (first == null) {
      return 0;
    }
    return monthIndex(now) - monthIndex(first) + 1;
  }

  /// Полные прошедшие месяцы с данными (от старых к новым).
  List<DateTime> get fullMonths {
    final first = firstDate;
    if (first == null) {
      return const [];
    }
    final result = <DateTime>[];
    var month = DateTime(first.year, first.month);
    final current = DateTime(now.year, now.month);
    while (month.isBefore(current)) {
      result.add(month);
      month = addMonths(month, 1);
    }
    return result;
  }

  /// Пояснение о том, насколько можно доверять аналитике.
  String get maturityText {
    final months = historyMonths;
    if (months == 0) {
      return 'Операций пока нет. Аналитика появится, когда вы начнёте '
          'записывать доходы и расходы.';
    }
    if (months < 3) {
      return 'История: $months ${plural(months, 'месяц', 'месяца', 'месяцев')}. '
          'Недостаточно данных для долгосрочного анализа — '
          'пока видны только итоги месяцев.';
    }
    if (months < 6) {
      return 'История: $months ${plural(months, 'месяц', 'месяца', 'месяцев')}. '
          'Уже видны основные тенденции. Полная аналитика — '
          'после 6 месяцев.';
    }
    return 'История: $months ${plural(months, 'месяц', 'месяца', 'месяцев')}. '
        'Данных достаточно для полноценной аналитики.';
  }

  // ─────────────────────────────
  // ИТОГИ МЕСЯЦЕВ
  // ─────────────────────────────

  bool _isEveryday(String? id) {
    final type = data.accounts.getById(id)?.type;
    return type == AccountType.debitCard || type == AccountType.cash;
  }

  bool _isSavingsType(String? id) {
    final type = data.accounts.getById(id)?.type;
    return type == AccountType.savings || type == AccountType.deposit;
  }

  /// Перевод в накопления (+) или из них (−).
  double _savingsEffect(Transaction t) {
    if (t.type != TransactionType.transfer) {
      return 0;
    }
    if (_isEveryday(t.accountId) && _isSavingsType(t.destinationAccountId)) {
      return t.amount;
    }
    if (_isSavingsType(t.accountId) && _isEveryday(t.destinationAccountId)) {
      return -t.amount;
    }
    return 0;
  }

  MonthSummary month(int year, int month) {
    var income = 0.0;
    var interest = 0.0;
    var expense = 0.0;
    var savings = 0.0;

    for (final t in data.transactions.forMonth(year, month)) {
      switch (t.type) {
        case TransactionType.income:
          if (t.isInterest) {
            interest += t.amount;
          } else {
            income += t.amount;
          }
        case TransactionType.expense:
          expense += t.amount;
        case TransactionType.transfer:
          savings += _savingsEffect(t);
        case TransactionType.adjustment:
          break;
      }
    }

    return MonthSummary(
      month: DateTime(year, month),
      income: roundMoney(income),
      interest: roundMoney(interest),
      expense: roundMoney(expense),
      savings: roundMoney(savings),
    );
  }

  /// Итоги последних [count] месяцев, включая текущий (от старых к новым).
  List<MonthSummary> lastMonths(int count) {
    return List.generate(count, (index) {
      final m = addMonths(DateTime(now.year, now.month), index - count + 1);
      return month(m.year, m.month);
    });
  }

  // ─────────────────────────────
  // КУДА УХОДЯТ ДЕНЬГИ
  // ─────────────────────────────

  List<Transaction> expensesBetween(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final end = dateOnly(to);
    return _all.where((t) {
      final day = dateOnly(t.date);
      return t.type == TransactionType.expense &&
          !day.isBefore(start) &&
          !day.isAfter(end);
    }).toList();
  }

  /// Расходы по категориям за период, от больших к меньшим.
  List<CategoryTotal> byCategory(DateTime from, DateTime to) {
    final result = <String, CategoryTotal>{};

    for (final t in expensesBetween(from, to)) {
      final name = t.category ?? 'Без категории';
      final total = result.putIfAbsent(name, () => CategoryTotal(name));
      total.total += t.amount;
      final sub = t.subcategory;
      if (sub != null && sub.isNotEmpty) {
        total.subs[sub] = (total.subs[sub] ?? 0) + t.amount;
      }
    }

    return result.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Начало периода «последние N месяцев» (включая текущий).
  DateTime periodStart(int months) =>
      addMonths(DateTime(now.year, now.month), -(months - 1));

  // ─────────────────────────────
  // СРАВНЕНИЕ МЕСЯЦЕВ
  // ─────────────────────────────

  /// Суммы по категориям за месяц.
  Map<String, double> categoryTotalsForMonth(DateTime month) {
    final result = <String, double>{};
    for (final t in data.transactions.expensesForMonth(month.year, month.month)) {
      final name = t.category ?? 'Без категории';
      result[name] = (result[name] ?? 0) + t.amount;
    }
    return result;
  }

  /// Месяцы для сравнения: последние 3 (текущий — если в нём есть траты).
  List<DateTime> get comparisonMonths {
    final current = DateTime(now.year, now.month);
    return List.generate(3, (i) => addMonths(current, i - 2));
  }

  /// Описания изменений между двумя последними полными месяцами.
  List<String> comparisonTexts() {
    final full = fullMonths;
    if (full.length < 2) {
      return const [];
    }

    final last = full.last;
    final previous = full[full.length - 2];
    final a = categoryTotalsForMonth(previous);
    final b = categoryTotalsForMonth(last);
    final texts = <({double weight, String text})>[];

    for (final name in {...a.keys, ...b.keys}) {
      final before = a[name] ?? 0;
      final after = b[name] ?? 0;
      if (before < 300 || after <= 0) {
        continue;
      }
      final percent = ((after - before) / before * 100).round();
      if (percent.abs() < 10) {
        continue;
      }
      final more = percent > 0;
      texts.add((
        weight: (after - before).abs(),
        text: 'На «$name» в ${_monthPrepositional(last.month)} потрачено '
            'на ${percent.abs()}% ${more ? 'больше' : 'меньше'}, '
            'чем в ${_monthPrepositional(previous.month)}.',
      ));
    }

    texts.sort((x, y) => y.weight.compareTo(x.weight));
    return texts.take(5).map((item) => item.text).toList();
  }

  static const _prepositional = [
    'январе',
    'феврале',
    'марте',
    'апреле',
    'мае',
    'июне',
    'июле',
    'августе',
    'сентябре',
    'октябре',
    'ноябре',
    'декабре',
  ];

  String _monthPrepositional(int month) => _prepositional[month - 1];

  // ─────────────────────────────
  // СРЕДНИЕ
  // ─────────────────────────────

  /// Месяцы для расчёта средних: полные, а если их нет — текущий.
  List<DateTime> get _averageMonths {
    final full = fullMonths;
    if (full.isNotEmpty) {
      return full.length > 12 ? full.sublist(full.length - 12) : full;
    }
    return [DateTime(now.year, now.month)];
  }

  double averageMonthlyExpense() {
    final months = _averageMonths;
    final sum = months.fold(
      0.0,
      (s, m) => s + data.transactions.expensesAmountForMonth(m.year, m.month),
    );
    return roundMoney(sum / months.length);
  }

  /// Средние траты без обязательных платежей (для прогноза и лимита).
  double averageMonthlyVariable() {
    final full = fullMonths;
    if (full.isEmpty) {
      // Экстраполируем текущий месяц.
      final spent = data.transactions
          .expensesForMonth(now.year, now.month)
          .where((t) => !t.isMandatoryPayment)
          .fold(0.0, (s, t) => s + t.amount);
      if (now.day < 3) {
        return 0;
      }
      return roundMoney(spent / now.day * endOfMonth(now).day);
    }
    final months = full.length > 3 ? full.sublist(full.length - 3) : full;
    final sum = months.fold(
      0.0,
      (s, m) =>
          s +
          data.transactions
              .expensesForMonth(m.year, m.month)
              .where((t) => !t.isMandatoryPayment)
              .fold(0.0, (x, t) => x + t.amount),
    );
    return roundMoney(sum / months.length);
  }

  double averageDailyExpense() {
    final months = _averageMonths;
    var days = 0;
    var sum = 0.0;
    for (final m in months) {
      final isCurrent = m.year == now.year && m.month == now.month;
      days += isCurrent ? now.day : endOfMonth(m).day;
      sum += data.transactions.expensesAmountForMonth(m.year, m.month);
    }
    return days == 0 ? 0 : roundMoney(sum / days);
  }

  /// Средний чек: средняя сумма обычной покупки.
  double averageCheck() {
    final list = _all
        .where((t) => t.type == TransactionType.expense && !t.isMandatoryPayment);
    if (list.isEmpty) {
      return 0;
    }
    return roundMoney(list.fold(0.0, (s, t) => s + t.amount) / list.length);
  }

  /// Средние расходы по категориям в месяц.
  List<MapEntry<String, double>> averageByCategory() {
    final months = _averageMonths;
    final totals = <String, double>{};
    for (final m in months) {
      categoryTotalsForMonth(m).forEach((name, value) {
        totals[name] = (totals[name] ?? 0) + value;
      });
    }
    return totals.entries
        .map((e) => MapEntry(e.key, roundMoney(e.value / months.length)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Месяц с минимальными и максимальными расходами (среди полных).
  ({MonthSummary min, MonthSummary max})? minMaxMonth() {
    final full = fullMonths;
    if (full.length < 2) {
      return null;
    }
    final summaries = full.map((m) => month(m.year, m.month)).toList();
    summaries.sort((a, b) => a.expense.compareTo(b.expense));
    return (min: summaries.first, max: summaries.last);
  }

  // ─────────────────────────────
  // ПОВТОРЯЮЩИЕСЯ РАСХОДЫ
  // ─────────────────────────────

  List<RecurringItem> recurring() {
    final full = fullMonths;
    final months = full.length > 6 ? full.sublist(full.length - 6) : full;

    if (months.length < 2) {
      return const [];
    }

    final minSeen = months.length <= 3 ? months.length : 3;

    // Группы: по комментарию (подписки и т.п.) и по категории.
    final groups = <String, List<Transaction>>{};
    final firstMonth = months.first;
    final lastMonth = months.last;

    for (final t in _all) {
      if (t.type != TransactionType.expense || t.isMandatoryPayment) {
        continue;
      }
      final m = DateTime(t.date.year, t.date.month);
      if (m.isBefore(firstMonth) || m.isAfter(lastMonth)) {
        continue;
      }
      final comment = t.comment.trim().toLowerCase();
      if (comment.isNotEmpty) {
        groups.putIfAbsent('c:$comment', () => []).add(t);
      }
      groups.putIfAbsent('k:${t.categoryLabel}', () => []).add(t);
    }

    final result = <RecurringItem>[];
    final mandatoryNames =
        data.mandatory.expenses.map((e) => e.name.toLowerCase()).toSet();

    groups.forEach((key, list) {
      final byMonth = <int, List<Transaction>>{};
      for (final t in list) {
        byMonth.putIfAbsent(monthIndex(t.date), () => []).add(t);
      }
      if (byMonth.length < minSeen) {
        return;
      }

      final total = list.fold(0.0, (s, t) => s + t.amount);
      final days = list.map((t) => t.date.day).toList()..sort();
      final sample = list.first;
      final isComment = key.startsWith('c:');
      final title = isComment ? sample.comment.trim() : sample.categoryLabel;

      if (mandatoryNames.contains(title.toLowerCase())) {
        return;
      }

      result.add(
        RecurringItem(
          title: title,
          category: sample.category,
          subcategory: sample.subcategory,
          averageMonthly: roundMoney(total / byMonth.length),
          monthsSeen: byMonth.length,
          monthsChecked: months.length,
          averageCount: list.length / byMonth.length,
          typicalDay: days[days.length ~/ 2],
        ),
      );
    });

    // Платежи «раз в месяц» — сначала, потом крупные траты.
    result.sort((a, b) {
      if (a.looksLikePayment != b.looksLikePayment) {
        return a.looksLikePayment ? -1 : 1;
      }
      return b.averageMonthly.compareTo(a.averageMonthly);
    });

    return result;
  }

  // ─────────────────────────────
  // ПРИВЫЧКИ
  // ─────────────────────────────

  /// Закономерности в тратах. Только цифры, без оценок.
  List<String> habits() {
    if (historyMonths < 3) {
      return const [];
    }

    final texts = <String>[];
    final months = historyMonths >= 6 ? 6 : historyMonths;
    final from = periodStart(months);
    final totals = byCategory(from, now);
    final sum = totals.fold(0.0, (s, c) => s + c.total);

    if (sum > 0 && totals.isNotEmpty) {
      final top = totals.first;
      texts.add(
        'За последние $months ${plural(months, 'месяц', 'месяца', 'месяцев')} '
        '${(top.total / sum * 100).round()}% расходов приходится '
        'на «${top.name}».',
      );
      final topSub = top.sortedSubs;
      if (topSub.isNotEmpty) {
        texts.add(
          'Внутри «${top.name}» больше всего уходит на «${topSub.first.key}»: '
          '${formatMoneyRound(topSub.first.value / months)} в месяц в среднем.',
        );
      }
    }

    // Рост и снижение относительно предыдущих месяцев.
    final full = fullMonths;
    if (full.length >= 3) {
      final last = full.last;
      final previous = full.sublist(
        full.length > 4 ? full.length - 4 : 0,
        full.length - 1,
      );
      final lastTotals = categoryTotalsForMonth(last);
      final avg = <String, double>{};
      for (final m in previous) {
        categoryTotalsForMonth(m).forEach((k, v) {
          avg[k] = (avg[k] ?? 0) + v / previous.length;
        });
      }
      for (final name in lastTotals.keys) {
        final before = avg[name] ?? 0;
        final after = lastTotals[name]!;
        if (before >= 500 && after > before * 1.25 && after - before > 500) {
          texts.add(
            'Расходы на «$name» выросли относительно предыдущих месяцев: '
            '${formatMoneyRound(after)} в ${_monthPrepositional(last.month)} '
            'против ${formatMoneyRound(before)} в среднем.',
          );
        } else if (before >= 500 && after < before * 0.75) {
          texts.add(
            'Расходы на «$name» снизились: ${formatMoneyRound(after)} '
            'в ${_monthPrepositional(last.month)} против '
            '${formatMoneyRound(before)} в среднем.',
          );
        }
      }
    }

    // Траты в первые 7 дней после зарплаты.
    final salaryDays = _all
        .where(
          (t) =>
              t.type == TransactionType.income &&
              !t.isInterest &&
              (t.incomeSource == 'Зарплата' || t.amount >= 10000),
        )
        .map((t) => dateOnly(t.date))
        .toSet();
    if (salaryDays.length >= 2) {
      var afterSum = 0.0;
      var afterDays = <DateTime>{};
      var otherSum = 0.0;
      final allDays = <DateTime>{};
      for (final t in _all.where(
        (t) => t.type == TransactionType.expense && !t.isMandatoryPayment,
      )) {
        final day = dateOnly(t.date);
        final isAfter = salaryDays.any((s) {
          final diff = daysBetween(s, day);
          return diff >= 0 && diff < 7;
        });
        if (isAfter) {
          afterSum += t.amount;
          afterDays.add(day);
        } else {
          otherSum += t.amount;
        }
        allDays.add(day);
      }
      final first = firstDate!;
      final totalDays = daysBetween(first, now) + 1;
      final afterTotalDays = salaryDays.length * 7;
      final otherDays = totalDays - afterTotalDays;
      if (otherDays > 7 && afterSum > 0) {
        final perDayAfter = afterSum / afterTotalDays;
        final perDayOther = otherSum / otherDays;
        if (perDayOther > 0 && perDayAfter > perDayOther * 1.2) {
          texts.add(
            'В первые 7 дней после получения дохода траты выше: '
            '${formatMoneyRound(perDayAfter)} в день против '
            '${formatMoneyRound(perDayOther)} в остальные дни.',
          );
        }
      }
    }

    // Будни и выходные.
    var weekend = 0.0;
    var weekday = 0.0;
    for (final t in expensesBetween(from, now)) {
      if (t.isMandatoryPayment) {
        continue;
      }
      if (t.date.weekday >= 6) {
        weekend += t.amount;
      } else {
        weekday += t.amount;
      }
    }
    final days = daysBetween(from, now) + 1;
    final weekendDays = (days * 2 / 7).round();
    final weekdayDays = days - weekendDays;
    if (weekendDays > 0 && weekdayDays > 0 && weekday > 0) {
      final we = weekend / weekendDays;
      final wd = weekday / weekdayDays;
      if (we > wd * 1.3) {
        texts.add(
          'В выходные в среднем тратится ${formatMoneyRound(we)} в день, '
          'в будни — ${formatMoneyRound(wd)}.',
        );
      }
    }

    // Покупки «можно было не брать».
    final want = expensesBetween(from, now)
        .where((t) => t.priority == TransactionPriority.want)
        .fold(0.0, (s, t) => s + t.amount);
    if (sum > 0 && want > 0) {
      texts.add(
        'Покупки с отметкой «можно было не брать» — '
        '${(want / sum * 100).round()}% расходов '
        '(${formatMoneyRound(want / months)} в месяц).',
      );
    }

    return texts;
  }

  // ─────────────────────────────
  // НАКОПЛЕНИЯ
  // ─────────────────────────────

  /// Средние накопления в месяц по месяцам, где они были.
  double averageSavings({int months = 6}) {
    final list = lastMonths(months + 1)
        .take(months)
        .where((m) => m.month.isAfter(
              DateTime((firstDate ?? now).year, (firstDate ?? now).month)
                  .subtract(const Duration(days: 1)),
            ))
        .toList();
    if (list.isEmpty) {
      return 0;
    }
    final sum = list.fold(0.0, (s, m) => s + m.savings);
    return roundMoney(sum / list.length);
  }

  // ─────────────────────────────
  // ВКЛАДЫ
  // ─────────────────────────────

  DepositStats depositStats(Account account) {
    final interest = data.interestOf(account.id);
    final interestTracked = interest.fold(0.0, (s, t) => s + t.amount);
    final deposit = account.deposit;

    // Баланс до всех записанных операций.
    final startBalance = roundMoney(
      account.balance - _all.fold(0.0, (s, t) => s + t.effectOn(account.id)),
    );

    // Внесено: начальная сумма + пополнения − снятия (без процентов).
    var movements = 0.0;
    for (final t in _all) {
      if (t.isInterest || t.type == TransactionType.adjustment) {
        continue;
      }
      movements += t.effectOn(account.id);
    }

    final initial = deposit?.initialAmount ?? 0;
    final deposited = roundMoney((initial > 0 ? initial : startBalance) + movements);

    // Проценты, полученные до начала учёта в приложении.
    final earlier = initial > 0 && (deposit?.capitalization ?? false)
        ? (startBalance - initial).clamp(0.0, double.infinity).toDouble()
        : 0.0;
    final interestTotal = roundMoney(interestTracked + earlier);

    final thisMonth = interest
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .fold(0.0, (s, t) => s + t.amount);
    final thisYear = interest
        .where((t) => t.date.year == now.year)
        .fold(0.0, (s, t) => s + t.amount);

    double? yieldPercent;
    final openDate = account.openDate;
    if (openDate != null && deposited > 0) {
      final days = daysBetween(openDate, now);
      if (days >= 28 && interestTotal > 0) {
        yieldPercent = interestTotal / deposited / days * 365 * 100;
      }
    }

    final end = deposit?.endDate;
    final projectionDate = end != null && end.isAfter(now)
        ? dateOnly(end)
        : addMonths(now, 12);

    return DepositStats(
      account: account,
      deposited: deposited,
      interestTotal: interestTotal,
      interestThisMonth: roundMoney(thisMonth),
      interestThisYear: roundMoney(thisYear),
      effectiveYield: yieldPercent,
      nextPayout: data.nextInterest(account),
      projection: data.projectDeposit(account, projectionDate),
      projectionDate: projectionDate,
    );
  }

  List<Account> get deposits => data.accounts.accounts
      .where((a) => a.type == AccountType.deposit && !a.isClosed)
      .toList();

  /// Проценты по всем вкладам за текущий месяц.
  double interestThisMonth() {
    return roundMoney(
      _all
          .where(
            (t) =>
                t.isInterest &&
                t.date.year == now.year &&
                t.date.month == now.month,
          )
          .fold(0.0, (s, t) => s + t.amount),
    );
  }

  // ─────────────────────────────
  // ПРОГНОЗ
  // ─────────────────────────────

  ForecastPoint forecast(int months) {
    final end = addMonths(now, months);
    final tomorrow = now.add(const Duration(days: 1));

    var incomes = 0.0;
    for (final income in data.plannedIncomes.items) {
      incomes += income.occurrences(tomorrow, end).length * income.amount;
    }

    var mandatoryTotal = 0.0;
    for (final item in data.dueUntil(now, end)) {
      mandatoryTotal += item.expense.amount;
    }

    final days = daysBetween(now, end);
    final spentThisMonth = data.transactions
        .expensesForMonth(now.year, now.month)
        .where((t) => !t.isMandatoryPayment)
        .fold(0.0, (s, t) => s + t.amount);
    final monthlyVariable = averageMonthlyVariable();
    // Из текущего месяца вычитаем то, что уже потрачено.
    final restOfMonth = (monthlyVariable - spentThisMonth)
        .clamp(0.0, double.infinity)
        .toDouble();
    final restDays = daysBetween(now, endOfMonth(now));
    final spending = days <= restDays
        ? restOfMonth * days / (restDays == 0 ? 1 : restDays)
        : restOfMonth + monthlyVariable * (days - restDays) / 30.44;

    // Плановые отложения на цели с отдельных счетов уходят в накопления.
    var toSavings = 0.0;
    for (final goal in data.goals.active) {
      if (goal.accountId != null && !data.isAvailableAccount(goal.accountId)) {
        toSavings += goal.monthlyNeed(now) * months;
      }
    }

    var deposits = 0.0;
    var depositInterest = 0.0;
    for (final account in data.accounts.accounts) {
      if (account.type != AccountType.deposit || !account.countsInTotals) {
        continue;
      }
      final projection = data.projectDeposit(account, end);
      deposits += projection.balance;
      depositInterest += projection.interest;
    }

    // Наличные + карты + накопительные, которые входят в доступные.
    final available = data.accounts.availableMoney +
        incomes -
        mandatoryTotal -
        spending -
        toSavings;

    final savingsNow = data.accounts.totalMoney -
        data.accounts.availableMoney -
        data.accounts.depositMoney;

    return ForecastPoint(
      months: months,
      date: end,
      available: roundMoney(available),
      savings: roundMoney(savingsNow + toSavings),
      deposits: roundMoney(deposits),
      depositInterest: roundMoney(depositInterest),
      incomes: roundMoney(incomes),
      mandatory: roundMoney(mandatoryTotal),
      spending: roundMoney(spending),
    );
  }

  /// Сколько примерно останется к концу месяца при текущем темпе.
  double? endOfMonthEstimate() {
    final end = endOfMonth(now);
    final daysLeft = daysBetween(now, end) + 1;

    final spentThisMonth = data.transactions
        .expensesForMonth(now.year, now.month)
        .where((t) => !t.isMandatoryPayment && data.isAvailableAccount(t.accountId))
        .fold(0.0, (s, t) => s + t.amount);

    double perDay;
    if (now.day >= 5) {
      perDay = spentThisMonth / now.day;
    } else {
      final avg = averageMonthlyVariable();
      if (avg <= 0) {
        return null;
      }
      perDay = avg / 30.44;
    }

    var incomes = 0.0;
    for (final income in data.plannedIncomes.items) {
      incomes += income.occurrences(now.add(const Duration(days: 1)), end).length *
          income.amount;
    }

    final mandatoryDue =
        data.dueUntil(now, end).fold(0.0, (s, i) => s + i.expense.amount);

    return roundMoney(
      data.accounts.availableMoney +
          incomes -
          mandatoryDue -
          perDay * daysLeft,
    );
  }

  // ─────────────────────────────
  // КАЛЕНДАРЬ
  // ─────────────────────────────

  /// События с [from] по [to]: прошлое — фактические операции,
  /// будущее — платежи, доходы, проценты, сроки целей и вкладов.
  List<FinEvent> events(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final end = dateOnly(to);
    final result = <FinEvent>[];

    // Прошлое и сегодня: операции.
    for (final t in _all) {
      final day = dateOnly(t.date);
      if (day.isBefore(start) || day.isAfter(end) || day.isAfter(now)) {
        continue;
      }
      if (t.type == TransactionType.income) {
        result.add(FinEvent(
          date: day,
          title: t.isInterest ? 'Проценты · ${t.comment}' : t.title,
          amount: t.amount,
          kind: EventKind.pastIncome,
        ));
      } else if (t.type == TransactionType.expense) {
        result.add(FinEvent(
          date: day,
          title: t.title,
          amount: t.amount,
          kind: EventKind.pastExpense,
        ));
      }
    }

    // Будущее (с сегодняшнего дня).
    final futureStart = start.isBefore(now) ? now : start;
    if (!futureStart.isAfter(end)) {
      for (final expense in data.mandatory.unpaidExpenses) {
        final overdue = dateOnly(expense.dueDate).isBefore(now);
        if (overdue && !now.isBefore(start) && !now.isAfter(end)) {
          result.add(FinEvent(
            date: now,
            title: '${expense.name} (просрочен)',
            amount: expense.amount,
            kind: EventKind.payment,
            overdue: true,
          ));
        }
        for (final date in MandatoryExpenseStore.occurrences(
          expense,
          futureStart,
          end,
        )) {
          result.add(FinEvent(
            date: date,
            title: expense.name,
            amount: expense.amount,
            kind: EventKind.payment,
          ));
        }
      }

      for (final income in data.plannedIncomes.items) {
        for (final date in income.occurrences(futureStart, end)) {
          result.add(FinEvent(
            date: date,
            title: income.name,
            amount: income.amount,
            kind: EventKind.income,
          ));
        }
      }

      for (final account in deposits) {
        final deposit = account.deposit;
        final openDate = account.openDate;
        if (deposit == null || openDate == null) {
          continue;
        }
        var balance = account.balance;
        var last = deposit.lastAccrualDate;
        var next = deposit.nextPayoutAfter(last, openDate);
        while (next != null && !next.isAfter(end)) {
          final days = daysBetween(last, next);
          final amount = roundMoney(
            balance * deposit.rate / 100 * days / daysInYear(next.year),
          );
          if (deposit.capitalization) {
            balance += amount;
          }
          if (!next.isBefore(futureStart)) {
            result.add(FinEvent(
              date: next,
              title: 'Проценты · ${account.name}',
              amount: amount,
              kind: EventKind.interest,
            ));
          }
          last = next;
          next = deposit.nextPayoutAfter(last, openDate);
        }
        final endDate = deposit.endDate;
        if (endDate != null &&
            !dateOnly(endDate).isBefore(futureStart) &&
            !dateOnly(endDate).isAfter(end)) {
          result.add(FinEvent(
            date: dateOnly(endDate),
            title: 'Окончание вклада «${account.name}»',
            kind: EventKind.depositEnd,
          ));
        }
      }

      for (final goal in data.goals.active) {
        final deadline = goal.deadline;
        if (deadline != null &&
            !dateOnly(deadline).isBefore(futureStart) &&
            !dateOnly(deadline).isAfter(end)) {
          result.add(FinEvent(
            date: dateOnly(deadline),
            title: 'Срок цели «${goal.name}»',
            amount: goal.remaining > 0 ? goal.remaining : null,
            kind: EventKind.goal,
          ));
        }
      }
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  // ─────────────────────────────
  // ПРЕДУПРЕЖДЕНИЯ
  // ─────────────────────────────

  List<FinWarning> warnings() {
    final result = <FinWarning>[];
    final budget = data.budgetFor(now);

    // Просроченные платежи.
    for (final expense in data.mandatory.unpaidExpenses) {
      final days = daysBetween(now, expense.dueDate);
      if (days < 0) {
        result.add(FinWarning(
          WarningLevel.danger,
          'Просрочен платёж «${expense.name}» — ${formatMoney(expense.amount)}.',
        ));
      } else if (days <= 3) {
        final when = days == 0
            ? 'Сегодня'
            : days == 1
                ? 'Завтра'
                : 'Через $days ${plural(days, 'день', 'дня', 'дней')}';
        result.add(FinWarning(
          WarningLevel.warning,
          '$when списание ${formatMoney(expense.amount)} («${expense.name}»).',
        ));
      }
    }

    // Хватит ли денег на счёте для ближайших платежей.
    final week = now.add(const Duration(days: 7));
    final byAccount = <String, List<DueItem>>{};
    for (final item in data.dueUntil(now, week)) {
      final id = item.expense.accountId;
      if (id != null && data.accounts.getById(id) != null) {
        byAccount.putIfAbsent(id, () => []).add(item);
      }
    }
    byAccount.forEach((id, items) {
      final account = data.accounts.getById(id)!;
      final total = items.fold(0.0, (s, i) => s + i.expense.amount);
      if (account.balance + 0.004 < total) {
        final first = items.first;
        final days = daysBetween(now, first.date);
        final when = days <= 0
            ? 'сегодня'
            : 'через $days ${plural(days, 'день', 'дня', 'дней')}';
        result.add(FinWarning(
          WarningLevel.danger,
          'На счёте «${account.name}» ${account.money(account.balance)}, '
          'а $when ${items.length == 1 ? 'ожидается платёж' : 'ожидаются платежи'} '
          '${formatMoney(total)}.',
        ));
      }
    });

    if (budget.free < 0) {
      result.add(FinWarning(
        WarningLevel.danger,
        'Доступных денег не хватает на обязательные платежи и резервы: '
        'не хватает ${formatMoney(-budget.free)}.',
      ));
    }

    // Ожидаемые доходы, которые не отмечены.
    for (final income in data.plannedIncomes.overdue(now)) {
      result.add(FinWarning(
        WarningLevel.info,
        'Ожидался доход «${income.name}» '
        '${formatDayMonth(income.nextDate, now: now)}. '
        'Если он пришёл — отметьте его в разделе «Бюджет».',
      ));
    }

    // Лимиты по категориям.
    for (final category in data.categories.topLevel) {
      final limit = category.monthlyLimit;
      if (limit == null || limit <= 0) {
        continue;
      }
      final spent = data.categorySpent(category.name, now.year, now.month);
      if (spent > limit + 0.004) {
        result.add(FinWarning(
          WarningLevel.warning,
          '«${category.name}»: потрачено ${formatMoney(spent)} при плане '
          '${formatMoney(limit)} — больше на ${formatMoney(spent - limit)}.',
        ));
      } else if (spent >= limit * 0.9 && spent > 0) {
        result.add(FinWarning(
          WarningLevel.info,
          '«${category.name}»: потрачено ${(spent / limit * 100).round()}% '
          'плана на месяц, осталось ${formatMoney(limit - spent)}.',
        ));
      }
    }

    // Вклады, у которых закончился срок.
    for (final account in deposits) {
      final end = account.deposit?.endDate;
      if (end != null && !dateOnly(end).isAfter(now) && account.balance > 0) {
        result.add(FinWarning(
          WarningLevel.info,
          'Срок вклада «${account.name}» закончился '
          '${formatDayMonth(end, now: now)}. Переведите деньги или '
          'продлите вклад в его настройках.',
        ));
      }
    }

    // Прогноз на конец месяца.
    final estimate = endOfMonthEstimate();
    if (estimate != null) {
      result.add(FinWarning(
        estimate < 0 ? WarningLevel.warning : WarningLevel.info,
        estimate < 0
            ? 'Если сохранить текущие расходы, к концу месяца денег не '
                'хватит примерно на ${formatMoneyRound(-estimate)}.'
            : 'Если сохранить текущие расходы, к концу месяца останется '
                'примерно ${formatMoneyRound(estimate)}.',
      ));
    }

    result.sort((a, b) => a.level.index.compareTo(b.level.index));
    return result;
  }

  /// Средняя фактическая сумма редкого платежа и рекомендация.
  String reserveAdvice(MandatoryExpense expense) {
    final months = monthsLeftInclusive(now, expense.dueDate);
    final need = data.reserveMonthlyNeed(expense, now);
    return 'До платежа $months ${plural(months, 'месяц', 'месяца', 'месяцев')}. '
        'Откладывать примерно ${formatMoneyRound(need)} в месяц.';
  }
}
