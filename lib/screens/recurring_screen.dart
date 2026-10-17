import 'package:flutter/material.dart';

import '../models/mandatory_expense.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'mandatory_expenses_screen.dart';

/// Расходы, которые повторяются из месяца в месяц.
class RecurringScreen extends StatelessWidget {
  final AppData data;

  const RecurringScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Повторяющиеся расходы')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final now = DateTime.now();
          final items = Insights(data, now).recurring();
          final payments = items.where((i) => i.looksLikePayment).toList();
          final regular = items.where((i) => !i.looksLikePayment).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              const Hint(
                'Приложение ищет траты, которые встречаются почти каждый '
                'месяц. Платежи «раз в месяц» можно превратить в '
                'обязательные — тогда они будут учитываться в бюджете '
                'заранее.',
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              ),
              if (items.isEmpty)
                const EmptyHint(
                  'Пока ничего не найдено. Нужна история хотя бы '
                  'за 2–3 полных месяца.',
                ),
              if (payments.isNotEmpty) ...[
                const SectionHeader(title: 'Похоже на регулярные платежи'),
                ...payments.map((item) => _card(context, item, now, true)),
              ],
              if (regular.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionHeader(title: 'Регулярные траты'),
                ...regular.map((item) => _card(context, item, now, false)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _card(
    BuildContext context,
    RecurringItem item,
    DateTime now,
    bool canCreate,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '~${formatMoneyRound(item.averageMonthly)}/мес',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Hint(
            '${item.monthsSeen} из ${item.monthsChecked} '
            '${plural(item.monthsChecked, 'месяца', 'месяцев', 'месяцев')}'
            '${item.looksLikePayment ? ' · обычно около ${item.typicalDay} числа' : ' · ~${item.averageCount.toStringAsFixed(0)} покупок в месяц'}',
          ),
          if (canCreate)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  var due = withDay(now, item.typicalDay);
                  if (due.isBefore(dateOnly(now))) {
                    due = withDay(addMonths(DateTime(now.year, now.month), 1),
                        item.typicalDay);
                  }
                  showExpenseDialog(
                    context,
                    data,
                    preset: MandatoryExpense(
                      id: '',
                      name: item.title,
                      amount: item.averageMonthly,
                      dueDate: due,
                      period: ExpensePeriod.monthly,
                      category: item.category,
                      subcategory: item.subcategory,
                    ),
                  );
                },
                icon: const Icon(Icons.add_task),
                label: const Text('Создать регулярный платёж'),
              ),
            ),
        ],
      ),
    );
  }
}
