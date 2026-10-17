import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/goal.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Финансовые цели: подушка, отпуск, ремонт…
class GoalsScreen extends StatelessWidget {
  final AppData data;

  const GoalsScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Цели')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final now = DateTime.now();
          final active = data.goals.active;
          final archived = data.goals.archived;
          final totalNeed =
              active.fold(0.0, (sum, goal) => sum + goal.monthlyNeed(now));
          final totalLeft =
              active.fold(0.0, (sum, goal) => sum + goal.leftThisMonth(now));
          final avgSavings = Insights(data, now).averageSavings();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              if (active.isNotEmpty)
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      StatRow(
                        'Откладывать на цели в месяц',
                        formatMoney(totalNeed),
                        bold: true,
                        fontSize: 15,
                      ),
                      StatRow(
                        'Осталось отложить в этом месяце',
                        formatMoney(totalLeft),
                        color: totalLeft > 0 ? kWarningColor : kIncomeColor,
                      ),
                      if (avgSavings > 0)
                        StatRow(
                          'В среднем откладывается в месяц',
                          formatMoney(avgSavings),
                        ),
                    ],
                  ),
                ),
              if (active.isEmpty)
                const EmptyHint(
                  'Целей пока нет.\n'
                  'Добавьте подушку безопасности, отпуск или ремонт —\n'
                  'приложение посчитает, сколько откладывать.',
                ),
              ...active.map(
                (goal) => GoalCard(
                  data: data,
                  goal: goal,
                  now: now,
                  onTap: () => pushScreen(
                    context,
                    GoalDetailsScreen(data: data, goalId: goal.id),
                  ),
                ),
              ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionHeader(title: 'Архив'),
                ...archived.map(
                  (goal) => GoalCard(
                    data: data,
                    goal: goal,
                    now: now,
                    onTap: () => pushScreen(
                      context,
                      GoalDetailsScreen(data: data, goalId: goal.id),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goals-fab',
        onPressed: () => showGoalDialog(context, data),
        icon: const Icon(Icons.add),
        label: const Text('Новая цель'),
      ),
    );
  }
}

/// Карточка цели с прогрессом.
class GoalCard extends StatelessWidget {
  final AppData data;
  final Goal goal;
  final DateTime now;
  final VoidCallback? onTap;
  final bool compact;

  const GoalCard({
    super.key,
    required this.data,
    required this.goal,
    required this.now,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final need = goal.monthlyNeed(now);
    final left = goal.leftThisMonth(now);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${formatMoneyRound(goal.current)} / '
                '${formatMoneyRound(goal.target)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgressBar(
            value: goal.progress,
            color: goal.isReached ? kIncomeColor : kSavingsColor,
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              goalStatusText(data, goal, now),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ] else if (need > 0)
            Hint(
              left > 0
                  ? 'В этом месяце осталось отложить ${formatMoney(left)}'
                  : 'План на этот месяц выполнен',
            ),
        ],
      ),
    );
  }
}

/// «Осталось 75 000 ₽. Чтобы успеть к 31 марта, откладывай 12 500 ₽/мес.»
String goalStatusText(AppData data, Goal goal, DateTime now) {
  if (goal.isReached) {
    return 'Цель достигнута 🎉';
  }

  final parts = <String>['Осталось ${formatMoney(goal.remaining)}.'];
  final need = goal.monthlyNeed(now);

  if (goal.deadline != null) {
    final months = monthsLeftInclusive(now, goal.deadline!);
    parts.add(
      'Чтобы достичь цели за $months '
      '${plural(months, 'месяц', 'месяца', 'месяцев')} '
      '(к ${formatDayMonth(goal.deadline!, now: now)}), '
      'откладывай ${formatMoney(need)}/мес.',
    );
  } else if (need > 0) {
    parts.add('План: ${formatMoney(need)}/мес.');
  }

  final pace = goalPace(goal, now);
  if (pace > 0) {
    final months = (goal.remaining / pace).ceil();
    parts.add(
      'При текущем темпе (${formatMoneyRound(pace)}/мес.) цель будет '
      'достигнута примерно через $months '
      '${plural(months, 'месяц', 'месяца', 'месяцев')}.',
    );
  }

  return parts.join(' ');
}

/// Средний темп пополнения цели за последние месяцы
/// (без стартовой суммы).
double goalPace(Goal goal, DateTime now) {
  final sorted = List.of(goal.contributions)
    ..sort((a, b) => a.date.compareTo(b.date));

  if (sorted.length < 2) {
    return 0;
  }

  final rest = sorted.skip(1).toList();
  final months = monthsLeftInclusive(rest.first.date, now);
  final sum = rest.fold(0.0, (s, c) => s + c.amount);

  if (sum <= 0) {
    return 0;
  }

  return roundMoney(sum / months);
}

