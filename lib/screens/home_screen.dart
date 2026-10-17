import 'package:flutter/material.dart';

import '../models/mandatory_expense.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/budget_card.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';
import 'goals_screen.dart';
import 'mandatory_expenses_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppData data;

  /// Переключить вкладку внизу: 0 Главная, 1 Бюджет, 2 Счета, 3 Ещё.
  final void Function(int index) onOpenTab;

  const HomeScreen({
    super.key,
    required this.data,
    required this.onOpenTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool showAllWarnings = false;

  AppData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data.all,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final now = DateTime.now();
    final budget = data.budgetFor(now);
    final insights = Insights(data, now);
    final accounts = data.accounts;

    final warnings = insights.warnings();
    final shownWarnings =
        showAllWarnings ? warnings : warnings.take(3).toList();

    final upcoming = data.mandatory.unpaidExpenses.take(3).toList();
    final recent = data.transactions.transactions.take(5).toList();
    final goals = data.goals.active.take(3).toList();
    final month = insights.month(now.year, now.month);
    final deposits = insights.deposits;
    final interestThisMonth = insights.interestThisMonth();

    return Scaffold(
      appBar: AppBar(title: const Text('Мои деньги')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _CapitalCard(data: data, onTap: () => widget.onOpenTab(2)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => widget.onOpenTab(1),
            child: BudgetCard(budget: budget, now: now),
          ),

          if (accounts.accounts.isEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              onTap: () => widget.onOpenTab(2),
              child: const Row(
                children: [
                  IconBox(icon: Icons.add),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Добавьте первый счёт',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Предупреждения
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...shownWarnings.map((w) => WarningTile(warning: w)),
            if (warnings.length > 3)
              Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => showAllWarnings = !showAllWarnings),
                  child: Text(
                    showAllWarnings
                        ? 'Свернуть'
                        : 'Ещё ${warnings.length - 3}',
                  ),
                ),
              ),
          ],

          // ── Ближайшие платежи
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Ближайшие платежи',
            trailing: TextButton(
              onPressed: () =>
                  pushScreen(context, MandatoryExpensesScreen(data: data)),
              child: const Text('Все'),
            ),
          ),
          if (upcoming.isEmpty)
            const EmptyHint('Неоплаченных обязательных платежей нет'),
          ...upcoming.map(
            (expense) => _PaymentRow(
              expense: expense,
              now: now,
              onTap: () => showPaymentDialog(context, data, expense),
            ),
          ),

          // ── Накопления
          if (goals.isNotEmpty || accounts.savingsMoney > 0) ...[
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Накопления',
              trailing: TextButton(
                onPressed: () => pushScreen(context, GoalsScreen(data: data)),
                child: const Text('Цели'),
              ),
            ),
            ...goals.map(
              (goal) => GoalCard(
                data: data,
                goal: goal,
                now: now,
                compact: true,
                onTap: () => pushScreen(
                  context,
                  GoalDetailsScreen(data: data, goalId: goal.id),
                ),
              ),
            ),
            if (goals.isEmpty)
              AppCard(
                onTap: () => pushScreen(context, GoalsScreen(data: data)),
                child: Text(
                  'На накопительных счетах ${formatMoney(accounts.savingsMoney)}. '
                  'Добавьте цель, чтобы видеть, сколько откладывать.',
                ),
              ),
          ],

          // ── Вклады
          if (deposits.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Вклады',
              trailing: TextButton(
                onPressed: () => widget.onOpenTab(2),
                child: const Text('Счета'),
              ),
            ),
            AppCard(
              onTap: () => widget.onOpenTab(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatMoney(accounts.depositMoney),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    interestThisMonth > 0
                        ? '+${formatMoney(interestThisMonth)} процентов в этом месяце'
                        : 'Процентов в этом месяце пока не было',
                    style: TextStyle(
                      fontSize: 14,
                      color: interestThisMonth > 0
                          ? kIncomeColor
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ...deposits.map((account) {
                    final next = data.nextInterest(account);
                    if (next == null) {
                      return const SizedBox.shrink();
                    }
                    return Hint(
                      '${account.name}: ≈ ${formatMoney(next.amount)} '
                      '${formatDayMonth(next.date, now: now)}',
                    );
                  }),
                ],
              ),
            ),
          ],

          // ── Этот месяц
          const SizedBox(height: 20),
          SectionHeader(title: monthTitle(now.year, now.month)),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                StatRow('Доходы', formatMoney(month.income), color: kIncomeColor),
                StatRow(
                  'Расходы',
                  formatMoney(month.expense),
                  color: kExpenseColor,
                ),
                StatRow(
                  'Накоплено',
                  formatMoney(month.savings),
                  color: kSavingsColor,
                ),
                if (month.interest > 0)
                  StatRow(
                    'Проценты по вкладам',
                    formatMoney(month.interest),
                    color: kIncomeColor,
                  ),
              ],
            ),
          ),

          // ── Последние операции
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Последние операции',
            trailing: TextButton(
              onPressed: () =>
                  pushScreen(context, TransactionsScreen(data: data)),
              child: const Text('Все'),
            ),
          ),
          if (recent.isEmpty)
            const EmptyHint(
              'Операций пока нет.\nНажмите «+», чтобы добавить первую.',
            ),
          ...recent.map(
            (transaction) => TransactionTile(
              transaction: transaction,
              data: data,
              onTap: () => openTransactionEditor(context, data, transaction),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home-fab',
        onPressed: () => showAddOperationSheet(context, data),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Общий капитал и его структура.
class _CapitalCard extends StatelessWidget {
  final AppData data;
  final VoidCallback onTap;

  const _CapitalCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accounts = data.accounts;
    final foreign = accounts.foreign;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ОБЩИЙ КАПИТАЛ',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(accounts.totalMoney),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _part('Доступно', accounts.availableMoney, Colors.black87),
              _part('Накопления', accounts.savingsMoney, kSavingsColor),
              _part('Вклады', accounts.depositMoney, kTransferColor),
            ],
          ),
          if (foreign.isNotEmpty)
            Hint(
              'Плюс в валюте: '
              '${foreign.map((a) => a.money(a.balance)).join(', ')}',
            ),
        ],
      ),
    );
  }

  Widget _part(String title, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoneyRound(value),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final MandatoryExpense expense;
  final DateTime now;
  final VoidCallback onTap;

  const _PaymentRow({
    required this.expense,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = dueStatus(expense.dueDate, now);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBox(
            icon: Icons.receipt_long_outlined,
            color: status.color,
            background: status.color?.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
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
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class DueStatus {
  final String text;
  final Color? color;

  const DueStatus(this.text, this.color);
}

/// «Просрочен на 3 дня», «Сегодня», «Через 5 дней, 10 октября».
DueStatus dueStatus(DateTime dueDate, DateTime now) {
  final days = daysBetween(now, dueDate);
  final date = formatDayMonth(dueDate, now: now);

  if (days < 0) {
    final overdue = -days;
    return DueStatus(
      'Просрочен на $overdue ${plural(overdue, 'день', 'дня', 'дней')} '
      '($date)',
      Colors.red.shade700,
    );
  }

  if (days == 0) {
    return DueStatus('Оплатить сегодня', Colors.orange.shade800);
  }

  if (days == 1) {
    return DueStatus('Оплатить завтра, $date', Colors.orange.shade800);
  }

  if (days <= 7) {
    return DueStatus(
      'Через $days ${plural(days, 'день', 'дня', 'дней')}, $date',
      Colors.orange.shade800,
    );
  }

  return DueStatus('До $date', null);
}
