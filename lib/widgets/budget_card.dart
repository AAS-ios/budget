import 'package:flutter/material.dart';

import '../services/app_data.dart';
import '../utils/format.dart';

/// Карточка «Можно потратить сегодня».
///
/// [detailed] — показать, из чего складываются свободные деньги.
class BudgetCard extends StatelessWidget {
  final BudgetSummary budget;
  final bool detailed;
  final DateTime now;

  const BudgetCard({
    super.key,
    required this.budget,
    required this.now,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final overspent = budget.leftToday < -0.004;
    final noMoney = budget.free < 0;

    final muted = TextStyle(
      fontSize: 13,
      color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
    );

    final days = budget.daysLeft;
    final until = budget.nextIncomeDate != null
        ? 'до дохода ${formatDayMonth(budget.nextIncomeDate!, now: now)}'
        : 'до конца месяца';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overspent ? 'Сегодня превышение' : 'Можно потратить сегодня',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(budget.leftToday.abs()),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: overspent ? Colors.red.shade700 : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Лимит на день ${formatMoney(budget.dailyLimit)}'
            '${budget.spentToday > 0 ? ' · потрачено ${formatMoney(budget.spentToday)}' : ''}',
            style: muted,
          ),
          if (overspent && budget.tomorrowLimit != null) ...[
            const SizedBox(height: 4),
            Text(
              'Бюджет пересчитан: с завтрашнего дня лимит '
              '${formatMoney(budget.tomorrowLimit!)} в день.',
              style: muted.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 12),
          if (detailed) ...[
            _line('Доступно на счетах', formatMoney(budget.available), muted),
            if (budget.mandatoryDue > 0)
              _line(
                'Обязательные платежи (${budget.mandatoryDueCount})',
                '−${formatMoney(budget.mandatoryDue)}',
                muted,
              ),
            if (budget.reservesHeld > 0)
              _line(
                'Уже отложено на редкие платежи',
                '−${formatMoney(budget.reservesHeld)}',
                muted,
              ),
            if (budget.reservesToSave > 0)
              _line(
                'Отложить на редкие платежи',
                '−${formatMoney(budget.reservesToSave)}',
                muted,
              ),
            if (budget.goalsHeld > 0)
              _line(
                'Деньги целей на этих счетах',
                '−${formatMoney(budget.goalsHeld)}',
                muted,
              ),
            if (budget.goalsToSave > 0)
              _line(
                'Отложить на цели',
                '−${formatMoney(budget.goalsToSave)}',
                muted,
              ),
            const SizedBox(height: 2),
          ],
          _line(
            'Свободно на $days ${plural(days, 'день', 'дня', 'дней')} ($until)',
            formatMoney(budget.free),
            muted.copyWith(fontWeight: FontWeight.w600),
          ),
          if (noMoney) ...[
            const SizedBox(height: 10),
            Text(
              'Денег не хватает на обязательные платежи и резервы.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(String title, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(title, style: style)),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }
}