// ─────────────────────────────
// ПОДРОБНОСТИ ЦЕЛИ
// ─────────────────────────────

class GoalDetailsScreen extends StatelessWidget {
  final AppData data;
  final String goalId;

  const GoalDetailsScreen({
    super.key,
    required this.data,
    required this.goalId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data.all,
      builder: (context, _) {
        final goal = data.goals.getById(goalId);

        if (goal == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyHint('Цель удалена'),
          );
        }

        final now = DateTime.now();
        final contributions = List.of(goal.contributions)
          ..sort((a, b) => b.date.compareTo(a.date));
        final account = data.accounts.getById(goal.accountId);

        return Scaffold(
          appBar: AppBar(
            title: Text(goal.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    showGoalDialog(context, data, goal: goal);
                  }
                  if (value == 'archive') {
                    data.goals.update(
                      goal.copyWith(isArchived: !goal.isArchived),
                    );
                  }
                  if (value == 'delete') {
                    final ok = await confirmDialog(
                      context,
                      title: 'Удалить цель «${goal.name}»?',
                      message: 'История пополнений цели будет удалена. '
                          'Деньги на счетах и переводы останутся.',
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                      data.goals.delete(goal.id);
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      goal.isArchived ? 'Вернуть из архива' : 'В архив',
                    ),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              GoalCard(data: data, goal: goal, now: now),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    StatRow('Цель', formatMoney(goal.target)),
                    StatRow('Сейчас', formatMoney(goal.current)),
                    StatRow('Осталось', formatMoney(goal.remaining)),
                    if (goal.deadline != null)
                      StatRow('Срок', formatDate(goal.deadline!)),
                    StatRow('Приоритет', goal.priority.title),
                    StatRow('Где хранятся деньги', account?.name ?? 'Не указан'),
                    if (goal.monthlyNeed(now) > 0)
                      StatRow(
                        'Откладывать в месяц',
                        formatMoney(goal.monthlyNeed(now)),
                        bold: true,
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          showContributeDialog(context, data, goal),
                      icon: const Icon(Icons.add),
                      label: const Text('Отложить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: goal.current > 0
                          ? () => showContributeDialog(
                                context,
                                data,
                                goal,
                                withdraw: true,
                              )
                          : null,
                      icon: const Icon(Icons.remove),
                      label: const Text('Взять'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'История'),
              if (contributions.isEmpty) const EmptyHint('Пополнений пока нет'),
              ...contributions.map(
                (item) => AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatDate(item.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.comment.isNotEmpty) Hint(item.comment),
                          ],
                        ),
                      ),
                      Text(
                        formatSigned(item.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: item.amount >= 0
                              ? kIncomeColor
                              : kExpenseColor,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Удалить запись',
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            title: 'Удалить запись?',
                            message: 'Сумма цели уменьшится. Переводы между '
                                'счетами, если они были, останутся — их '
                                'можно удалить в истории операций.',
                          );
                          if (ok) {
                            data.goals.update(
                              goal.copyWith(
                                contributions: goal.contributions
                                    .where((c) => c.id != item.id)
                                    .toList(),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────
// ДИАЛОГИ
// ─────────────────────────────

/// Создание или изменение цели.
void showGoalDialog(BuildContext context, AppData data, {Goal? goal}) {
  final nameController = TextEditingController(text: goal?.name ?? '');
  final targetController = TextEditingController(
    text: goal == null ? '' : moneyToInput(goal.target),
  );
  final currentController = TextEditingController();
  final planController = TextEditingController(
    text: goal?.monthlyPlan == null ? '' : moneyToInput(goal!.monthlyPlan!),
  );

  DateTime? deadline = goal?.deadline;
  GoalPriority priority = goal?.priority ?? GoalPriority.medium;
  String? accountId = goal?.accountId ??
      _firstOfType(data, AccountType.savings) ??
      data.accounts.active.firstOrNull?.id;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(goal == null ? 'Новая цель' : 'Изменить цель'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Подушка, отпуск, ремонт…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MoneyField(
                    controller: targetController,
                    label: 'Целевая сумма',
                  ),
                  if (goal == null) ...[
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: currentController,
                      label: 'Уже накоплено',
                      helper: 'Сумма, которая уже есть на цель',
                    ),
                  ],
                  const SizedBox(height: 4),
                  DateTile(
                    title: 'Срок',
                    date: deadline,
                    emptyText: 'Без срока',
                    onChanged: (value) => setState(() => deadline = value),
                    onClear: () => setState(() => deadline = null),
                  ),
                  if (deadline == null)
                    MoneyField(
                      controller: planController,
                      label: 'Откладывать в месяц',
                      helper: 'Необязательно. Без срока и плана цель не '
                          'влияет на дневной лимит.',
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GoalPriority>(
                    isExpanded: true,
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Приоритет'),
                    items: GoalPriority.values
                        .map(
                          (p) => DropdownMenuItem(value: p, child: Text(p.title)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => priority = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  AccountDropdown(
                    data: data,
                    value: accountId,
                    label: 'Где хранятся деньги',
                    allowNone: true,
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  const Hint(
                    'Если деньги цели лежат на счёте, который входит в '
                    'доступные, они не будут считаться свободными.',
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final target = parseMoney(targetController.text);
                  final current = readMoney(currentController, empty: 0);
                  final plan = readMoney(planController);

                  if (name.isEmpty || target == null || target <= 0) {
                    setState(
                      () => errorText = 'Введите название и целевую сумму.',
                    );
                    return;
                  }
                  if (current == null || current < 0) {
                    setState(() => errorText = 'Проверьте накопленную сумму.');
                    return;
                  }

                  if (goal == null) {
                    final now = DateTime.now();
                    data.goals.add(
                      Goal(
                        id: newId(),
                        name: name,
                        target: roundMoney(target),
                        deadline: deadline,
                        priority: priority,
                        accountId: accountId,
                        monthlyPlan: deadline == null ? plan : null,
                        contributions: current > 0
                            ? [
                                GoalContribution(
                                  id: newId(),
                                  date: now,
                                  amount: roundMoney(current),
                                  comment: 'Начальная сумма',
                                ),
                              ]
                            : const [],
                        createdAt: now,
                      ),
                    );
                  } else {
                    data.goals.update(
                      Goal(
                        id: goal.id,
                        name: name,
                        target: roundMoney(target),
                        deadline: deadline,
                        priority: priority,
                        accountId: accountId,
                        monthlyPlan: deadline == null ? plan : null,
                        contributions: goal.contributions,
                        isArchived: goal.isArchived,
                        createdAt: goal.createdAt,
                      ),
                    );
                  }

                  Navigator.pop(dialogContext);
                },
                child: Text(goal == null ? 'Создать' : 'Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

String? _firstOfType(AppData data, AccountType type) {
  final list = data.accounts.byType(type);
  return list.isEmpty ? null : list.first.id;
}

/// Отложить на цель (или взять из неё).
void showContributeDialog(
  BuildContext context,
  AppData data,
  Goal goal, {
  bool withdraw = false,
}) {
  final now = DateTime.now();
  final left = goal.leftThisMonth(now);
  final amountController = TextEditingController(
    text: !withdraw && left > 0 ? moneyToInput(left) : '',
  );
  final goalAccount = data.accounts.getById(goal.accountId);

  // По умолчанию переводим с первого доступного счёта,
  // если цель хранится на отдельном.
  String? fromAccountId;
  if (goalAccount != null && !goalAccount.includeInAvailableMoney) {
    fromAccountId = data.accounts.active
        .where((a) => a.includeInAvailableMoney && a.id != goalAccount.id)
        .firstOrNull
        ?.id;
  }

  DateTime date = now;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(withdraw ? 'Взять из цели' : 'Отложить на цель'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«${goal.name}»: ${formatMoney(goal.current)} из '
                    '${formatMoney(goal.target)}',
                  ),
                  const SizedBox(height: 12),
                  MoneyField(controller: amountController, autofocus: true),
                  if (goalAccount != null) ...[
                    const SizedBox(height: 12),
                    AccountDropdown(
                      data: data,
                      value: fromAccountId,
                      label: withdraw
                          ? 'Вернуть деньги на счёт'
                          : 'Перевести со счёта',
                      allowNone: true,
                      noneTitle: 'Не переводить (деньги уже там)',
                      filter: (a) => a.id != goalAccount.id,
                      onChanged: (value) =>
                          setState(() => fromAccountId = value),
                    ),
                    Hint(
                      'Деньги цели хранятся на счёте «${goalAccount.name}». '
                      'Если выбрать счёт, будет создан перевод.',
                    ),
                  ],
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
                  if (amount == null || amount <= 0) {
                    setState(() => errorText = 'Введите сумму.');
                    return;
                  }
                  final error = data.contributeToGoal(
                    goal,
                    withdraw ? -amount : amount,
                    date: isSameDay(date, now) ? now : date,
                    fromAccountId: fromAccountId,
                  );
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                  Navigator.pop(dialogContext);
                },
                child: Text(withdraw ? 'Взять' : 'Отложить'),
              ),
            ],
          );
        },
      );
    },
  );
}
