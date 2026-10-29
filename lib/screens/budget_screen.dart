import 'package:flutter/material.dart';

import '../models/planned_income.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/budget_card.dart';
import '../widgets/common.dart';
import 'categories_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart' show dueStatus;
import 'mandatory_expenses_screen.dart';

/// Планирование месяца: дневной лимит, доходы, платежи,
/// резервы, цели и планы по категориям.
class BudgetScreen extends StatelessWidget {
  final AppData data;

  const BudgetScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data.all,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final now = DateTime.now();
    final budget = data.budgetFor(now);
    final incomes = data.plannedIncomes.items;
    final due = data.dueUntil(now, budget.periodEnd);
    final rare = data.mandatory.unpaidExpenses
        .where((e) => e.isRare && !due.any((d) => d.expense.id == e.id))
        .toList();
    final goals = data.goals.active;
    final limited = data.categories.topLevel
        .where((c) => (c.monthlyLimit ?? 0) > 0)
        .toList();
    final insights = Insights(data, now);
    final month = insights.month(now.year, now.month);

    // План доходов на месяц: ещё ожидаемые + уже полученные.
    final expectedIncome = incomes.fold(
      0.0,
      (sum, income) =>
          sum +
          income.occurrences(now, endOfMonth(now)).length * income.amount,
    );
    final savingPlan = rare.fold(
          0.0,
          (sum, e) => sum + data.reserveMonthlyNeed(e, now),
        ) +
        goals.fold(0.0, (sum, g) => sum + g.monthlyNeed(now));
    final savedThisMonth = rare.fold(
          0.0,
          (sum, e) => sum + e.reservedInMonth(now.year, now.month),
        ) +
        goals.fold(
          0.0,
          (sum, g) => sum + g.contributedInMonth(now.year, now.month),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Бюджет')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          BudgetCard(budget: budget, now: now, detailed: true),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _askDistribution(context),
            icon: const Icon(Icons.call_split),
            label: const Text('Распределить доход'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          // ── План месяца
          const SizedBox(height: 24),
          SectionHeader(title: monthTitle(now.year, now.month)),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                StatRow(
                  'Доходы',
                  '${formatMoneyRound(month.income)}'
                      '${expectedIncome > 0 ? ' + ещё ${formatMoneyRound(expectedIncome)}' : ''}',
                  color: kIncomeColor,
                ),
                StatRow(
                  'Расходы',
                  formatMoneyRound(month.expense),
                  color: kExpenseColor,
                ),
                if (savingPlan > 0)
                  StatRow(
                    'Отложено по плану',
                    '${formatMoneyRound(savedThisMonth)} из '
                        '${formatMoneyRound(savingPlan)}',
                    color: kSavingsColor,
                  ),
                if (month.savings != 0)
                  StatRow(
                    'Переведено в накопления',
                    formatMoneyRound(month.savings),
                  ),
              ],
            ),
          ),

          // ── Ожидаемые доходы
          const SizedBox(height: 16),
          SectionHeader(
            title: 'Ожидаемые доходы',
            trailing: IconButton(
              tooltip: 'Добавить',
              onPressed: () => showPlannedIncomeDialog(context, data),
              icon: const Icon(Icons.add),
            ),
          ),
          if (incomes.isEmpty)
            AppCard(
              onTap: () => showPlannedIncomeDialog(context, data),
              child: const Text(
                'Добавьте зарплату или другой регулярный доход — тогда '
                'дневной лимит будет считаться до дня его получения, '
                'а прогноз станет точнее.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ...incomes.map(
            (income) => _IncomeCard(data: data, income: income, now: now),
          ),

          // ── Обязательные платежи
          const SizedBox(height: 16),
          SectionHeader(
            title: 'Обязательные платежи',
            trailing: TextButton(
              onPressed: () =>
                  pushScreen(context, MandatoryExpensesScreen(data: data)),
              child: const Text('Все'),
            ),
          ),
          if (due.isEmpty)
            EmptyHint(
              'До ${formatDayMonth(budget.periodEnd, now: now)} платежей нет',
            ),
          ...due.take(5).map(
                (item) => _DueRow(
                  item: item,
                  now: now,
                  onTap: () =>
                      showPaymentDialog(context, data, item.expense),
                ),
              ),
          if (due.length > 5)
            Hint('И ещё ${due.length - 5} — в списке «Все».'),

          // ── Резервы на редкие платежи
          if (rare.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeader(title: 'Резервы на редкие платежи'),
            ...rare.map((expense) {
              final left = data.reserveLeftThisMonth(expense, now);
              return AppCard(
                onTap: () => showReserveDialog(context, data, expense),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            expense.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${formatMoneyRound(expense.reserved)} / '
                          '${formatMoneyRound(expense.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ProgressBar(
                      value: expense.amount <= 0
                          ? 0
                          : expense.reserved / expense.amount,
                      color: kSavingsColor,
                    ),
                    Hint(
                      '${insights.reserveAdvice(expense)} '
                      '${left > 0 ? 'В этом месяце осталось ${formatMoney(left)}.' : 'В этом месяце уже отложено.'}',
                    ),
                  ],
                ),
              );
            }),
          ],

          // ── Цели
          const SizedBox(height: 16),
          SectionHeader(
            title: 'Цели',
            trailing: TextButton(
              onPressed: () => pushScreen(context, GoalsScreen(data: data)),
              child: Text(goals.isEmpty ? 'Добавить' : 'Все'),
            ),
          ),
          if (goals.isEmpty)
            const EmptyHint(
              'Целей пока нет. Подушка безопасности, отпуск, ремонт — '
              'добавьте в разделе «Цели».',
            ),
          ...goals.take(4).map(
                (goal) => GoalCard(
                  data: data,
                  goal: goal,
                  now: now,
                  compact: true,
                  onTap: () => showContributeDialog(context, data, goal),
                ),
              ),

          // ── Планы по категориям
          const SizedBox(height: 16),
          SectionHeader(
            title: 'Планы по категориям',
            trailing: TextButton(
              onPressed: () =>
                  pushScreen(context, CategoriesScreen(data: data)),
              child: const Text('Настроить'),
            ),
          ),
          if (limited.isEmpty)
            const EmptyHint(
              'Задайте план на месяц для категорий (например, «Еда — '
              '10 000 ₽»), и здесь будет видно, где траты больше плана.',
            )
          else
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: limited.map((category) {
                  final limit = category.monthlyLimit!;
                  final spent =
                      data.categorySpent(category.name, now.year, now.month);
                  final over = spent > limit;
                  return ShareBar(
                    title: category.name,
                    amount: spent,
                    total: limit,
                    color: over
                        ? kExpenseColor
                        : spent > limit * 0.9
                            ? kWarningColor
                            : kIncomeColor,
                    suffix: over
                        ? '${formatMoneyRound(spent)} из ${formatMoneyRound(limit)} '
                            '(+${formatMoneyRound(spent - limit)})'
                        : '${formatMoneyRound(spent)} из ${formatMoneyRound(limit)}',
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _askDistribution(BuildContext context) async {
    final controller = TextEditingController();
    final incomes = data.plannedIncomes.items;
    if (incomes.isNotEmpty) {
      controller.text = moneyToInput(incomes.first.amount);
    }

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Распределить доход'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Приложение покажет, сколько из этой суммы уйдёт на '
              'обязательные платежи, резервы и цели, и сколько останется '
              'свободно.',
            ),
            const SizedBox(height: 12),
            MoneyField(controller: controller, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, parseMoney(controller.text)),
            child: const Text('Показать'),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0 || !context.mounted) {
      return;
    }

    showDistributionSheet(context, data, amount, DateTime.now());
  }
}

