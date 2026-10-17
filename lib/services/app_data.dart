import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/account_store.dart';
import '../models/category.dart';
import '../models/category_store.dart';
import '../models/goal.dart';
import '../models/income_source.dart';
import '../models/income_source_store.dart';
import '../models/mandatory_expense.dart';
import '../models/mandatory_expense_store.dart';
import '../models/planned_income.dart';
import '../models/transaction.dart';
import '../models/transaction_store.dart';
import '../utils/format.dart';

/// Все данные приложения в одном месте.
///
/// Здесь же находится логика, которая затрагивает
/// несколько хранилищ сразу: операции меняют балансы
/// счетов, оплата обязательного платежа создаёт расход,
/// по вкладам начисляются проценты и т.д.
///
/// Любое изменение автоматически сохраняется на телефоне.
class AppData {
  static const _keyAccounts = 'accounts_v1';
  static const _keyCategories = 'categories_v1';
  static const _keyIncomeSources = 'income_sources_v1';
  static const _keyMandatory = 'mandatory_expenses_v1';
  static const _keyTransactions = 'transactions_v1';
  static const _keyGoals = 'goals_v1';
  static const _keyPlannedIncomes = 'planned_incomes_v1';

  static const _backupAppId = 'moy-budget';
  static const _backupVersion = 2;

  /// Источник дохода для начисленных процентов.
  static const interestSourceName = 'Проценты по вкладу';

  final AccountStore accounts = AccountStore();
  final CategoryStore categories = CategoryStore();
  final IncomeSourceStore incomeSources = IncomeSourceStore();
  final MandatoryExpenseStore mandatory = MandatoryExpenseStore();
  final TransactionStore transactions = TransactionStore();
  final GoalStore goals = GoalStore();
  final PlannedIncomeStore plannedIncomes = PlannedIncomeStore();

  final SharedPreferences? _prefs;

  AppData._(this._prefs);

  /// Слушатель, который срабатывает при любом изменении данных.
  Listenable get all => Listenable.merge([
        accounts,
        categories,
        incomeSources,
        mandatory,
        transactions,
        goals,
        plannedIncomes,
      ]);

  // ─────────────────────────────
  // ЗАГРУЗКА И СОХРАНЕНИЕ
  // ─────────────────────────────

  static Future<AppData> load() async {
    SharedPreferences? prefs;

    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('Не удалось открыть хранилище: $error');
    }

    final data = AppData._(prefs);

    data.accounts.replaceAll(
      data._readList(_keyAccounts, Account.fromJson) ??
          AccountStore.defaults(),
    );
    data.categories.replaceAll(
      data._readList(_keyCategories, ExpenseCategory.fromJson) ??
          CategoryStore.defaults(),
    );
    data.incomeSources.replaceAll(
      data._readList(_keyIncomeSources, IncomeSource.fromJson) ??
          IncomeSourceStore.defaults(),
    );
    data.mandatory.replaceAll(
      data._readList(_keyMandatory, MandatoryExpense.fromJson) ??
          MandatoryExpenseStore.defaults(),
    );
    data.transactions.replaceAll(
      data._readList(_keyTransactions, Transaction.fromJson) ?? const [],
    );
    data.goals.replaceAll(
      data._readList(_keyGoals, Goal.fromJson) ?? const [],
    );
    data.plannedIncomes.replaceAll(
      data._readList(_keyPlannedIncomes, PlannedIncome.fromJson) ?? const [],
    );

    // Сохраняем сразу, чтобы при следующем запуске
    // не подставлялись стартовые данные.
    data._saveAll();
    data._listenForChanges();

    data.processScheduled(DateTime.now());

