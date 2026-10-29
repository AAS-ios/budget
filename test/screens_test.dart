// Дымовые тесты интерфейса: каждый экран и диалог открывается
// на демо-данных без ошибок отрисовки (ширина айфона).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appforios/main.dart';
import 'package:appforios/models/account.dart';
import 'package:appforios/models/goal.dart';
import 'package:appforios/models/mandatory_expense.dart';
import 'package:appforios/models/planned_income.dart';
import 'package:appforios/models/transaction.dart';
import 'package:appforios/screens/account_screen.dart';
import 'package:appforios/screens/add_transaction_screen.dart';
import 'package:appforios/screens/analytics_screen.dart';
import 'package:appforios/screens/budget_screen.dart';
import 'package:appforios/screens/calendar_screen.dart';
import 'package:appforios/screens/categories_screen.dart';
import 'package:appforios/screens/forecast_screen.dart';
import 'package:appforios/screens/goals_screen.dart';
import 'package:appforios/screens/mandatory_expenses_screen.dart';
import 'package:appforios/screens/recurring_screen.dart';
import 'package:appforios/screens/transactions_screen.dart';
import 'package:appforios/services/app_data.dart';
import 'package:appforios/utils/format.dart';

AppData demoData() {
  final data = AppData.inMemory();
  final now = DateTime.now();
  final today = dateOnly(now);

  data.accounts.replaceAll([
    Account(
      id: 'card',
      name: 'Т-Банк',
      type: AccountType.debitCard,
      balance: 300000,
      includeInAvailableMoney: true,
    ),
    Account(
      id: 'cash',
      name: 'Наличные',
      type: AccountType.cash,
      balance: 3000,
      includeInAvailableMoney: true,
    ),
    Account(
      id: 'save',
      name: 'Накопительный',
      type: AccountType.savings,
      balance: 20000,
      includeInAvailableMoney: false,
    ),
    Account(
      id: 'usd',
      name: 'Доллары',
      type: AccountType.cash,
      balance: 150,
      includeInAvailableMoney: false,
      currency: 'USD',
    ),
  ]);

  data.addAccount(
    Account(
      id: 'dep',
      name: 'Вклад в Сбере',
      type: AccountType.deposit,
      balance: 104072.72,
      includeInAvailableMoney: false,
      openDate: addMonths(today, -5),
      deposit: DepositInfo(
        bank: 'Сбербанк',
        initialAmount: 100000,
        rate: 16,
        payoutDay: addMonths(today, -5).day,
        endDate: addMonths(today, 7),
        lastAccrualDate: addMonths(today, -5),
      ),
    ),
    now: now,
  );

  // Четыре месяца истории.
  for (var back = 4; back >= 0; back--) {
    final month = addMonths(DateTime(today.year, today.month), -back);
    DateTime day(int d) {
      final date = withDay(month, d);
      return date.isAfter(today) ? today : date;
    }

    data.addTransaction(Transaction(
      id: newId(),
      type: TransactionType.income,
      amount: 50000,
      date: day(5),
      accountId: 'card',
      incomeSource: 'Зарплата',
    ));
    for (final (category, sub, amount) in [
      ('Еда', 'Продукты', 3000.0),
      ('Еда', 'Кафе', 900.0),
      ('Транспорт', 'Такси', 450.0),
      ('Личное', 'Развлечения', 299.0),
    ]) {
      for (final d in [3, 9, 16, 23]) {
        data.addTransaction(Transaction(
          id: newId(),
          type: TransactionType.expense,
          amount: amount,
          date: day(d),
          accountId: 'card',
          category: category,
          subcategory: sub,
          priority: TransactionPriority.need,
          comment: sub == 'Развлечения' && d == 3 ? 'Подписка' : '',
        ));
      }
    }
    data.addTransaction(Transaction(
      id: newId(),
      type: TransactionType.transfer,
      amount: 5000,
      date: day(6),
      accountId: 'card',
      destinationAccountId: 'save',
    ));
  }

  data.adjustBalance('cash', 2500, reason: 'Пересчитала кошелёк');

  data.mandatory.replaceAll([
    MandatoryExpense(
      id: 'utilities',
      name: 'Коммунальные',
      amount: 5000,
      dueDate: today.add(const Duration(days: 2)),
      period: ExpensePeriod.monthly,
      isVariableAmount: true,
      category: 'Дом',
      subcategory: 'Коммунальные',
      accountId: 'cash',
    ),
    MandatoryExpense(
      id: 'net',
      name: 'Интернет',
      amount: 700,
      dueDate: today.subtract(const Duration(days: 1)),
      period: ExpensePeriod.monthly,
    ),
    MandatoryExpense(
      id: 'osago',
      name: 'ОСАГО',
      amount: 48000,
      dueDate: addMonths(today, 7),
      period: ExpensePeriod.yearly,
      reserveLog: [ReserveEntry(date: today, amount: 2000)],
    ),
  ]);
  data.payMandatory(
    data.mandatory.getById('utilities')!,
    amount: 4873,
    accountId: 'card',
    date: addMonths(today, -1),
  );

  data.goals.add(Goal(
    id: 'cushion',
    name: 'Подушка безопасности',
    target: 100000,
    deadline: addMonths(today, 6),
    accountId: 'save',
    contributions: [
      GoalContribution(id: 'c1', date: addMonths(today, -2), amount: 15000),
      GoalContribution(id: 'c2', date: addMonths(today, -1), amount: 5000),
    ],
    createdAt: addMonths(today, -2),
  ));
  data.goals.add(Goal(
    id: 'trip',
    name: 'Отпуск',
    target: 60000,
    monthlyPlan: 5000,
    accountId: 'card',
    createdAt: today,
  ));

  data.plannedIncomes.add(PlannedIncome(
    id: 'salary',
    name: 'Зарплата',
    amount: 50000,
    nextDate: today.add(const Duration(days: 1)),
    accountId: 'card',
  ));

  final food = data.categories.getByName('Еда')!;
  data.categories.updateCategory(food.copyWith(monthlyLimit: 10000));
  final transport = data.categories.getByName('Транспорт')!;
  data.categories.updateCategory(transport.copyWith(monthlyLimit: 500));

  return data;
}

