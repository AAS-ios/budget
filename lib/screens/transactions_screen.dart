import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/app_data.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';

/// Все операции за выбранный месяц.
class TransactionsScreen extends StatefulWidget {
  final AppData data;

  const TransactionsScreen({super.key, required this.data});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late DateTime month;
  TransactionType? filter;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return Scaffold(
      appBar: AppBar(title: const Text('История операций')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final all = data.transactions.forMonth(month.year, month.month);
          final list = filter == null
              ? all
              : all.where((t) => t.type == filter).toList();

          final children = <Widget>[];
          DateTime? currentDay;

          for (final transaction in list) {
            final day = dateOnly(transaction.date);

            if (currentDay == null || !isSameDay(currentDay, day)) {
              currentDay = day;
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    formatDayMonth(day),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }

            children.add(
              Dismissible(
                key: ValueKey(transaction.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.only(right: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (_) => confirmDialog(
                  context,
                  title: 'Удалить операцию?',
                  message:
                      'Деньги вернутся на счёт, как будто операции не было.',
                ),
                onDismissed: (_) => data.deleteTransaction(transaction),
                child: TransactionTile(
                  transaction: transaction,
                  data: data,
                  onTap: () =>
                      openTransactionEditor(context, data, transaction),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              MonthSwitcher(
                month: month,
                onChanged: (value) => setState(() => month = value),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('Все', null),
                    _chip('Расходы', TransactionType.expense),
                    _chip('Доходы', TransactionType.income),
                    _chip('Переводы', TransactionType.transfer),
                  ],
                ),
              ),
              if (list.isEmpty)
                const EmptyHint('За этот месяц операций нет'),
              ...children,
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Смахните операцию влево, чтобы удалить.\n'
                    'Нажмите, чтобы изменить.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, TransactionType? type) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: filter == type,
        onSelected: (_) => setState(() => filter = type),
      ),
    );
  }
}

/// Переключатель месяца: ‹ Сентябрь 2026 ›
class MonthSwitcher extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;

    return Row(
      children: [
        IconButton(
          onPressed: () => onChanged(addMonths(month, -1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: GestureDetector(
            onTap: isCurrent
                ? null
                : () => onChanged(DateTime(now.year, now.month)),
            child: Text(
              monthTitle(month.year, month.month),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(addMonths(month, 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
