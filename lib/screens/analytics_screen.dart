import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'forecast_screen.dart';
import 'recurring_screen.dart';
import 'transactions_screen.dart';

/// Аналитика: итоги, структура расходов, сравнения, средние,
/// закономерности, накопления и вклады.
class AnalyticsScreen extends StatefulWidget {
  final AppData data;

  const AnalyticsScreen({super.key, required this.data});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late DateTime month;
  int periodMonths = 1;
  final Set<String> expanded = {};

  AppData get data => widget.data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) => _build(context),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final now = DateTime.now();
    final insights = Insights(data, now);
    final summary = insights.month(month.year, month.month);
    final previous = addMonths(month, -1);
    final previousSummary = insights.month(previous.year, previous.month);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        AppCard(
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Icon(Icons.insights, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              Expanded(child: Text(insights.maturityText)),
            ],
          ),
        ),

        // ── Итоги месяца
        const SizedBox(height: 8),
        MonthSwitcher(
          month: month,
          onChanged: (value) => setState(() => month = value),
        ),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatRow('Доходы', formatMoney(summary.income),
                  color: kIncomeColor, fontSize: 15),
              StatRow('Расходы', formatMoney(summary.expense),
                  color: kExpenseColor, fontSize: 15),
              StatRow('Накопления', formatMoney(summary.savings),
                  color: kSavingsColor, fontSize: 15),
              const Divider(height: 18),
              StatRow(
                summary.remainder >= 0 ? 'Остаток' : 'Расходы больше доходов',
                formatMoney(summary.remainder.abs()),
                bold: true,
                fontSize: 16,
                color: summary.remainder >= 0 ? null : kExpenseColor,
              ),
              if (summary.interest > 0)
                StatRow('Проценты по вкладам', formatMoney(summary.interest),
                    color: kIncomeColor),
              if (summary.income > 0 && summary.savings > 0)
                Hint(
                  'Отложено ${(summary.savings / summary.income * 100).round()}% '
                  'от доходов.',
                ),
              if (previousSummary.expense > 0 && summary.expense > 0)
                Hint(_compareText(summary.expense, previousSummary.expense)),
            ],
          ),
        ),

        // ── Динамика
        const SizedBox(height: 16),
        const SectionHeader(title: 'Динамика за полгода'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
          child: MonthBars(months: insights.lastMonths(6)),
        ),

        // ── Куда уходят деньги
        const SizedBox(height: 16),
        const SectionHeader(title: 'Куда уходят деньги'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (months, label) in [
                (1, 'Этот месяц'),
                (3, '3 месяца'),
                (6, '6 месяцев'),
                (12, 'Год'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: periodMonths == months,
                    onSelected: (_) => setState(() => periodMonths = months),
                  ),
                ),
            ],
          ),
        ),
        _whereMoneyGoes(insights, now),

        // ── Сравнение месяцев
        const SizedBox(height: 16),
        const SectionHeader(title: 'Сравнение месяцев'),
        _comparison(insights),

        // ── Средние
        const SizedBox(height: 16),
        const SectionHeader(title: 'Средние расходы'),
        _averages(insights),

        // ── Закономерности
        const SizedBox(height: 16),
        const SectionHeader(title: 'Закономерности'),
        _habits(insights),

        // ── Насколько траты были нужны
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Насколько траты были нужны · ${monthName(month.month)}',
        ),
        _priorities(),

        // ── Накопления
        const SizedBox(height: 16),
        const SectionHeader(title: 'Накопления'),
        _savings(insights, now),

        // ── Вклады
        if (insights.deposits.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(title: 'Вклады'),
          ...insights.deposits.map((account) {
            final stats = insights.depositStats(account);
            return AppCard(
              onTap: () => pushScreen(
                context,
                AccountDetailsScreen(data: data, accountId: account.id),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StatRow('Внесено', formatMoney(stats.deposited)),
                  StatRow('Проценты', formatMoney(stats.interestTotal),
                      color: kIncomeColor),
                  StatRow('Баланс', formatMoney(account.balance), bold: true),
                  if (stats.effectiveYield != null)
                    StatRow(
                      'Фактическая доходность',
                      '${formatPercent(stats.effectiveYield!, digits: 2)} годовых',
                    ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 16),
        MenuTile(
          icon: Icons.repeat,
          title: 'Повторяющиеся расходы',
          subtitle: 'Что уходит каждый месяц',
          onTap: () => pushScreen(context, RecurringScreen(data: data)),
        ),
        MenuTile(
          icon: Icons.trending_up,
          title: 'Прогноз',
          subtitle: 'Что будет с деньгами через 1–12 месяцев',
          onTap: () => pushScreen(context, ForecastScreen(data: data)),
        ),
        MenuTile(
          icon: Icons.list_alt,
          title: 'Все операции',
          onTap: () => pushScreen(context, TransactionsScreen(data: data)),
        ),
      ],
    );
  }

  Widget _whereMoneyGoes(Insights insights, DateTime now) {
    final from = insights.periodStart(periodMonths);
    final totals = insights.byCategory(from, now);
    final sum = totals.fold(0.0, (s, c) => s + c.total);

    if (totals.isEmpty) {
      return const EmptyHint('Расходов за этот период нет');
    }

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Расходы за ${periodMonths == 1 ? 'месяц' : '$periodMonths ${plural(periodMonths, 'месяц', 'месяца', 'месяцев')}'}'
            ' — ${formatMoneyRound(sum)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...totals.map((category) {
            final subs = category.sortedSubs;
            final isOpen = expanded.contains(category.name);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: subs.isEmpty
                      ? null
                      : () => setState(() {
                            if (!expanded.remove(category.name)) {
                              expanded.add(category.name);
                            }
                          }),
                  child: ShareBar(
                    title: subs.isEmpty
                        ? category.name
                        : '${category.name} ${isOpen ? '▾' : '▸'}',
                    amount: category.total,
                    total: sum,
                    color: kExpenseColor,
                  ),
                ),
                if (isOpen)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, bottom: 8),
                    child: Column(
                      children: [
                        ...subs.map(
                          (e) => StatRow('— ${e.key}', formatMoney(e.value)),
                        ),
                        if (category.total -
                                subs.fold(0.0, (s, e) => s + e.value) >
                            0.5)
                          StatRow(
                            '— без подкатегории',
                            formatMoney(
                              category.total -
                                  subs.fold(0.0, (s, e) => s + e.value),
                            ),
                          ),
                        if (periodMonths > 1)
                          Hint(
                            'В среднем ${formatMoneyRound(category.total / periodMonths)} в месяц',
                          ),
                      ],
                    ),
                  ),
              ],
            );
          }),
          if (totals.any((c) => c.subs.isNotEmpty))
            const Hint('Нажмите на категорию, чтобы увидеть подкатегории.'),
        ],
      ),
    );
  }

  Widget _comparison(Insights insights) {
    final months = insights.comparisonMonths;
    final totals = months.map(insights.categoryTotalsForMonth).toList();
    final names = <String>{for (final t in totals) ...t.keys}.toList()
      ..sort((a, b) {
        final sa = totals.fold(0.0, (s, t) => s + (t[a] ?? 0));
        final sb = totals.fold(0.0, (s, t) => s + (t[b] ?? 0));
        return sb.compareTo(sa);
      });

    if (names.isEmpty) {
      return const EmptyHint('Пока нечего сравнивать');
    }

    final texts = insights.comparisonTexts();
    const cellStyle = TextStyle(fontSize: 13);
    final headStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade700,
    );

    Widget cell(String text, {TextStyle? style, bool left = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          text,
          textAlign: left ? TextAlign.left : TextAlign.right,
          style: style ?? cellStyle,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    String short(double value) =>
        value == 0 ? '—' : formatMoneyRound(value).replaceAll(' ₽', '');

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: [
                  cell('Категория, ₽', style: headStyle, left: true),
                  ...months.map((m) => cell(monthName(m.month), style: headStyle)),
                ],
              ),
              ...names.take(10).map(
                    (name) => TableRow(
                      children: [
                        cell(name, left: true),
                        ...totals.map((t) => cell(short(t[name] ?? 0))),
                      ],
                    ),
                  ),
              TableRow(
                children: [
                  cell('Всего', style: headStyle, left: true),
                  ...totals.map(
                    (t) => cell(
                      short(t.values.fold(0.0, (s, v) => s + v)),
                      style: headStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (texts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...texts.map(
              (text) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $text', style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
          if (months.last.month == DateTime.now().month)
            const Hint('Текущий месяц ещё не закончился.'),
        ],
      ),
    );
  }

  Widget _averages(Insights insights) {
    if (insights.historyMonths == 0) {
      return const EmptyHint('Данных пока нет');
    }

    final minMax = insights.minMaxMonth();
    final byCategory = insights.averageByCategory().take(5).toList();
    final full = insights.fullMonths.length;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatRow('В месяц', formatMoneyRound(insights.averageMonthlyExpense()),
              bold: true),
          StatRow('В день', formatMoneyRound(insights.averageDailyExpense())),
          StatRow('Средний чек', formatMoneyRound(insights.averageCheck())),
          if (minMax != null) ...[
            StatRow(
              'Минимальный месяц',
              '${monthTitle(minMax.min.month.year, minMax.min.month.month)} · '
                  '${formatMoneyRound(minMax.min.expense)}',
            ),
            StatRow(
              'Максимальный месяц',
              '${monthTitle(minMax.max.month.year, minMax.max.month.month)} · '
                  '${formatMoneyRound(minMax.max.expense)}',
            ),
          ],
          if (byCategory.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'По категориям в месяц',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            ...byCategory.map(
              (e) => StatRow(e.key, formatMoneyRound(e.value)),
            ),
          ],
          Hint(
            full == 0
                ? 'Считается по текущему месяцу — после первого полного '
                    'месяца средние станут точнее.'
                : 'По $full полным '
                    '${plural(full, 'месяцу', 'месяцам', 'месяцам')}.',
          ),
        ],
      ),
    );
  }

  Widget _habits(Insights insights) {
    final habits = insights.habits();

    if (habits.isEmpty) {
      return EmptyHint(
        insights.historyMonths < 3
            ? 'Закономерности появятся, когда накопится история '
                'хотя бы за 3 месяца.'
            : 'Заметных закономерностей пока нет.',
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: habits
            .map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 18, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _priorities() {
    final store = data.transactions;
    final expense = store.expensesAmountForMonth(month.year, month.month);

    if (expense == 0) {
      return const EmptyHint('Расходов в этом месяце нет');
    }

    final priorities = {
      for (final priority in TransactionPriority.values)
        priority: store.expensesForPriority(priority, month.year, month.month),
    };
    final want = priorities[TransactionPriority.want] ?? 0;

    Color colorOf(TransactionPriority priority) {
      switch (priority) {
        case TransactionPriority.necessary:
          return Colors.red.shade400;
        case TransactionPriority.need:
          return Colors.orange.shade400;
        case TransactionPriority.want:
          return Colors.blue.shade400;
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          for (final priority in TransactionPriority.values)
            ShareBar(
              title: '${priority.emoji} ${priority.title}',
              amount: priorities[priority] ?? 0,
              total: expense,
              color: colorOf(priority),
            ),
          if (want > 0)
            Hint(
              'Покупки «можно было не брать» — ${formatMoney(want)}.',
            ),
        ],
      ),
    );
  }

  Widget _savings(Insights insights, DateTime now) {
    final months = insights.lastMonths(6);
    final average = insights.averageSavings();
    final goals = data.goals.active.where((g) => !g.isReached).toList();
    final maxValue =
        months.fold(0.0, (m, s) => s.savings.abs() > m ? s.savings.abs() : m);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...months.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(monthName(m.month.month),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: ProgressBar(
                      value: maxValue == 0 ? 0 : m.savings.abs() / maxValue,
                      color: m.savings >= 0 ? kSavingsColor : kExpenseColor,
                      height: 6,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      formatSigned(m.savings.roundToDouble()),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          StatRow('В среднем в месяц', formatMoney(average), bold: true),
          if (average > 0)
            ...goals.map((goal) {
              final monthsLeft = (goal.remaining / average).ceil();
              return Hint(
                'При сохранении текущего темпа цель «${goal.name}» '
                '(${formatMoneyRound(goal.target)}) будет достигнута '
                'примерно через $monthsLeft '
                '${plural(monthsLeft, 'месяц', 'месяца', 'месяцев')}.',
              );
            }),
          const Hint(
            'Накопления — переводы с расходных счетов и наличных '
            'на накопительные счета и вклады.',
          ),
        ],
      ),
    );
  }

  String _compareText(double current, double previous) {
    final diff = current - previous;
    final percent = (diff.abs() / previous * 100).round();

    if (percent == 0) {
      return 'Расходы примерно такие же, как в прошлом месяце.';
    }

    return diff > 0
        ? 'Расходы на $percent% больше, чем в прошлом месяце.'
        : 'Расходы на $percent% меньше, чем в прошлом месяце.';
  }
}
