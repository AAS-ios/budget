import 'package:flutter/foundation.dart';

import 'transaction.dart';

class TransactionStore extends ChangeNotifier {
  final List<Transaction> _transactions = [];

  /// Все операции, от новых к старым.
  List<Transaction> get transactions {
    return List<Transaction>.of(_transactions)..sort(_newestFirst);
  }

  static int _newestFirst(Transaction a, Transaction b) {
    final byDate = b.date.compareTo(a.date);

    if (byDate != 0) {
      return byDate;
    }

    return b.id.compareTo(a.id);
  }

  void replaceAll(Iterable<Transaction> transactions) {
    _transactions
      ..clear()
      ..addAll(transactions);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() {
    return _transactions.map((transaction) => transaction.toJson()).toList();
  }

  /// Добавить операцию.
  ///
  /// Балансы счетов здесь НЕ меняются —
  /// для этого используйте AppData.addTransaction.
  void add(Transaction transaction) {
    _transactions.add(transaction);
    notifyListeners();
  }

  void remove(String id) {
    _transactions.removeWhere((transaction) => transaction.id == id);
    notifyListeners();
  }

  void replace(Transaction transaction) {
    final index = _transactions.indexWhere(
      (item) => item.id == transaction.id,
    );

    if (index == -1) {
      return;
    }

    _transactions[index] = transaction;
    notifyListeners();
  }

  /// Найти операцию по ID.
  Transaction? getById(String id) {
    for (final transaction in _transactions) {
      if (transaction.id == id) {
        return transaction;
      }
    }

    return null;
  }

  /// Операции по конкретному счёту (включая входящие переводы).
  List<Transaction> forAccount(String accountId) {
    return transactions
        .where(
          (transaction) =>
              transaction.accountId == accountId ||
              transaction.destinationAccountId == accountId,
        )
        .toList();
  }

  /// Все операции за месяц.
  List<Transaction> forMonth(int year, int month) {
    return transactions
        .where(
          (transaction) =>
              transaction.date.year == year &&
              transaction.date.month == month,
        )
        .toList();
  }

  /// Расходы за конкретный месяц.
  List<Transaction> expensesForMonth(int year, int month) {
    return forMonth(year, month)
        .where((transaction) => transaction.type == TransactionType.expense)
        .toList();
  }

  /// Доходы за конкретный месяц.
  List<Transaction> incomesForMonth(int year, int month) {
    return forMonth(year, month)
        .where((transaction) => transaction.type == TransactionType.income)
        .toList();
  }

  /// Сумма расходов за конкретный месяц.
  double expensesAmountForMonth(int year, int month) {
    return _sum(expensesForMonth(year, month));
  }

  /// Сумма доходов за конкретный месяц.
  double incomesAmountForMonth(int year, int month) {
    return _sum(incomesForMonth(year, month));
  }

  /// Расходы по категориям за месяц: {категория: сумма},
  /// от большей суммы к меньшей.
  List<MapEntry<String, double>> expensesByCategory(int year, int month) {
    final result = <String, double>{};

    for (final transaction in expensesForMonth(year, month)) {
      final key = transaction.category ?? 'Без категории';
      result[key] = (result[key] ?? 0) + transaction.amount;
    }

    return result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Доходы по источникам за месяц.
  List<MapEntry<String, double>> incomesBySource(int year, int month) {
    final result = <String, double>{};

    for (final transaction in incomesForMonth(year, month)) {
      final key = transaction.incomeSource ?? 'Другое';
      result[key] = (result[key] ?? 0) + transaction.amount;
    }

    return result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Расходы по приоритету за месяц.
  double expensesForPriority(
    TransactionPriority priority,
    int year,
    int month,
  ) {
    return _sum(
      expensesForMonth(year, month)
          .where((transaction) => transaction.priority == priority),
    );
  }

  static double _sum(Iterable<Transaction> transactions) {
    return transactions.fold(
      0.0,
      (sum, transaction) => sum + transaction.amount,
    );
  }
}
