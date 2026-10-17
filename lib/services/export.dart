import '../models/account.dart';
import '../models/mandatory_expense.dart';
import '../models/transaction.dart';
import '../utils/format.dart';
import 'app_data.dart';
import 'insights.dart';

/// Выгрузки в CSV, которые открываются в Excel и «Числах».
///
/// Разделитель — точка с запятой, дробная часть — через запятую,
/// в начале файла метка UTF-8: так русский Excel открывает файл
/// без «кракозябр» и сразу по столбцам.
class CsvExport {
  final AppData data;
  final DateTime now;

  CsvExport(this.data, this.now);

  static String _cell(Object? value) {
    final text = switch (value) {
      null => '',
      double v => v.toStringAsFixed(2).replaceAll('.', ','),
      DateTime d => formatDate(d),
      bool b => b ? 'да' : 'нет',
      _ => value.toString(),
    };

    if (text.contains(';') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static String _table(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer('﻿');
    buffer.writeln(header.map(_cell).join(';'));
    for (final row in rows) {
      buffer.writeln(row.map(_cell).join(';'));
    }
    return buffer.toString();
  }

  String _accountName(String? id) =>
      id == null ? '' : data.accounts.nameOf(id);

  static String typeTitle(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Расход';
      case TransactionType.income:
        return 'Доход';
      case TransactionType.transfer:
        return 'Перевод';
      case TransactionType.adjustment:
        return 'Корректировка';
    }
  }

  String transactions() {
    return _table(
      [
        'Дата',
        'Тип',
        'Сумма',
        'Валюта',
        'Счёт',
        'На счёт',
        'Категория',
        'Подкатегория',
        'Источник дохода',
        'Приоритет',
        'Обязательный платёж',
        'Комментарий',
      ],
      data.transactions.transactions.reversed.map((t) {
        final signed = switch (t.type) {
          TransactionType.expense => -t.amount,
          _ => t.amount,
        };
        return [
          t.date,
          t.isInterest ? 'Проценты по вкладу' : typeTitle(t.type),
          signed,
          data.accounts.getById(t.accountId)?.currency ?? 'RUB',
          _accountName(t.accountId),
          _accountName(t.destinationAccountId),
          t.category,
          t.subcategory,
          t.incomeSource,
          t.priority?.title,
          t.isMandatoryPayment,
          t.comment,
        ];
      }),
    );
  }

  String accounts() {
    return _table(
      [
        'Название',
        'Тип',
        'Валюта',
        'Баланс',
        'Входит в доступные',
        'Дата открытия',
        'Статус',
        'Банк',
        'Ставка, %',
        'Капитализация',
        'Окончание вклада',
        'Комментарий',
      ],
      data.accounts.accounts.map((a) {
        final d = a.deposit;
        return [
          a.name,
          a.type.title,
          a.currency,
          a.balance,
          a.type != AccountType.deposit && a.includeInAvailableMoney,
          a.openDate,
          a.isClosed ? 'закрыт' : 'активен',
          d?.bank,
          d?.rate,
          d?.capitalization,
          d?.endDate,
          a.comment,
        ];
      }),
    );
  }

  String deposits() {
    final insights = Insights(data, now);
    return _table(
      [
        'Вклад',
        'Банк',
        'Ставка, %',
        'Внесено',
        'Начислено процентов',
        'За этот год',
        'Баланс',
        'Фактическая доходность, %',
        'Прогноз на дату',
        'Прогноз баланса',
        'Прогноз процентов',
      ],
      data.accounts.accounts
          .where((a) => a.type == AccountType.deposit)
          .map((a) {
        final s = insights.depositStats(a);
        return [
          a.name,
          a.deposit?.bank,
          a.deposit?.rate,
          s.deposited,
          s.interestTotal,
          s.interestThisYear,
          a.balance,
          s.effectiveYield,
          s.projectionDate,
          s.projection.balance,
          s.projection.interest,
        ];
      }),
    );
  }

  String mandatory() {
    String period(MandatoryExpense e) => e.periodText;

    return _table(
      [
        'Платёж',
        'Плановая сумма',
        'Средняя фактическая',
        'Ближайшая дата',
        'Периодичность',
        'Сумма меняется',
        'Категория',
        'Подкатегория',
        'Счёт',
        'Отложено в резерв',
        'Откладывать в месяц',
        'Оплачен',
      ],
      data.mandatory.expenses.map(
        (e) => [
          e.name,
          e.amount,
          data.averagePayment(e.id),
          e.dueDate,
          period(e),
          e.isVariableAmount,
          e.category,
          e.subcategory,
          _accountName(e.accountId),
          e.reserved,
          data.reserveMonthlyNeed(e, now),
          e.isPaid,
        ],
      ),
    );
  }

  String goals() {
    return _table(
      [
        'Цель',
        'Целевая сумма',
        'Накоплено',
        'Осталось',
        'Срок',
        'Откладывать в месяц',
        'Приоритет',
        'Счёт',
        'В архиве',
      ],
      data.goals.goals.map(
        (g) => [
          g.name,
          g.target,
          g.current,
          g.remaining,
          g.deadline,
          g.monthlyNeed(now),
          g.priority.name,
          _accountName(g.accountId),
          g.isArchived,
        ],
      ),
    );
  }

  /// Планы по категориям и факт за текущий месяц.
  String budgets() {
    return _table(
      ['Категория', 'План на месяц', 'Потрачено в ${monthName(now.month).toLowerCase()}', 'Остаток'],
      data.categories.topLevel.map((c) {
        final spent = data.categorySpent(c.name, now.year, now.month);
        final limit = c.monthlyLimit;
        return [
          c.name,
          limit,
          spent,
          limit == null ? null : roundMoney(limit - spent),
        ];
      }),
    );
  }

  /// Итоги по месяцам и расходы по категориям за последний год.
  String analytics() {
    final insights = Insights(data, now);
    final months = insights.lastMonths(12);
    final totals = months
        .map((m) => insights.categoryTotalsForMonth(m.month))
        .toList();
    final names = <String>{for (final t in totals) ...t.keys}.toList()..sort();

    return _table(
      [
        'Месяц',
        'Доходы',
        'Расходы',
        'Накопления',
        'Остаток',
        'Проценты по вкладам',
        ...names,
      ],
      List.generate(months.length, (i) {
        final m = months[i];
        return [
          monthTitle(m.month.year, m.month.month),
          m.income,
          m.expense,
          m.savings,
          roundMoney(m.remainder),
          m.interest,
          ...names.map((n) => totals[i][n] ?? 0.0),
        ];
      }),
    );
  }
}
