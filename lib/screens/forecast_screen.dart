import 'package:flutter/material.dart';

import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Что будет с деньгами при текущих доходах и расходах.
class ForecastScreen extends StatefulWidget {
  final AppData data;

  const ForecastScreen({super.key, required this.data});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  int months = 3;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return Scaffold(
      appBar: AppBar(title: const Text('Прогноз')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final now = DateTime.now();
          final insights = Insights(data, now);
          final point = insights.forecast(months);
          final capitalNow = data.accounts.totalMoney;
          final variable = insights.averageMonthlyVariable();
          final estimate = insights.endOfMonthEstimate();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in [1, 3, 6, 12])
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 8),
                        child: ChoiceChip(
                          label: Text(
                            '$m ${plural(m, 'месяц', 'месяца', 'месяцев')}',
                          ),
                          selected: months == m,
                          onSelected: (_) => setState(() => months = m),
                        ),
                      ),
                  ],
                ),
              ),
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Через $months '
                      '${plural(months, 'месяц', 'месяца', 'месяцев')} '
                      '(${formatDate(point.date)})',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoneyRound(point.capital),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'общий капитал · сейчас ${formatMoneyRound(capitalNow)} '
                      '(${formatSigned((point.capital - capitalNow).roundToDouble())})',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    StatRow(
                      'Доступные деньги',
                      formatMoneyRound(point.available),
                      color: point.available < 0 ? kExpenseColor : null,
                    ),
                    StatRow('Накопления', formatMoneyRound(point.savings),
                        color: kSavingsColor),
                    StatRow('Вклады', formatMoneyRound(point.deposits),
                        color: kTransferColor),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const SectionHeader(title: 'Из чего складывается'),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    StatRow('Доступно сейчас',
                        formatMoneyRound(data.accounts.availableMoney)),
                    StatRow('+ ожидаемые доходы',
                        formatMoneyRound(point.incomes),
                        color: kIncomeColor),
                    StatRow('− обязательные платежи',
                        formatMoneyRound(point.mandatory),
                        color: kExpenseColor),
                    StatRow('− обычные расходы (по среднему)',
                        formatMoneyRound(point.spending),
                        color: kExpenseColor),
                    if (point.savings - _savingsNow(data) > 0.5)
                      StatRow(
                        '− переводы на цели',
                        formatMoneyRound(point.savings - _savingsNow(data)),
                        color: kSavingsColor,
                      ),
                    const Divider(height: 18),
                    StatRow('Доступно через $months мес.',
                        formatMoneyRound(point.available),
                        bold: true),
                    const SizedBox(height: 8),
                    StatRow('Проценты по вкладам за период',
                        '+${formatMoneyRound(point.depositInterest)}',
                        color: kIncomeColor),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AppCard(
                color: Colors.blue.shade50,
                child: Text(
                  [
                    if (variable > 0)
                      'Обычные расходы в прогнозе — ${formatMoneyRound(variable)} '
                          'в месяц (среднее без обязательных платежей).',
                    if (variable == 0)
                      'Истории расходов пока нет, поэтому обычные траты '
                          'в прогнозе не учитываются.',
                    if (data.plannedIncomes.items.isEmpty)
                      'Ожидаемые доходы не заданы — добавьте зарплату '
                          'в разделе «Бюджет», чтобы прогноз был точнее.',
                    if (estimate != null)
                      'К концу этого месяца при текущем темпе останется '
                          'примерно ${formatMoneyRound(estimate)}.',
                  ].join('\n\n'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              const SectionHeader(title: 'По месяцам'),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    for (final m in [1, 2, 3, 6, 12])
                      _row(insights.forecast(m)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _savingsNow(AppData data) =>
      data.accounts.totalMoney -
      data.accounts.availableMoney -
      data.accounts.depositMoney;

  Widget _row(ForecastPoint point) {
    return StatRow(
      '${monthName(point.date.month)} ${point.date.year}',
      '${formatMoneyRound(point.capital)} · доступно '
          '${formatMoneyRound(point.available)}',
    );
  }
}
