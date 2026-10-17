import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:appforios/models/account.dart';
import 'package:appforios/models/goal.dart';
import 'package:appforios/models/mandatory_expense.dart';
import 'package:appforios/models/planned_income.dart';
import 'package:appforios/models/transaction.dart';
import 'package:appforios/services/app_data.dart';
import 'package:appforios/services/insights.dart';
import 'package:appforios/utils/format.dart';

AppData _dataWithAccounts() {
  final data = AppData.inMemory();

  data.accounts.replaceAll([
    Account(
      id: 'card',
      name: 'Карта',
      type: AccountType.debitCard,
      balance: 10000,
      includeInAvailableMoney: true,
    ),
    Account(
      id: 'deposit',
      name: 'Вклад',
      type: AccountType.deposit,
      balance: 50000,
      includeInAvailableMoney: false,
    ),
  ]);

  return data;
}

Transaction _expense(double amount, {String account = 'card', DateTime? date}) {
  return Transaction(
    id: newId(),
    type: TransactionType.expense,
    amount: amount,
    date: date ?? DateTime.now(),
    accountId: account,
    category: 'Продукты',
    priority: TransactionPriority.need,
  );
}

void main() {
  group('Форматирование', () {
    test('деньги', () {
      expect(formatMoney(15000), '15 000 ₽');
      expect(formatMoney(104072.72), '104 072,72 ₽');
      expect(formatMoney(-500), '−500 ₽');
      expect(formatMoney(0), '0 ₽');
    });

    test('разбор суммы', () {
      expect(parseMoney('1 500,50'), 1500.5);
      expect(parseMoney('1500.5'), 1500.5);
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
    });

    test('прибавление месяцев', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
      expect(addMonths(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 15));
      expect(addMonths(DateTime(2026, 5, 15), 12), DateTime(2027, 5, 15));
    });

    test('склонения', () {
      expect(plural(1, 'день', 'дня', 'дней'), 'день');
      expect(plural(3, 'день', 'дня', 'дней'), 'дня');
      expect(plural(11, 'день', 'дня', 'дней'), 'дней');
      expect(plural(21, 'день', 'дня', 'дней'), 'день');
    });
  });

  group('Операции', () {
    test('расход списывает деньги, удаление возвращает', () {
      final data = _dataWithAccounts();
      final t = _expense(1500);

      expect(data.addTransaction(t), isNull);
      expect(data.accounts.getById('card')!.balance, 8500);

      data.deleteTransaction(t);
      expect(data.accounts.getById('card')!.balance, 10000);
      expect(data.transactions.transactions, isEmpty);
    });

    test('нельзя потратить больше, чем есть', () {
      final data = _dataWithAccounts();

      expect(data.addTransaction(_expense(20000)), isNotNull);
      expect(data.accounts.getById('card')!.balance, 10000);
    });

    test('перевод между счетами', () {
      final data = _dataWithAccounts();

      final t = Transaction(
        id: newId(),
        type: TransactionType.transfer,
        amount: 3000,
        date: DateTime.now(),
        accountId: 'deposit',
        destinationAccountId: 'card',
      );

      expect(data.addTransaction(t), isNull);
      expect(data.accounts.getById('card')!.balance, 13000);
      expect(data.accounts.getById('deposit')!.balance, 47000);
    });

    test('изменение операции пересчитывает баланс', () {
      final data = _dataWithAccounts();
      final t = _expense(1000);

      data.addTransaction(t);

      final edited = Transaction(
        id: t.id,
        type: TransactionType.expense,
        amount: 2500,
        date: t.date,
        accountId: 'card',
        category: 'Продукты',
        priority: TransactionPriority.want,
      );

      expect(data.updateTransaction(t, edited), isNull);
      expect(data.accounts.getById('card')!.balance, 7500);
      expect(data.transactions.transactions.single.amount, 2500);
    });
  });

  group('Обязательные платежи', () {
    test('оплата ежемесячного платежа переносит дату', () {
      final data = _dataWithAccounts();

      final expense = MandatoryExpense(
        id: 'net',
        name: 'Интернет',
        amount: 700,
        dueDate: DateTime(2026, 10, 15),
        period: ExpensePeriod.monthly,
      );

      data.mandatory.addExpense(expense);

      final error = data.payMandatory(
        expense,
        amount: 700,
        accountId: 'card',
        date: DateTime(2026, 10, 14),
      );

      expect(error, isNull);
      expect(data.accounts.getById('card')!.balance, 9300);
      expect(data.mandatory.getById('net')!.dueDate, DateTime(2026, 11, 15));
      expect(data.mandatory.getById('net')!.isPaid, isFalse);
      expect(data.transactions.transactions.single.title, 'Интернет');
    });

    test('разовый платёж отмечается оплаченным', () {
      final data = _dataWithAccounts();

      final expense = MandatoryExpense(
        id: 'fine',
        name: 'Штраф',
        amount: 500,
        dueDate: DateTime(2026, 10, 1),
        period: ExpensePeriod.once,
      );

      data.mandatory.addExpense(expense);
      data.payMandatory(
        expense,
        amount: 500,
        accountId: 'card',
        date: DateTime(2026, 10, 1),
      );

      expect(data.mandatory.getById('fine')!.isPaid, isTrue);
      expect(data.mandatory.unpaidExpenses, isEmpty);
    });
  });

  group('Дневной бюджет', () {
    test('учитывает обязательные платежи и оставшиеся дни', () {
      final data = _dataWithAccounts();

      data.mandatory.addExpense(
        MandatoryExpense(
          id: 'a',
          name: 'Коммуналка',
          amount: 4000,
          dueDate: DateTime(2026, 9, 25),
          period: ExpensePeriod.monthly,
        ),
      );
      // Платёж в следующем месяце не учитывается.
      data.mandatory.addExpense(
        MandatoryExpense(
          id: 'b',
          name: 'Страховка',
          amount: 48000,
          dueDate: DateTime(2027, 5, 15),
          period: ExpensePeriod.yearly,
        ),
      );

      // 21 сентября: осталось 10 дней (21–30).
      final budget = data.budgetFor(DateTime(2026, 9, 21, 12));

      expect(budget.available, 10000);
      expect(budget.mandatoryDue, 4000);
      expect(budget.daysLeft, 10);
      // На страховку откладываем 48 000 / 9 мес. (сен…май) = 5 333,33.
      expect(budget.reservesToSave, closeTo(5333.33, 0.01));
      expect(budget.dailyLimit, closeTo(66.67, 0.01));
    });

    test('траты сегодня уменьшают остаток, но не лимит', () {
      final data = _dataWithAccounts();
      final now = DateTime(2026, 9, 21, 12);

      data.addTransaction(_expense(200, date: now));

      final budget = data.budgetFor(now);

      expect(budget.dailyLimit, 1000);
      expect(budget.spentToday, 200);
      expect(budget.leftToday, 800);
    });
  });

  group('Резервная копия', () {
    test('экспорт и восстановление', () {
      final data = _dataWithAccounts();
      data.addTransaction(_expense(1234.56));

      final json = data.exportJson();

      final restored = AppData.inMemory();
      restored.importJson(json);

      expect(restored.accounts.accounts.length, 2);
      expect(restored.accounts.getById('card')!.balance, 8765.44);
      expect(restored.transactions.transactions.single.amount, 1234.56);
    });

    test('чужой текст не принимается', () {
      final data = _dataWithAccounts();

      expect(() => data.importJson('привет'), throwsFormatException);
      expect(() => data.importJson('{"a": 1}'), throwsFormatException);
      expect(data.accounts.accounts.length, 2);
    });
  });

  group('Вклады', () {
    AppData depositData({bool capitalization = true}) {
      final data = AppData.inMemory();
      data.accounts.replaceAll([
        Account(
          id: 'card',
          name: 'Карта',
          type: AccountType.debitCard,
          balance: 50000,
          includeInAvailableMoney: true,
        ),
      ]);
      data.addAccount(
        Account(
          id: 'dep',
          name: 'Вклад',
          type: AccountType.deposit,
          balance: 100000,
          includeInAvailableMoney: false,
          openDate: DateTime(2026, 9, 1),
          deposit: DepositInfo(
            initialAmount: 100000,
            rate: 12,
            payoutDay: 1,
            capitalization: capitalization,
            interestAccountId: 'card',
            lastAccrualDate: DateTime(2026, 9, 1),
          ),
        ),
        now: DateTime(2026, 9, 1),
      );
      return data;
    }

    test('проценты учитывают пополнение в середине месяца', () {
      final data = depositData();

      // 10 сентября пополнили на 20 000.
      expect(
        data.addTransaction(
          Transaction(
            id: newId(),
            type: TransactionType.transfer,
            amount: 20000,
            date: DateTime(2026, 9, 10, 15),
            accountId: 'card',
            destinationAccountId: 'dep',
          ),
        ),
        isNull,
      );

      expect(data.accrueInterest(DateTime(2026, 10, 1, 8)), 1);

      // 2–10 сентября: 9 дней от 100 000, 11 сен – 1 окт: 21 день от 120 000.
      final expected = (100000 * 9 + 120000 * 21) * 0.12 / 365;
      final interest = data.interestOf('dep').single;

      expect(interest.amount, closeTo(expected, 0.01));
      expect(interest.accountId, 'dep');
      expect(
        data.accounts.getById('dep')!.balance,
        closeTo(120000 + expected, 0.01),
      );
      expect(
        data.accounts.getById('dep')!.deposit!.lastAccrualDate,
        DateTime(2026, 10, 1),
      );

      // Повторный запуск в тот же день ничего не начисляет.
      expect(data.accrueInterest(DateTime(2026, 10, 1, 20)), 0);
    });

    test('капитализация: следующий месяц считается от новой суммы', () {
      final data = depositData();

      expect(data.accrueInterest(DateTime(2026, 11, 2)), 2);

      final list = data.interestOf('dep');
      final september = 100000 * 0.12 * 30 / 365;
      final october = (100000 + september) * 0.12 * 31 / 365;

      expect(
        list.map((t) => t.amount).reduce((a, b) => a + b),
        closeTo(september + october, 0.02),
      );
    });

    test('без капитализации проценты приходят на карту', () {
      final data = depositData(capitalization: false);

      data.accrueInterest(DateTime(2026, 10, 1));

      final interest = data.interestOf('dep').single;
      expect(interest.accountId, 'card');
      expect(data.accounts.getById('dep')!.balance, 100000);
      expect(
        data.accounts.getById('card')!.balance,
        closeTo(50000 + 100000 * 0.12 * 30 / 365, 0.01),
      );
    });

    test('вклад, открытый давно, не начисляет прошлые проценты', () {
      final data = AppData.inMemory();
      data.addAccount(
        Account(
          id: 'old',
          name: 'Старый вклад',
          type: AccountType.deposit,
          balance: 104072.72,
          includeInAvailableMoney: false,
          openDate: DateTime(2026, 1, 27),
          deposit: DepositInfo(
            initialAmount: 100000,
            rate: 16,
            payoutDay: 27,
            lastAccrualDate: DateTime(2026, 1, 27),
          ),
        ),
        now: DateTime(2026, 10, 17),
      );

      expect(
        data.accounts.getById('old')!.deposit!.lastAccrualDate,
        DateTime(2026, 9, 27),
      );
      expect(data.accrueInterest(DateTime(2026, 10, 17)), 0);
      expect(data.accrueInterest(DateTime(2026, 10, 27)), 1);
      expect(
        data.interestOf('old').single.amount,
        closeTo(104072.72 * 0.16 * 30 / 365, 0.01),
      );
    });

    test('со вклада без права снятия нельзя снять деньги', () {
      final data = depositData();

      final error = data.addTransaction(
        Transaction(
          id: newId(),
          type: TransactionType.transfer,
          amount: 1000,
          date: DateTime(2026, 9, 15),
          accountId: 'dep',
          destinationAccountId: 'card',
        ),
      );

      expect(error, isNotNull);
    });

    test('вклад не входит в доступные деньги, но входит в капитал', () {
      final data = depositData();

      expect(data.accounts.availableMoney, 50000);
      expect(data.accounts.depositMoney, 100000);
      expect(data.accounts.totalMoney, 150000);
    });
  });

  group('Корректировка и закрытие', () {
    test('корректировка меняет баланс и остаётся в истории', () {
      final data = _dataWithAccounts();

      expect(
        data.adjustBalance('card', 10500, reason: 'Забыла кэшбэк'),
        isNull,
      );
      expect(data.accounts.getById('card')!.balance, 10500);

      final t = data.transactions.transactions.single;
      expect(t.type, TransactionType.adjustment);
      expect(t.amount, 500);
      expect(t.comment, 'Забыла кэшбэк');

      data.deleteTransaction(t);
      expect(data.accounts.getById('card')!.balance, 10000);
    });

    test('баланс на дату считается по истории', () {
      final data = _dataWithAccounts();
      data.addTransaction(_expense(1000, date: DateTime(2026, 9, 10)));
      data.addTransaction(_expense(500, date: DateTime(2026, 9, 20)));

      expect(data.balanceAt('card', DateTime(2026, 9, 9)), 10000);
      expect(data.balanceAt('card', DateTime(2026, 9, 15)), 9000);
      expect(data.balanceAt('card', DateTime(2026, 9, 25)), 8500);
    });

    test('счёт с деньгами закрыть нельзя', () {
      final data = _dataWithAccounts();

      expect(data.closeAccount('card'), isNotNull);
      data.adjustBalance('card', 0);
      expect(data.closeAccount('card'), isNull);
      expect(data.accounts.getById('card')!.isClosed, isTrue);
      expect(data.addTransaction(_expense(1)), isNotNull);
    });
  });

  group('Резервы и цели', () {
    test('редкий платёж: рекомендация и резерв в бюджете', () {
      final data = _dataWithAccounts();
      final now = DateTime(2026, 10, 17);
      final osago = MandatoryExpense(
        id: 'osago',
        name: 'ОСАГО',
        amount: 48000,
        dueDate: DateTime(2027, 5, 15),
        period: ExpensePeriod.yearly,
      );
      data.mandatory.addExpense(osago);

      // Октябрь…май = 8 месяцев → 6 000 в месяц.
      expect(data.reserveMonthlyNeed(osago, now), 6000);

      expect(data.addToReserve(osago, 2000, date: now), isNull);
      final updated = data.mandatory.getById('osago')!;
      expect(updated.reserved, 2000);
      // Рекомендация в этом месяце не меняется, остаток — 4 000.
      expect(data.reserveMonthlyNeed(updated, now), 6000);
      expect(data.reserveLeftThisMonth(updated, now), 4000);

      final budget = data.budgetFor(now);
      expect(budget.reservesHeld, 2000);
      expect(budget.reservesToSave, 4000);
      expect(budget.free, 10000 - 6000);

      // После оплаты резерв обнуляется.
      data.adjustBalance('card', 50000);
      data.payMandatory(
        updated,
        amount: 48000,
        accountId: 'card',
        date: DateTime(2027, 5, 10),
      );
      expect(data.mandatory.getById('osago')!.reserved, 0);
    });

    test('цель: сколько откладывать и перевод на накопительный счёт', () {
      final data = _dataWithAccounts();
      data.accounts.addAccount(
        Account(
          id: 'save',
          name: 'Накопительный',
          type: AccountType.savings,
          balance: 25000,
          includeInAvailableMoney: false,
        ),
      );
      final now = DateTime(2026, 10, 1);
      final goal = Goal(
        id: 'g',
        name: 'Подушка',
        target: 100000,
        deadline: DateTime(2027, 3, 31),
        accountId: 'save',
        contributions: [
          GoalContribution(
            id: '1',
            date: DateTime(2026, 9, 1),
            amount: 25000,
          ),
        ],
        createdAt: DateTime(2026, 9, 1),
      );
      data.goals.add(goal);

      // Осталось 75 000 на 6 месяцев (окт…мар) → 12 500.
      expect(goal.monthlyNeed(now), 12500);

      expect(
        data.contributeToGoal(goal, 5000, date: now, fromAccountId: 'card'),
        isNull,
      );
      expect(data.accounts.getById('card')!.balance, 5000);
      expect(data.accounts.getById('save')!.balance, 30000);

      final updated = data.goals.getById('g')!;
      expect(updated.current, 30000);
      expect(updated.leftThisMonth(now), 7500);
    });
  });

  group('Доходы и период бюджета', () {
    test('бюджет считается до следующей зарплаты', () {
      final data = _dataWithAccounts();
      data.plannedIncomes.add(
        PlannedIncome(
          id: 'salary',
          name: 'Зарплата',
          amount: 50000,
          nextDate: DateTime(2026, 10, 25),
        ),
      );

      final budget = data.budgetFor(DateTime(2026, 10, 17));

      expect(budget.periodEnd, DateTime(2026, 10, 24));
      expect(budget.daysLeft, 8);
      expect(budget.dailyLimit, 1250);
    });

    test('получение дохода переносит дату и распределяет деньги', () {
      final data = _dataWithAccounts();
      final salary = PlannedIncome(
        id: 'salary',
        name: 'Зарплата',
        amount: 50000,
        nextDate: DateTime(2026, 10, 5),
        accountId: 'card',
      );
      data.plannedIncomes.add(salary);
      data.mandatory.addExpense(
        MandatoryExpense(
          id: 'net',
          name: 'Интернет',
          amount: 700,
          dueDate: DateTime(2026, 10, 15),
          period: ExpensePeriod.monthly,
        ),
      );

      expect(
        data.receiveIncome(
          salary,
          amount: 50000,
          accountId: 'card',
          date: DateTime(2026, 10, 5),
        ),
        isNull,
      );
      expect(data.accounts.getById('card')!.balance, 60000);
      expect(
        data.plannedIncomes.getById('salary')!.nextDate,
        DateTime(2026, 11, 5),
      );

      final plan = data.distributionFor(50000, DateTime(2026, 10, 5));
      expect(plan.lines.first.amount, 700);
      expect(plan.free, 49300);
    });
  });

  group('Аналитика', () {
    test('итоги месяца: доходы, расходы, накопления', () {
      final data = _dataWithAccounts();
      data.accounts.addAccount(
        Account(
          id: 'save',
          name: 'Накопления',
          type: AccountType.savings,
          balance: 0,
          includeInAvailableMoney: false,
        ),
      );
      final day = DateTime(2026, 9, 10);
      data.addTransaction(
        Transaction(
          id: newId(),
          type: TransactionType.income,
          amount: 50000,
          date: day,
          accountId: 'card',
          incomeSource: 'Зарплата',
        ),
      );
      data.addTransaction(_expense(32450, date: day));
      data.addTransaction(
        Transaction(
          id: newId(),
          type: TransactionType.transfer,
          amount: 10000,
          date: day,
          accountId: 'card',
          destinationAccountId: 'save',
        ),
      );

      final summary = Insights(data, DateTime(2026, 9, 30)).month(2026, 9);
      expect(summary.income, 50000);
      expect(summary.expense, 32450);
      expect(summary.savings, 10000);
      expect(summary.remainder, 7550);
    });

    test('повторяющиеся расходы находятся по месяцам', () {
      final data = _dataWithAccounts();
      data.adjustBalance('card', 100000, date: DateTime(2026, 5, 1));
      for (final month in [6, 7, 8, 9]) {
        data.addTransaction(
          Transaction(
            id: newId(),
            type: TransactionType.expense,
            amount: 299,
            date: DateTime(2026, month, 3),
            accountId: 'card',
            category: 'Личное',
            subcategory: 'Развлечения',
            comment: 'Подписка на музыку',
          ),
        );
      }

      final items = Insights(data, DateTime(2026, 10, 5)).recurring();
      final music = items.firstWhere((i) => i.title == 'Подписка на музыку');
      expect(music.averageMonthly, 299);
      expect(music.looksLikePayment, isTrue);
      expect(music.typicalDay, 3);
    });

    test('прогноз и календарь не падают на пустых данных', () {
      final data = AppData.inMemory();
      final insights = Insights(data, DateTime(2026, 10, 17));

      expect(insights.forecast(3).capital, 0);
      expect(insights.events(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
          isEmpty);
      expect(insights.habits(), isEmpty);
    });
  });

  group('Совместимость', () {
    test('старые данные читаются без новых полей', () {
      final old = {
        'app': 'moy-budget',
        'version': 1,
        'accounts': [
          {
            'id': '1',
            'name': 'Т-Банк',
            'type': 'debitCard',
            'balance': 1500.5,
            'includeInAvailableMoney': true,
          },
        ],
        'categories': [
          {'id': 'products', 'name': 'Продукты', 'isDefault': true},
        ],
        'mandatoryExpenses': [
          {
            'id': 'm',
            'name': 'Интернет',
            'amount': 700,
            'dueDate': '2026-10-15T00:00:00.000',
            'period': 'monthly',
          },
        ],
        'transactions': [
          {
            'id': 't',
            'type': 'expense',
            'amount': 100,
            'date': '2026-09-01T10:00:00.000',
            'accountId': '1',
            'category': 'Продукты',
            'priority': 'need',
          },
        ],
      };

      final data = AppData.inMemory();
      data.importJson(jsonEncode(old));

      final account = data.accounts.getById('1')!;
      expect(account.currency, 'RUB');
      expect(account.isClosed, isFalse);
      expect(data.mandatory.getById('m')!.reserveLog, isEmpty);
      expect(data.transactions.transactions.single.subcategory, isNull);
      expect(data.goals.goals, isEmpty);

      // И новые данные переживают экспорт/импорт.
      final again = AppData.inMemory()..importJson(data.exportJson());
      expect(again.accounts.getById('1')!.balance, 1500.5);
    });
  });
}