class _IncomeCard extends StatelessWidget {
  final AppData data;
  final PlannedIncome income;
  final DateTime now;

  const _IncomeCard({
    required this.data,
    required this.income,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final days = daysBetween(now, income.nextDate);
    final String status;
    Color? color;

    if (days < 0) {
      status = 'Ожидался ${formatDayMonth(income.nextDate, now: now)}';
      color = kWarningColor;
    } else if (days == 0) {
      status = 'Сегодня';
      color = kIncomeColor;
    } else {
      status = 'Через $days ${plural(days, 'день', 'дня', 'дней')}, '
          '${formatDayMonth(income.nextDate, now: now)}';
    }

    return AppCard(
      onTap: () => showPlannedIncomeDialog(context, data, income: income),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          IconBox(
            icon: Icons.arrow_downward,
            color: kIncomeColor,
            background: kIncomeColor.withValues(alpha: 0.08),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${income.name} · ${formatMoney(income.amount)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  income.isMain ? status : '$status · подработка',
                  style: TextStyle(
                    fontSize: 13,
                    color: color ?? Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (days <= 3)
            FilledButton.tonal(
              onPressed: () => showReceiveIncomeDialog(context, data, income),
              child: const Text('Пришёл'),
            ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  final DueItem item;
  final DateTime now;
  final VoidCallback onTap;

  const _DueRow({required this.item, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final expense = item.expense;
    final status = dueStatus(item.date, now);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: status.color ?? Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${expense.isVariableAmount ? '≈ ' : ''}'
            '${formatMoney(expense.amount)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────
// ДИАЛОГИ
// ─────────────────────────────

/// Добавить или изменить ожидаемый доход.
void showPlannedIncomeDialog(
  BuildContext context,
  AppData data, {
  PlannedIncome? income,
}) {
  final nameController = TextEditingController(
    text: income?.name ?? 'Зарплата',
  );
  final amountController = TextEditingController(
    text: income == null ? '' : moneyToInput(income.amount),
  );
  DateTime date = income?.nextDate ?? dateOnly(DateTime.now());
  int interval = income?.intervalMonths ?? 1;
  String? accountId = income?.accountId ??
      data.accounts.active
          .where((a) => a.includeInAvailableMoney)
          .firstOrNull
          ?.id;
  String source = income?.source ?? 'Зарплата';
  bool isMain = income?.isMain ?? true;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final sources = data.incomeSources.sources;
          if (!sources.any((s) => s.name == source) && sources.isNotEmpty) {
            source = sources.first.name;
          }

          return AlertDialog(
            title: Text(income == null ? 'Ожидаемый доход' : 'Изменить доход'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Зарплата, аванс…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MoneyField(
                    controller: amountController,
                    label: 'Ожидаемая сумма',
                  ),
                  DateTile(
                    title: 'Ближайшая дата',
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: interval,
                    decoration: const InputDecoration(labelText: 'Повтор'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Один раз')),
                      DropdownMenuItem(value: 1, child: Text('Каждый месяц')),
                      DropdownMenuItem(value: 3, child: Text('Раз в квартал')),
                      DropdownMenuItem(value: 12, child: Text('Раз в год')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => interval = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('src-$source'),
                    initialValue: sources.any((s) => s.name == source)
                        ? source
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Источник дохода',
                    ),
                    items: sources
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.name,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => source = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  AccountDropdown(
                    data: data,
                    value: accountId,
                    label: 'На счёт',
                    allowNone: true,
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isMain,
                    title: const Text('Аванс или зарплата'),
                    subtitle: const Text(
                      'Свободные деньги считаются до этого дохода. '
                      'Для подработки выключите.',
                    ),
                    onChanged: (value) => setState(() => isMain = value),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (income != null)
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Удалить «${income.name}»?',
                      message: 'Полученные доходы останутся в истории.',
                    );
                    if (ok && dialogContext.mounted) {
                      data.plannedIncomes.delete(income.id);
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text(
                    'Удалить',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final amount = parseMoney(amountController.text);
                  if (name.isEmpty || amount == null || amount <= 0) {
                    setState(
                      () => errorText = 'Введите название и сумму.',
                    );
                    return;
                  }
                  final item = PlannedIncome(
                    id: income?.id ?? newId(),
                    name: name,
                    amount: roundMoney(amount),
                    nextDate: date,
                    intervalMonths: interval,
                    accountId: accountId,
                    source: source,
                    isMain: isMain,
                  );
                  if (income == null) {
                    data.plannedIncomes.add(item);
                  } else {
                    data.plannedIncomes.update(item);
                  }
                  Navigator.pop(dialogContext);
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Отметить, что доход пришёл, и показать план распределения.
void showReceiveIncomeDialog(
  BuildContext context,
  AppData data,
  PlannedIncome income,
) {
  final amountController = TextEditingController(
    text: moneyToInput(income.amount),
  );
  String? accountId = income.accountId ??
      data.accounts.active
          .where((a) => a.includeInAvailableMoney)
          .firstOrNull
          ?.id;
  DateTime date = DateTime.now();
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          return AlertDialog(
            title: Text('Пришёл доход «${income.name}»'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyField(
                    controller: amountController,
                    label: 'Фактическая сумма',
                  ),
                  const SizedBox(height: 12),
                  AccountDropdown(
                    data: data,
                    value: accountId,
                    label: 'На счёт',
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  DateTile(
                    title: 'Дата',
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = parseMoney(amountController.text);
                  if (amount == null || amount <= 0 || accountId == null) {
                    setState(() => errorText = 'Введите сумму и счёт.');
                    return;
                  }
                  final now = DateTime.now();
                  final when = isSameDay(date, now) ? now : date;
                  final error = data.receiveIncome(
                    income,
                    amount: amount,
                    accountId: accountId!,
                    date: when,
                  );
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                  Navigator.pop(dialogContext);
                  showDistributionSheet(context, data, amount, when);
                },
                child: const Text('Записать'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// План распределения дохода.
void showDistributionSheet(
  BuildContext context,
  AppData data,
  double amount,
  DateTime date,
) {
  final plan = data.distributionFor(amount, date);

  Color colorOf(DistributionKind kind) {
    switch (kind) {
      case DistributionKind.mandatory:
        return kExpenseColor;
      case DistributionKind.reserve:
      case DistributionKind.goal:
        return kSavingsColor;
      case DistributionKind.category:
        return kTransferColor;
    }
  }

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                'Доход ${formatMoney(amount)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Hint(
                'План до ${formatDayMonth(plan.until, now: date)}',
                padding: const EdgeInsets.only(top: 2, bottom: 14),
              ),
              if (plan.lines.isEmpty)
                const Text(
                  'Обязательных платежей, резервов и целей на этот период '
                  'нет — вся сумма свободна.',
                ),
              ...plan.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorOf(line.kind),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              line.details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(line.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Свободные деньги',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(plan.free),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: plan.free >= 0 ? kIncomeColor : kExpenseColor,
                    ),
                  ),
                ],
              ),
              if (plan.free < 0)
                const Hint(
                  'Дохода не хватает на всё запланированное — разница '
                  'берётся из денег, которые уже есть на счетах.',
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