    return data;
  }

  /// Пустые данные без сохранения (для тестов).
  factory AppData.inMemory() {
    final data = AppData._(null);
    data.categories.replaceAll(CategoryStore.defaults());
    data.incomeSources.replaceAll(IncomeSourceStore.defaults());
    return data;
  }

  List<T>? _readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _prefs?.getString(key);

    if (raw == null) {
      return null;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;

      return list
          .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      debugPrint('Не удалось прочитать $key: $error');
      return null;
    }
  }

  void _write(String key, List<Map<String, dynamic>> data) {
    _prefs?.setString(key, jsonEncode(data));
  }

  void _saveAll() {
    _write(_keyAccounts, accounts.toJson());
    _write(_keyCategories, categories.toJson());
    _write(_keyIncomeSources, incomeSources.toJson());
    _write(_keyMandatory, mandatory.toJson());
    _write(_keyTransactions, transactions.toJson());
    _write(_keyGoals, goals.toJson());
    _write(_keyPlannedIncomes, plannedIncomes.toJson());
  }

  void _listenForChanges() {
    accounts.addListener(() => _write(_keyAccounts, accounts.toJson()));
    categories.addListener(
      () => _write(_keyCategories, categories.toJson()),
    );
    incomeSources.addListener(
      () => _write(_keyIncomeSources, incomeSources.toJson()),
    );
    mandatory.addListener(() => _write(_keyMandatory, mandatory.toJson()));
    transactions.addListener(
      () => _write(_keyTransactions, transactions.toJson()),
    );
    goals.addListener(() => _write(_keyGoals, goals.toJson()));
    plannedIncomes.addListener(
      () => _write(_keyPlannedIncomes, plannedIncomes.toJson()),
    );
  }

  /// Автоматические действия по расписанию (при запуске
  /// и при возвращении в приложение): начисление процентов.
  /// Возвращает, сколько начислений создано.
  int processScheduled(DateTime now) {
    return accrueInterest(now);
  }

  // ─────────────────────────────
  // ОПЕРАЦИИ
  // ─────────────────────────────

  /// Применить операцию к балансам.
  /// [sign] = -1 — откатить операцию.
  void _apply(Transaction transaction, {int sign = 1}) {
    final amount = transaction.amount * sign;

    switch (transaction.type) {
      case TransactionType.expense:
        accounts.changeBalance(transaction.accountId, -amount);
      case TransactionType.income:
      case TransactionType.adjustment:
        accounts.changeBalance(transaction.accountId, amount);
      case TransactionType.transfer:
        accounts.changeBalance(transaction.accountId, -amount);
        final destination = transaction.destinationAccountId;
        if (destination != null) {
          accounts.changeBalance(destination, amount);
        }
    }
  }

  /// Проверка перед проведением операции.
  /// Возвращает текст ошибки или null.
  String? _validate(Transaction transaction) {
    if (transaction.type == TransactionType.adjustment) {
      if (transaction.amount.abs() < 0.005) {
        return 'Баланс не изменился.';
      }
    } else if (transaction.amount <= 0) {
      return 'Сумма должна быть больше нуля.';
    }

    final account = accounts.getById(transaction.accountId);

    if (account == null) {
      return 'Выберите счёт.';
    }

    if (account.isClosed && !transaction.isInterest) {
      return 'Счёт «${account.name}» закрыт.';
    }

    if (transaction.type == TransactionType.adjustment) {
      return null;
    }

    final date = dateOnly(transaction.date);

    if (transaction.type == TransactionType.transfer) {
      final destination =
          accounts.getById(transaction.destinationAccountId);

      if (destination == null) {
        return 'Выберите счёт назначения.';
      }

      if (destination.id == account.id) {
        return 'Счёт отправителя и счёт назначения должны отличаться.';
      }

      if (destination.isClosed) {
        return 'Счёт «${destination.name}» закрыт.';
      }

      if (destination.currency != account.currency) {
        return 'Переводы между счетами в разных валютах '
            'пока не поддерживаются.';
      }

      final depositError = _depositTopUpError(destination, date);
      if (depositError != null) {
        return depositError;
      }
    }

    if (transaction.type == TransactionType.income &&
        !transaction.isInterest) {
      final depositError = _depositTopUpError(account, date);
      if (depositError != null) {
        return depositError;
      }
    }

    if (transaction.type != TransactionType.income) {
      final deposit = account.deposit;

      if (account.isDeposit && !deposit!.canWithdraw) {
        final end = deposit.endDate;
        final matured = end != null && !date.isBefore(dateOnly(end));

        if (!matured) {
          return 'По условиям вклада «${account.name}» снимать деньги '
              'до окончания срока нельзя. Это можно изменить '
              'в настройках вклада.';
        }
      }

      if (account.balance + 0.004 < transaction.amount) {
        return 'На счёте «${account.name}» только '
            '${account.money(account.balance)}. '
            'Если баланс неверный — исправьте его в разделе «Счета».';
      }
    }

    return null;
  }

  String? _depositTopUpError(Account account, DateTime date) {
    final deposit = account.deposit;

    if (!account.isDeposit) {
      return null;
    }

    if (!deposit!.canTopUp) {
      return 'Вклад «${account.name}» нельзя пополнять. '
          'Это можно изменить в настройках вклада.';
    }

    final end = deposit.endDate;
    if (end != null && date.isAfter(dateOnly(end))) {
      return 'Срок вклада «${account.name}» закончился.';
    }

    return null;
  }

  /// Провести новую операцию. Возвращает ошибку или null.
  String? addTransaction(Transaction transaction) {
    final error = _validate(transaction);

    if (error != null) {
      return error;
    }

    _apply(transaction);
    accounts.commit();
    transactions.add(transaction);

    return null;
  }

  /// Изменить операцию: старая откатывается, новая применяется.
  String? updateTransaction(Transaction oldOne, Transaction newOne) {
    _apply(oldOne, sign: -1);

    final error = _validate(newOne);

    if (error != null) {
      _apply(oldOne);
      return error;
    }

    _apply(newOne);
    accounts.commit();
    transactions.replace(newOne);

    return null;
  }

  /// Удалить операцию и вернуть деньги на счета.
  void deleteTransaction(Transaction transaction) {
    _apply(transaction, sign: -1);
    accounts.commit();
    transactions.remove(transaction.id);
  }

  /// Исправить баланс счёта: создаётся операция-корректировка,
  /// история не теряется. Возвращает ошибку или null.
  String? adjustBalance(
    String accountId,
    double newBalance, {
    String reason = '',
    DateTime? date,
  }) {
    final account = accounts.getById(accountId);

    if (account == null) {
      return 'Счёт не найден.';
    }

    final delta = roundMoney(newBalance - account.balance);

    return addTransaction(
      Transaction(
        id: newId(),
        type: TransactionType.adjustment,
        amount: delta,
        date: date ?? DateTime.now(),
        accountId: accountId,
        comment: reason.trim().isEmpty
            ? 'Было ${account.money(account.balance)}, '
                'стало ${account.money(newBalance)}'
            : reason.trim(),
      ),
    );
  }

  // ─────────────────────────────
  // СЧЕТА
  // ─────────────────────────────

  /// Добавить счёт. Для вклада, открытого в прошлом, считаем, что
  /// введённый баланс уже включает выплаченные проценты.
  void addAccount(Account account, {DateTime? now}) {
    accounts.addAccount(_withAccrualStart(account, now ?? DateTime.now()));
  }

  /// Изменить параметры счёта (не баланс — для этого [adjustBalance]).
  void updateAccount(Account account, {DateTime? now}) {
    final old = accounts.getById(account.id);
    var updated = account.copyWith(balance: old?.balance ?? account.balance);

    // Вклад только что получил условия — начинаем отсчёт процентов.
    if (old != null && old.deposit == null && updated.deposit != null) {
      updated = _withAccrualStart(updated, now ?? DateTime.now());
    }

    accounts.updateAccount(updated);
  }

  Account _withAccrualStart(Account account, DateTime now) {
    final deposit = account.deposit;
    final openDate = account.openDate;

    if (deposit == null || openDate == null) {
      return account;
    }

    return account.copyWith(
      deposit: deposit.copyWith(
        lastAccrualDate: deposit.lastPayoutOnOrBefore(now, openDate),
      ),
    );
  }

  /// Закрыть счёт. Возвращает ошибку или null.
  String? closeAccount(String id) {
    final account = accounts.getById(id);

    if (account == null) {
      return 'Счёт не найден.';
    }

    if (account.balance.abs() >= 0.005) {
      return 'На счёте ещё ${account.money(account.balance)}. '
          'Сначала переведите остаток на другой счёт.';
    }

    accounts.updateAccount(account.copyWith(isClosed: true));
    return null;
  }

  void reopenAccount(String id) {
    final account = accounts.getById(id);

    if (account != null) {
      accounts.updateAccount(account.copyWith(isClosed: false));
    }
  }

  /// Удалить счёт. Операции по нему остаются в истории.
  void deleteAccount(String id) {
    accounts.deleteAccount(id);
  }

  /// Баланс счёта на конец дня [date].
  double balanceAt(String accountId, DateTime date) {
    final account = accounts.getById(accountId);

    if (account == null) {
      return 0;
    }

    final day = dateOnly(date);
    var balance = account.balance;

    for (final transaction in transactions.transactions) {
      if (dateOnly(transaction.date).isAfter(day)) {
        balance -= transaction.effectOn(accountId);
      }
    }

    return roundMoney(balance);
  }

  // ─────────────────────────────
  // ВКЛАДЫ
  // ─────────────────────────────

  /// Проценты по вкладу за дни после [from] по [to] включительно.
  ///
  /// Считаются по дням: каждый день — от суммы, которая лежала
  /// на вкладе на начало этого дня. Поэтому пополнение 10-го числа
  /// увеличивает проценты только с 11-го.
  double interestBetween(Account account, DateTime from, DateTime to) {
    final deposit = account.deposit;

    if (deposit == null || deposit.rate <= 0) {
      return 0;
    }

    final start = dateOnly(from);
    final end = dateOnly(to);

    if (!end.isAfter(start)) {
      return 0;
    }

    // Движения по вкладу после начала периода: {день: изменение}.
    final changes = <DateTime, double>{};
    for (final transaction in transactions.transactions) {
      final day = dateOnly(transaction.date);
      final effect = transaction.effectOn(account.id);

      if (effect != 0 && day.isAfter(start)) {
        changes[day] = (changes[day] ?? 0) + effect;
      }
    }

    var balance = balanceAt(account.id, start);
    var interest = 0.0;
    var day = start.add(const Duration(days: 1));

    while (!day.isAfter(end)) {
      // Проценты за день — от суммы на начало дня.
      interest += balance * deposit.rate / 100 / daysInYear(day.year);
      balance += changes[day] ?? 0;
      day = DateTime(day.year, day.month, day.day + 1);
    }

    return roundMoney(interest);
  }

  /// Начислить все проценты, срок которых наступил.
  int accrueInterest(DateTime now) {
    final today = dateOnly(now);
    var created = 0;

    for (final account in accounts.accounts) {
      final openDate = account.openDate;

      if (!account.isDeposit || account.isClosed || openDate == null) {
        continue;
      }

      var deposit = account.deposit!;
      var last = deposit.lastAccrualDate;
      var next = deposit.nextPayoutAfter(last, openDate);

      while (next != null && !next.isAfter(today)) {
        final amount = interestBetween(account, last, next);

        if (amount > 0) {
          final target = deposit.capitalization
              ? account.id
              : (_activeAccountId(deposit.interestAccountId) ?? account.id);

          final transaction = Transaction(
            id: newId(),
            type: TransactionType.income,
            amount: amount,
            date: DateTime(next.year, next.month, next.day, 9),
            accountId: target,
            incomeSource: interestSourceName,
            comment: 'Вклад «${account.name}»',
            depositInterestFor: account.id,
          );

          _apply(transaction);
          transactions.add(transaction);
          created++;
        }

        last = next;
        next = deposit.nextPayoutAfter(last, openDate);
      }

      if (last != deposit.lastAccrualDate) {
        deposit = deposit.copyWith(lastAccrualDate: last);
        accounts.updateAccount(account.copyWith(deposit: deposit));
      }
    }

    if (created > 0) {
      accounts.commit();
    }

    return created;
  }

  String? _activeAccountId(String? id) {
    final account = accounts.getById(id);
    return account == null || account.isClosed ? null : account.id;
  }

  /// Прогноз вклада до [until] при текущей сумме без пополнений.
  DepositProjection projectDeposit(Account account, DateTime until) {
    final deposit = account.deposit;
    final openDate = account.openDate;

    if (deposit == null || openDate == null || deposit.rate <= 0) {
      return DepositProjection(balance: account.balance, interest: 0);
    }

    var balance = account.balance;
    var interest = 0.0;
    var last = deposit.lastAccrualDate;
    var next = deposit.nextPayoutAfter(last, openDate);
    final end = dateOnly(until);

    while (next != null && !next.isAfter(end)) {
      final days = daysBetween(last, next);
      final amount = roundMoney(
        balance * deposit.rate / 100 * days / daysInYear(next.year),
      );

      interest += amount;
      if (deposit.capitalization) {
        balance += amount;
      }

      last = next;
      next = deposit.nextPayoutAfter(last, openDate);
    }

    return DepositProjection(
      balance: roundMoney(balance),
      interest: roundMoney(interest),
    );
  }

  /// Сколько начислится в ближайшую дату (по текущей сумме).
  ({DateTime date, double amount})? nextInterest(Account account) {
    final deposit = account.deposit;
    final openDate = account.openDate;

    if (deposit == null || openDate == null || account.isClosed) {
      return null;
    }

    final next = deposit.nextPayoutAfter(deposit.lastAccrualDate, openDate);

    if (next == null) {
      return null;
    }

    final days = daysBetween(deposit.lastAccrualDate, next);
    return (
      date: next,
      amount: roundMoney(
        account.balance * deposit.rate / 100 * days / daysInYear(next.year),
      ),
    );
  }

  /// Все начисления процентов по вкладу.
  List<Transaction> interestOf(String depositId) {
    return transactions.transactions
        .where((transaction) => transaction.depositInterestFor == depositId)
        .toList();
  }

  // ─────────────────────────────
  // ОБЯЗАТЕЛЬНЫЕ ПЛАТЕЖИ
  // ─────────────────────────────

  /// Оплатить обязательный платёж:
  /// 1. создаётся расход и списываются деньги со счёта;
  /// 2. повторяющийся платёж переносится на следующую дату,
  ///    разовый — отмечается оплаченным;
  /// 3. резерв, накопленный на этот платёж, обнуляется.
  String? payMandatory(
    MandatoryExpense expense, {
    required double amount,
    required String accountId,
    required DateTime date,
  }) {
    final transaction = Transaction(
      id: newId(),
      type: TransactionType.expense,
      amount: roundMoney(amount),
      date: date,
      accountId: accountId,
      category: expense.category ?? CategoryStore.mandatoryCategoryName,
      subcategory: expense.category == null ? null : expense.subcategory,
      priority: TransactionPriority.necessary,
      comment: expense.name,
      mandatoryExpenseId: expense.id,
    );

    final error = addTransaction(transaction);

    if (error != null) {
      return error;
    }

    final updated = expense.copyWith(
      reserveLog: const [],
      accountId: accountId,
    );

    if (expense.period == ExpensePeriod.once) {
      mandatory.updateExpense(updated.copyWith(isPaid: true));
    } else {
      mandatory.updateExpense(
        updated.copyWith(
          dueDate: addMonths(expense.dueDate, expense.intervalMonths),
        ),
      );
    }

    return null;
  }

  /// Фактические оплаты платежа (от новых к старым).
  List<Transaction> paymentsOf(String expenseId) {
    return transactions.transactions
        .where((transaction) => transaction.mandatoryExpenseId == expenseId)
        .toList();
  }

  /// Средняя фактическая сумма платежа (null — оплат ещё не было).
  double? averagePayment(String expenseId) {
    final payments = paymentsOf(expenseId);

    if (payments.isEmpty) {
      return null;
    }

    final sum = payments.fold(0.0, (total, t) => total + t.amount);
    return roundMoney(sum / payments.length);
  }

  /// Сколько откладывать в месяц на редкий платёж.
  double reserveMonthlyNeed(MandatoryExpense expense, DateTime now) {
    if (!expense.isRare || expense.isPaid) {
      return 0;
    }

    final before =
        expense.reserved - expense.reservedInMonth(now.year, now.month);
    final left = expense.amount - before;

    if (left <= 0) {
      return 0;
    }

    return roundMoney(left / monthsLeftInclusive(now, expense.dueDate));
  }

  /// Сколько ещё отложить на редкий платёж в этом месяце.
  double reserveLeftThisMonth(MandatoryExpense expense, DateTime now) {
    final left = reserveMonthlyNeed(expense, now) -
        expense.reservedInMonth(now.year, now.month);
    return left > 0 ? roundMoney(left) : 0;
  }

  /// Отложить деньги на редкий платёж.
  /// Если указан [fromAccountId] и резерв хранится на другом счёте —
  /// делается перевод. Отрицательная сумма — забрать из резерва.
  String? addToReserve(
    MandatoryExpense expense,
    double amount, {
    DateTime? date,
    String? fromAccountId,
  }) {
    final when = date ?? DateTime.now();

    if (amount.abs() < 0.005) {
      return 'Введите сумму.';
    }

    if (amount < 0 && expense.reserved + amount < -0.004) {
      return 'В резерве только ${formatMoney(expense.reserved)}.';
    }

    final transferError = _moveForSaving(
      amount: amount,
      fromAccountId: fromAccountId,
      toAccountId: expense.reserveAccountId,
      date: when,
      comment: 'Резерв: ${expense.name}',
    );

    if (transferError != null) {
      return transferError;
    }

    mandatory.updateExpense(
      expense.copyWith(
        reserveLog: [
          ...expense.reserveLog,
          ReserveEntry(date: when, amount: roundMoney(amount)),
        ],
      ),
    );

    return null;
  }

  /// Перевод для накоплений: положительная сумма — с [fromAccountId]
  /// на [toAccountId], отрицательная — обратно.
  String? _moveForSaving({
    required double amount,
    required String? fromAccountId,
    required String? toAccountId,
    required DateTime date,
    required String comment,
  }) {
    if (fromAccountId == null ||
        toAccountId == null ||
        fromAccountId == toAccountId) {
      return null;
    }

    final positive = amount > 0;

    return addTransaction(
      Transaction(
        id: newId(),
        type: TransactionType.transfer,
        amount: roundMoney(amount.abs()),
        date: date,
        accountId: positive ? fromAccountId : toAccountId,
        destinationAccountId: positive ? toAccountId : fromAccountId,
        comment: comment,
      ),
    );
  }

  // ─────────────────────────────
  // ЦЕЛИ
  // ─────────────────────────────

  /// Пополнить цель (или снять, если сумма отрицательная).
  /// Если указан [fromAccountId] и он отличается от счёта цели —
  /// делается перевод между счетами.
  String? contributeToGoal(
    Goal goal,
    double amount, {
    DateTime? date,
    String? fromAccountId,
    String comment = '',
  }) {
    final when = date ?? DateTime.now();

    if (amount.abs() < 0.005) {
      return 'Введите сумму.';
    }

    if (amount < 0 && goal.current + amount < -0.004) {
      return 'В цели только ${formatMoney(goal.current)}.';
    }

    final transferError = _moveForSaving(
      amount: amount,
      fromAccountId: fromAccountId,
      toAccountId: goal.accountId,
      date: when,
      comment: 'Цель: ${goal.name}',
    );

    if (transferError != null) {
      return transferError;
    }

    goals.update(
      goal.copyWith(
        contributions: [
          ...goal.contributions,
          GoalContribution(
            id: newId(),
            date: when,
            amount: roundMoney(amount),
            comment: comment,
          ),
        ],
      ),
    );

    return null;
  }

  // ─────────────────────────────
  // ПЛАНОВЫЕ ДОХОДЫ
  // ─────────────────────────────

  /// Отметить, что ожидаемый доход пришёл: создаётся доход,
  /// дата переносится на следующий раз.
  String? receiveIncome(
    PlannedIncome income, {
    required double amount,
    required String accountId,
    required DateTime date,
  }) {
    final error = addTransaction(
      Transaction(
        id: newId(),
        type: TransactionType.income,
        amount: roundMoney(amount),
        date: date,
        accountId: accountId,
        incomeSource: income.source,
        comment: income.name == income.source ? '' : income.name,
      ),
    );

    if (error != null) {
      return error;
    }

    if (income.intervalMonths == 0) {
      plannedIncomes.delete(income.id);
    } else {
      // Переносим на ближайшую дату после дня получения.
      var next = income.nextDate;
      var step = 0;
      while (!dateOnly(next).isAfter(dateOnly(date)) || step == 0) {
        step++;
        next = addMonths(income.nextDate, income.intervalMonths * step);
      }
      plannedIncomes.update(
        income.copyWith(nextDate: next, accountId: accountId),
      );
    }

    return null;
  }

  // ─────────────────────────────
  // КАТЕГОРИИ
  // ─────────────────────────────

  /// Переименовать категорию. Операции и платежи хранят категорию
  /// по имени, поэтому обновляем и их.
  void renameCategory(String id, String newName) {
    final category = categories.getById(id);
    final name = newName.trim();

    if (category == null || name.isEmpty || name == category.name) {
      return;
    }

    if (category.name == CategoryStore.mandatoryCategoryName) {
      return;
    }

    final parent = categories.getById(category.parentId);
    final oldName = category.name;

    categories.updateCategory(category.copyWith(name: name));

    for (final transaction in transactions.transactions) {
      if (parent == null && transaction.category == oldName) {
        transactions.replace(transaction.copyWith(category: name));
      } else if (parent != null &&
          transaction.category == parent.name &&
          transaction.subcategory == oldName) {
        transactions.replace(transaction.copyWith(subcategory: name));
      }
    }

    for (final expense in mandatory.expenses) {
      if (parent == null && expense.category == oldName) {
        mandatory.updateExpense(expense.copyWith(category: name));
      } else if (parent != null &&
          expense.category == parent.name &&
          expense.subcategory == oldName) {
        mandatory.updateExpense(expense.copyWith(subcategory: name));
      }
    }
  }

  // ─────────────────────────────
  // РЕЗЕРВНАЯ КОПИЯ
  // ─────────────────────────────

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': _backupAppId,
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': accounts.toJson(),
      'categories': categories.toJson(),
      'incomeSources': incomeSources.toJson(),
      'mandatoryExpenses': mandatory.toJson(),
      'transactions': transactions.toJson(),
      'goals': goals.toJson(),
      'plannedIncomes': plannedIncomes.toJson(),
    });
  }

  /// Восстановить данные из резервной копии.
  /// Бросает [FormatException], если текст не подходит.
  void importJson(String text) {
    dynamic decoded;

    try {
      decoded = jsonDecode(text.trim());
    } catch (_) {
      throw const FormatException(
        'Текст не похож на резервную копию.',
      );
    }

    if (decoded is! Map || decoded['app'] != _backupAppId) {
      throw const FormatException(
        'Это не резервная копия «Моего бюджета».',
      );
    }

    List<T> parse<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final list = decoded[key];

      if (list is! List) {
        return <T>[];
      }

      return list
          .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    // Сначала разбираем всё целиком, чтобы при ошибке
    // не заменить данные наполовину.
    late final List<Account> newAccounts;
    late final List<ExpenseCategory> newCategories;
    late final List<IncomeSource> newSources;
    late final List<MandatoryExpense> newMandatory;
    late final List<Transaction> newTransactions;
    late final List<Goal> newGoals;
    late final List<PlannedIncome> newIncomes;

    try {
      newAccounts = parse('accounts', Account.fromJson);
      newCategories = parse('categories', ExpenseCategory.fromJson);
      newSources = parse('incomeSources', IncomeSource.fromJson);
      newMandatory = parse('mandatoryExpenses', MandatoryExpense.fromJson);
      newTransactions = parse('transactions', Transaction.fromJson);
      newGoals = parse('goals', Goal.fromJson);
      newIncomes = parse('plannedIncomes', PlannedIncome.fromJson);
    } catch (_) {
      throw const FormatException(
        'Резервная копия повреждена.',
      );
    }

    accounts.replaceAll(newAccounts);
    categories.replaceAll(
      newCategories.isEmpty ? CategoryStore.defaults() : newCategories,
    );
    incomeSources.replaceAll(
      newSources.isEmpty ? IncomeSourceStore.defaults() : newSources,
    );
    mandatory.replaceAll(newMandatory);
    transactions.replaceAll(newTransactions);
    goals.replaceAll(newGoals);
    plannedIncomes.replaceAll(newIncomes);
  }

  /// Удалить все данные и начать с чистого листа.
  void resetAll() {
    accounts.replaceAll(const []);
    categories.replaceAll(CategoryStore.defaults());
    incomeSources.replaceAll(IncomeSourceStore.defaults());
    mandatory.replaceAll(const []);
    transactions.replaceAll(const []);
    goals.replaceAll(const []);
    plannedIncomes.replaceAll(const []);
  }

  // ─────────────────────────────
  // ДНЕВНОЙ БЮДЖЕТ
  // ─────────────────────────────

  /// Счёт учитывается в доступных деньгах.
  bool isAvailableAccount(String? id) {
    final account = accounts.getById(id);
    return account != null &&
        account.countsInTotals &&
        account.includeInAvailableMoney;
  }

  /// Конец текущего бюджетного периода: день перед ближайшим
  /// доходом, а если доходы не запланированы — конец месяца.
  DateTime periodEnd(DateTime now) {
    final today = dateOnly(now);
    final nextIncome = plannedIncomes.nextAfter(today);

    if (nextIncome == null) {
      return endOfMonth(today);
    }

    return nextIncome.subtract(const Duration(days: 1));
  }

  /// Неоплаченные платежи до [until] (с повторами и просроченными).
  List<DueItem> dueUntil(DateTime now, DateTime until) {
    final result = <DueItem>[];

    for (final expense in mandatory.unpaidExpenses) {
      for (final date in MandatoryExpenseStore.occurrences(
        expense,
        now,
        until,
        includeOverdue: true,
      )) {
        result.add(DueItem(expense: expense, date: date));
      }
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// Сколько нужно заплатить из доступных денег по этому платежу.
  /// Если резерв лежит на отдельном счёте — он покроет часть суммы.
  double _dueFromAvailable(DueItem item, {required bool first}) {
    final expense = item.expense;
    var amount = expense.amount;

    if (first &&
        expense.reserved > 0 &&
        !isAvailableAccount(expense.reserveAccountId) &&
        expense.reserveAccountId != null) {
      amount -= expense.reserved;
    }

    return amount > 0 ? amount : 0;
  }

  BudgetSummary budgetFor(DateTime now) {
    final today = dateOnly(now);
    final end = periodEnd(today);
    final daysLeft = daysBetween(today, end) + 1;
    final nextIncome = plannedIncomes.nextAfter(today);

    final available = accounts.availableMoney;

    // Обязательные платежи до конца периода.
    final due = dueUntil(today, end);
    final seen = <String>{};
    var mandatoryDue = 0.0;

    for (final item in due) {
      mandatoryDue += _dueFromAvailable(item, first: seen.add(item.expense.id));
    }

    // Резервы на редкие платежи, которые будут позже.
    var reservesHeld = 0.0;
    var reservesToSave = 0.0;

    for (final expense in mandatory.unpaidExpenses) {
      if (!expense.isRare || seen.contains(expense.id)) {
        continue;
      }

      final heldInAvailable = expense.reserveAccountId == null ||
          isAvailableAccount(expense.reserveAccountId);

      if (heldInAvailable) {
        reservesHeld += expense.reserved;
      }
      reservesToSave += reserveLeftThisMonth(expense, today);
    }

    // Цели.
    var goalsHeld = 0.0;
    var goalsToSave = 0.0;

    for (final goal in goals.active) {
      if (isAvailableAccount(goal.accountId)) {
        goalsHeld += goal.current;
      }
      goalsToSave += goal.leftThisMonth(today);
    }

    // Обычные траты за сегодня со счетов, которые учитываются
    // в доступных деньгах. Оплата обязательных платежей сюда
    // не входит — она уже заложена в mandatoryDue.
    final spentToday = transactions.transactions
        .where(
          (transaction) =>
              transaction.type == TransactionType.expense &&
              !transaction.isMandatoryPayment &&
              isSameDay(transaction.date, today) &&
              isAvailableAccount(transaction.accountId),
        )
        .fold(0.0, (sum, transaction) => sum + transaction.amount);

    final free = roundMoney(
      available -
          mandatoryDue -
          reservesHeld -
          reservesToSave -
          goalsHeld -
          goalsToSave,
    );
    final dailyLimit = (free + spentToday) / daysLeft;

    return BudgetSummary(
      available: available,
      mandatoryDue: roundMoney(mandatoryDue),
      mandatoryDueCount: due.length,
      reservesHeld: roundMoney(reservesHeld),
      reservesToSave: roundMoney(reservesToSave),
      goalsHeld: roundMoney(goalsHeld),
      goalsToSave: roundMoney(goalsToSave),
      free: free,
      periodEnd: end,
      nextIncomeDate: nextIncome,
      daysLeft: daysLeft,
      dailyLimit: dailyLimit,
      spentToday: spentToday,
      leftToday: dailyLimit - spentToday,
      tomorrowLimit: daysLeft > 1 ? free / (daysLeft - 1) : null,
    );
  }

  /// Как распределить доход [amount], пришедший [date]:
  /// обязательные до следующего дохода, резервы, цели,
  /// планы по категориям, остаток — свободные деньги.
  IncomeDistribution distributionFor(double amount, DateTime date) {
    final day = dateOnly(date);
    final nextIncome = plannedIncomes.nextAfter(day);
    final until = nextIncome == null
        ? endOfMonth(day)
        : nextIncome.subtract(const Duration(days: 1));

    final lines = <DistributionLine>[];

    final due = dueUntil(day, until);
    final mandatoryTotal =
        due.fold(0.0, (sum, item) => sum + item.expense.amount);
    if (mandatoryTotal > 0) {
      lines.add(
        DistributionLine(
          title: 'Обязательные платежи',
          amount: roundMoney(mandatoryTotal),
          details: due.map((item) => item.expense.name).toSet().join(', '),
          kind: DistributionKind.mandatory,
        ),
      );
    }

    final dueIds = due.map((item) => item.expense.id).toSet();
    for (final expense in mandatory.unpaidExpenses) {
      if (!expense.isRare || dueIds.contains(expense.id)) {
        continue;
      }
      final need = reserveLeftThisMonth(expense, day);
      if (need > 0) {
        lines.add(
          DistributionLine(
            title: expense.name,
            amount: need,
            details: 'резерв к ${formatDayMonth(expense.dueDate, now: day)}',
            kind: DistributionKind.reserve,
          ),
        );
      }
    }

    for (final goal in goals.active) {
      final need = goal.leftThisMonth(day);
      if (need > 0) {
        lines.add(
          DistributionLine(
            title: goal.name,
            amount: need,
            details: 'цель',
            kind: DistributionKind.goal,
          ),
        );
      }
    }

    for (final category in categories.topLevel) {
      final limit = category.monthlyLimit;
      if (limit == null || limit <= 0) {
        continue;
      }
      final spent = categorySpent(category.name, day.year, day.month);
      final left = limit - spent;
      if (left > 0) {
        lines.add(
          DistributionLine(
            title: category.name,
            amount: roundMoney(left),
            details: 'план на месяц',
            kind: DistributionKind.category,
          ),
        );
      }
    }

    final planned = lines.fold(0.0, (sum, line) => sum + line.amount);

    return IncomeDistribution(
      income: amount,
      lines: lines,
      free: roundMoney(amount - planned),
      until: until,
    );
  }

  /// Потрачено по категории верхнего уровня за месяц
  /// (включая оплаты обязательных платежей в этой категории).
  double categorySpent(String categoryName, int year, int month) {
    return roundMoney(
      transactions
          .expensesForMonth(year, month)
          .where((transaction) => transaction.category == categoryName)
          .fold(0.0, (sum, transaction) => sum + transaction.amount),
    );
  }
}

class DueItem {
  final MandatoryExpense expense;
  final DateTime date;

  const DueItem({required this.expense, required this.date});
}

class DepositProjection {
  final double balance;
  final double interest;

  const DepositProjection({required this.balance, required this.interest});
}

class BudgetSummary {
  /// Деньги на счетах, которые учитываются в доступных.
  final double available;

  /// Неоплаченные обязательные платежи до конца периода
  /// (включая просроченные).
  final double mandatoryDue;
  final int mandatoryDueCount;

  /// Уже отложено на редкие платежи (на доступных счетах).
  final double reservesHeld;

  /// Ещё отложить на редкие платежи в этом месяце.
  final double reservesToSave;

  /// Деньги целей, которые лежат на доступных счетах.
  final double goalsHeld;

  /// Ещё отложить на цели в этом месяце.
  final double goalsToSave;

  /// Свободно: доступно минус всё, что уже распределено.
  final double free;

  /// Последний день периода (день перед доходом или конец месяца).
  final DateTime periodEnd;
  final DateTime? nextIncomeDate;

  /// Сколько дней осталось в периоде, включая сегодня.
  final int daysLeft;

  /// Лимит на сегодня (посчитан на начало дня).
  final double dailyLimit;

  final double spentToday;

  /// Сколько ещё можно потратить сегодня.
  final double leftToday;

  /// Каким будет лимит завтра, если сегодня больше не тратить.
  final double? tomorrowLimit;

  const BudgetSummary({
    required this.available,
    required this.mandatoryDue,
    required this.mandatoryDueCount,
    this.reservesHeld = 0,
    this.reservesToSave = 0,
    this.goalsHeld = 0,
    this.goalsToSave = 0,
    required this.free,
    required this.periodEnd,
    this.nextIncomeDate,
    required this.daysLeft,
    required this.dailyLimit,
    required this.spentToday,
    required this.leftToday,
    this.tomorrowLimit,
  });

  /// Всего отложено и запланировано к откладыванию.
  double get savingsTotal =>
      reservesHeld + reservesToSave + goalsHeld + goalsToSave;
}

enum DistributionKind {
  mandatory,
  reserve,
  goal,
  category,
}

class DistributionLine {
  final String title;
  final double amount;
  final String details;
  final DistributionKind kind;

  const DistributionLine({
    required this.title,
    required this.amount,
    required this.details,
    required this.kind,
  });
}

class IncomeDistribution {
  final double income;
  final List<DistributionLine> lines;

  /// Свободные деньги после всех планов.
  final double free;

  /// До какого дня рассчитан план.
  final DateTime until;

  const IncomeDistribution({
    required this.income,
    required this.lines,
    required this.free,
    required this.until,
  });
}
