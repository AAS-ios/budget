import 'package:flutter/foundation.dart';

import '../utils/format.dart';
import 'mandatory_expense.dart';

class MandatoryExpenseStore extends ChangeNotifier {
  final List<MandatoryExpense> _expenses = [];

  List<MandatoryExpense> get expenses => List.unmodifiable(_expenses);

  /// Примеры платежей при первом запуске (даты — ближайшие).
  static List<MandatoryExpense> defaults({DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());

    DateTime next(int day) {
      final thisMonth = withDay(today, day);
      return thisMonth.isBefore(today)
          ? withDay(addMonths(DateTime(today.year, today.month), 1), day)
          : thisMonth;
    }

    return [
      MandatoryExpense(
        id: '1',
        name: 'Коммунальные услуги',
        amount: 5000,
        dueDate: next(10),
        period: ExpensePeriod.monthly,
        isVariableAmount: true,
        category: 'Дом',
        subcategory: 'Коммунальные',
      ),
      MandatoryExpense(
        id: '2',
        name: 'Интернет',
        amount: 700,
        dueDate: next(15),
        period: ExpensePeriod.monthly,
        category: 'Дом',
        subcategory: 'Интернет',
      ),
      MandatoryExpense(
        id: '3',
        name: 'Мобильная связь',
        amount: 500,
        dueDate: next(20),
        period: ExpensePeriod.monthly,
        isVariableAmount: true,
        category: 'Связь',
      ),
    ];
  }

  void replaceAll(Iterable<MandatoryExpense> expenses) {
    _expenses
      ..clear()
      ..addAll(expenses);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() {
    return _expenses.map((expense) => expense.toJson()).toList();
  }

  /// Ещё не оплаченные платежи, отсортированные по дате.
  List<MandatoryExpense> get unpaidExpenses {
    return _expenses.where((expense) => !expense.isPaid).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  /// Оплаченные разовые платежи.
  List<MandatoryExpense> get paidExpenses {
    return _expenses.where((expense) => expense.isPaid).toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  }

  /// Неоплаченные платежи со сроком до [date] включительно
  /// (в том числе просроченные).
  List<MandatoryExpense> unpaidUntil(DateTime date) {
    final limit = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return unpaidExpenses
        .where((expense) => !expense.dueDate.isAfter(limit))
        .toList();
  }

  /// Все даты платежа [expense] в промежутке [from]..[to] включительно
  /// (с учётом повторов). При [includeOverdue] просроченный платёж
  /// попадает в дату [from].
  static List<DateTime> occurrences(
    MandatoryExpense expense,
    DateTime from,
    DateTime to, {
    bool includeOverdue = false,
  }) {
    if (expense.isPaid) {
      return const [];
    }

    final result = <DateTime>[];
    final start = dateOnly(from);
    final end = dateOnly(to);
    var date = dateOnly(expense.dueDate);
    var step = 0;

    while (!date.isAfter(end) && step < 500) {
      if (!date.isBefore(start)) {
        result.add(date);
      } else if (step == 0 && includeOverdue) {
        result.add(start);
      }

      if (expense.intervalMonths == 0) {
        break;
      }

      step++;
      date = addMonths(dateOnly(expense.dueDate), expense.intervalMonths * step);
    }

    return result;
  }

  /// Общая сумма всех неоплаченных обязательных расходов.
  double get unpaidTotal {
    return unpaidExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  /// Добавить обязательный расход.
  void addExpense(MandatoryExpense expense) {
    _expenses.add(expense);
    notifyListeners();
  }

  /// Изменить обязательный расход.
  void updateExpense(MandatoryExpense expense) {
    final index = _expenses.indexWhere((item) => item.id == expense.id);

    if (index == -1) {
      return;
    }

    _expenses[index] = expense;
    notifyListeners();
  }

  /// Вернуть разовый платёж в состояние "не оплачен".
  void markAsUnpaid(String id) {
    final expense = getById(id);

    if (expense == null) {
      return;
    }

    updateExpense(expense.copyWith(isPaid: false));
  }

  /// Удалить обязательный расход.
  void deleteExpense(String id) {
    _expenses.removeWhere((expense) => expense.id == id);
    notifyListeners();
  }

  /// Найти обязательный расход по ID.
  MandatoryExpense? getById(String id) {
    for (final expense in _expenses) {
      if (expense.id == id) {
        return expense;
      }
    }

    return null;
  }
}
