import 'package:flutter/foundation.dart';

import '../utils/format.dart';
import 'account.dart';

class AccountStore extends ChangeNotifier {
  final List<Account> _accounts = [];

  List<Account> get accounts => List.unmodifiable(_accounts);

  /// Стартовые счета при первом запуске.
  /// Балансы нулевые — реальные суммы вводятся в приложении.
  static List<Account> defaults() {
    return [
      Account(
        id: '1',
        name: 'Т-Банк',
        type: AccountType.debitCard,
        balance: 0,
        includeInAvailableMoney: true,
      ),
      Account(
        id: '2',
        name: 'Сбербанк',
        type: AccountType.debitCard,
        balance: 0,
        includeInAvailableMoney: true,
      ),
      Account(
        id: '3',
        name: 'Накопительный счёт',
        type: AccountType.savings,
        balance: 0,
        includeInAvailableMoney: true,
      ),
      Account(
        id: '4',
        name: 'Вклад',
        type: AccountType.deposit,
        balance: 0,
        includeInAvailableMoney: false,
      ),
    ];
  }

  void replaceAll(Iterable<Account> accounts) {
    _accounts
      ..clear()
      ..addAll(accounts);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() {
    return _accounts.map((account) => account.toJson()).toList();
  }

  /// Открытые счета (для выбора в формах).
  List<Account> get active {
    return _accounts.where((account) => !account.isClosed).toList();
  }

  List<Account> get closed {
    return _accounts.where((account) => account.isClosed).toList();
  }

  /// Общая сумма денег, которые доступны
  /// для обычных расходов.
  ///
  /// Вклады, закрытые, валютные и другие исключённые счета
  /// сюда не попадают.
  double get availableMoney {
    return _sum(
      (account) => account.countsInTotals && account.includeInAvailableMoney,
    );
  }

  /// Деньги на накопительных счетах.
  double get savingsMoney {
    return _sum(
      (account) =>
          account.countsInTotals && account.type == AccountType.savings,
    );
  }

  /// Деньги во вкладах.
  double get depositMoney {
    return _sum(
      (account) =>
          account.countsInTotals && account.type == AccountType.deposit,
    );
  }

  /// Деньги на расходных счетах и наличными.
  double get everydayMoney {
    return _sum(
      (account) =>
          account.countsInTotals &&
          (account.type == AccountType.debitCard ||
              account.type == AccountType.cash),
    );
  }

  /// Общий капитал: все открытые рублёвые счета, включая вклады.
  double get totalMoney => _sum((account) => account.countsInTotals);

  /// Открытые счета в иностранной валюте.
  List<Account> get foreign {
    return _accounts
        .where((account) => !account.isClosed && !account.isRub)
        .toList();
  }

  double _sum(bool Function(Account account) test) {
    return roundMoney(
      _accounts.where(test).fold(0.0, (sum, account) => sum + account.balance),
    );
  }

  /// Открытые счета этого типа.
  List<Account> byType(AccountType type) {
    return _accounts
        .where((account) => account.type == type && !account.isClosed)
        .toList();
  }

  /// Найти счёт по ID.
  Account? getById(String? id) {
    if (id == null) {
      return null;
    }

    for (final account in _accounts) {
      if (account.id == id) {
        return account;
      }
    }

    return null;
  }

  String nameOf(String? id) {
    return getById(id)?.name ?? 'Удалённый счёт';
  }

  /// Добавить новый счёт.
  void addAccount(Account account) {
    _accounts.add(account);
    notifyListeners();
  }

  /// Изменить счёт (название, тип, баланс и т.д.).
  void updateAccount(Account account) {
    final index = _accounts.indexWhere((item) => item.id == account.id);

    if (index == -1) {
      return;
    }

    _accounts[index] = account;
    notifyListeners();
  }

  void deleteAccount(String id) {
    _accounts.removeWhere((account) => account.id == id);
    notifyListeners();
  }

  /// Изменить баланс на [delta].
  ///
  /// Не уведомляет слушателей — после серии изменений
  /// нужно вызвать [commit].
  void changeBalance(String id, double delta) {
    final account = getById(id);

    if (account == null) {
      return;
    }

    account.balance = roundMoney(account.balance + delta);
  }

  /// Сообщить экранам, что балансы изменились,
  /// и сохранить данные.
  void commit() {
    notifyListeners();
  }
}