Widget wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void phone(WidgetTester tester, {double height = 4000}) {
  tester.view.physicalSize = Size(390 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> openScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(wrap(screen));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Открыть диалог через функцию, которой нужен BuildContext.
Future<void> openDialog(
  WidgetTester tester,
  void Function(BuildContext context) show,
) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    wrap(
      Scaffold(
        body: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  show(ctx);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('приложение: все вкладки', (tester) async {
    phone(tester, height: 900);
    final data = demoData();
    await tester.pumpWidget(BudgetApp(data: data));
    await tester.pumpAndSettle();

    for (final tab in ['Бюджет', 'Операции', 'Счета', 'Ещё', 'Главная']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  group('экраны', () {
    late AppData data;
    setUp(() => data = demoData());

    final screens = <String, Widget Function(AppData)>{
      'Бюджет': (d) => BudgetScreen(data: d),
      'Счета': (d) => AccountScreen(data: d),
      'Вклад': (d) => AccountDetailsScreen(data: d, accountId: 'dep'),
      'Карта': (d) => AccountDetailsScreen(data: d, accountId: 'card'),
      'Цели': (d) => GoalsScreen(data: d),
      'Цель': (d) => GoalDetailsScreen(data: d, goalId: 'cushion'),
      'Календарь': (d) => CalendarScreen(data: d),
      'Прогноз': (d) => ForecastScreen(data: d),
      'Платежи': (d) => MandatoryExpensesScreen(data: d),
      'Аналитика': (d) => AnalyticsScreen(data: d),
      'Повторяющиеся': (d) => RecurringScreen(data: d),
      'История': (d) => TransactionsScreen(data: d),
      'Категории': (d) => CategoriesScreen(data: d),
      'Новый расход': (d) => AddTransactionScreen(data: d),
      'Новый перевод': (d) => AddTransactionScreen(
            data: d,
            initialType: TransactionType.transfer,
          ),
    };

    screens.forEach((name, build) {
      testWidgets(name, (tester) async {
        phone(tester);
        await openScreen(tester, build(data));
      });
    });

    testWidgets('редактирование корректировки и процентов', (tester) async {
      phone(tester);
      final adjustment = data.transactions.transactions
          .firstWhere((t) => t.type == TransactionType.adjustment);
      await openScreen(
        tester,
        AddTransactionScreen(data: data, existing: adjustment),
      );

      data.accrueInterest(addMonths(DateTime.now(), 1));
      final interest = data.transactions.transactions
          .firstWhere((t) => t.isInterest);
      await openScreen(
        tester,
        AddTransactionScreen(data: data, existing: interest),
      );
    });

    testWidgets('аналитика: раскрытие категории и периоды', (tester) async {
      phone(tester);
      await openScreen(tester, AnalyticsScreen(data: data));
      await tester.tap(find.text('6 месяцев'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Еда ▸').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('операции: поиск и один день', (tester) async {
      phone(tester);
      await openScreen(tester, TransactionsScreen(data: data));
      expect(find.textContaining('потрачено'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'кафе');
      await tester.pumpAndSettle();
      expect(find.textContaining('по всем месяцам'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('потрачено').first);
      await tester.pumpAndSettle();
      expect(find.text('Потрачено за день'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('календарь: выбор дня', (tester) async {
      phone(tester);
      await openScreen(tester, CalendarScreen(data: data));
      await tester.tap(find.text('${DateTime.now().day}').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('диалоги', () {
    late AppData data;
    setUp(() => data = demoData());

    final dialogs = <String, void Function(BuildContext, AppData)>{
      'новый счёт': (c, d) => showAccountDialog(c, d),
      'изменить вклад': (c, d) =>
          showAccountDialog(c, d, account: d.accounts.getById('dep')),
      'корректировка': (c, d) =>
          showAdjustDialog(c, d, d.accounts.getById('card')!),
      'новая цель': (c, d) => showGoalDialog(c, d),
      'изменить цель': (c, d) =>
          showGoalDialog(c, d, goal: d.goals.getById('cushion')),
      'отложить на цель': (c, d) =>
          showContributeDialog(c, d, d.goals.getById('cushion')!),
      'новый платёж': (c, d) => showExpenseDialog(c, d),
      'изменить ОСАГО': (c, d) =>
          showExpenseDialog(c, d, expense: d.mandatory.getById('osago')),
      'оплата': (c, d) =>
          showPaymentDialog(c, d, d.mandatory.getById('utilities')!),
      'резерв': (c, d) =>
          showReserveDialog(c, d, d.mandatory.getById('osago')!),
      'история оплат': (c, d) =>
          showPaymentHistory(c, d, d.mandatory.getById('utilities')!),
      'ожидаемый доход': (c, d) => showPlannedIncomeDialog(c, d),
      'доход пришёл': (c, d) =>
          showReceiveIncomeDialog(c, d, d.plannedIncomes.items.first),
      'распределение': (c, d) =>
          showDistributionSheet(c, d, 50000, DateTime.now()),
      'добавить операцию': (c, d) => showAddOperationSheet(c, d),
    };

    dialogs.forEach((name, show) {
      testWidgets(name, (tester) async {
        phone(tester, height: 900);
        await openDialog(tester, (context) => show(context, data));
      });
    });
  });
}
