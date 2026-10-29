import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/app_data.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';

/// Операции: по месяцам с итогом за каждый день,
/// поиск по всем операциям и просмотр одного дня.
class TransactionsScreen extends StatefulWidget {
  final AppData data;

  const TransactionsScreen({super.key, required this.data});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late DateTime month;
  TransactionType? filter;

  /// Выбранный день — показываем только его.
  DateTime? day;

  final searchController = TextEditingController();
  String query = '';

  AppData get data => widget.data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// Потрачено (только рублёвые расходы).
  double _spent(Iterable<Transaction> list) => _sumOf(list, TransactionType.expense);

  double _received(Iterable<Transaction> list) =>
      _sumOf(list, TransactionType.income);

  double _sumOf(Iterable<Transaction> list, TransactionType type) {
    return roundMoney(
      list
          .where(
            (t) =>
                t.type == type &&
                (data.accounts.getById(t.accountId)?.isRub ?? true),
          )
          .fold(0.0, (sum, t) => sum + t.amount),
    );
  }

  bool _matches(Transaction t, String q) {
    final accounts = data.accounts;
    final text = [
      t.title,
      t.categoryLabel,
      t.comment,
      t.incomeSource ?? '',
      accounts.nameOf(t.accountId),
      if (t.destinationAccountId != null)
        accounts.nameOf(t.destinationAccountId),
      moneyToInput(t.amount),
    ].join(' ').toLowerCase();

    return text.contains(q);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await pickDate(context, day ?? dateOnly(now));
    if (picked != null) {
      setState(() {
        day = dateOnly(picked);
        month = DateTime(picked.year, picked.month);
      });
    }
  }

  String _dayTitle(DateTime date) {
    final now = DateTime.now();
    final text = formatDayMonth(date, now: now);
    if (isSameDay(date, now)) {
      return 'Сегодня, $text';
    }
    if (isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Вчера, $text';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Операции'),
        actions: [
          IconButton(
            tooltip: 'Выбрать день',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) => _buildList(context),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'operations-fab',
        onPressed: () => showAddOperationSheet(context, data),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final all = data.transactions.transactions;

    // Что показываем: один день, поиск по всем месяцам или месяц.
    final List<Transaction> base;
    if (day != null) {
      base = all.where((t) => isSameDay(t.date, day!)).toList();
    } else if (searching) {
      base = all;
    } else {
      base = all
          .where(
            (t) => t.date.year == month.year && t.date.month == month.month,
          )
          .toList();
    }

    final list = base
        .where((t) => filter == null || t.type == filter)
        .where((t) => !searching || _matches(t, q))
        .toList();

    // Траты за каждый день — по всем операциям дня, без учёта фильтров.
    final spentByDay = <DateTime, double>{};
    for (final t in all) {
      if (t.type == TransactionType.expense &&
          (data.accounts.getById(t.accountId)?.isRub ?? true)) {
        final key = dateOnly(t.date);
        spentByDay[key] = (spentByDay[key] ?? 0) + t.amount;
      }
    }

    final children = <Widget>[];
    DateTime? currentDay;

    for (final transaction in list) {
      final date = dateOnly(transaction.date);

      if (day == null && (currentDay == null || !isSameDay(currentDay, date))) {
        currentDay = date;
        children.add(
          _DayHeader(
            title: _dayTitle(date),
            spent: roundMoney(spentByDay[date] ?? 0),
            onTap: () => setState(() {
              day = date;
              month = DateTime(date.year, date.month);
            }),
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
            message: 'Деньги вернутся на счёт, как будто операции не было.',
          ),
          onDismissed: (_) => data.deleteTransaction(transaction),
          child: TransactionTile(
            transaction: transaction,
            data: data,
            onTap: () => openTransactionEditor(context, data, transaction),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        TextField(
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Поиск: категория, комментарий, сумма',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() {
                      searchController.clear();
                      query = '';
                    }),
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 8),
        if (day != null)
          _DaySummary(
            title: _dayTitle(day!),
            spent: _spent(base),
            received: _received(base),
            count: base.length,
            onPrev: () => setState(
              () => day = day!.subtract(const Duration(days: 1)),
            ),
            onNext: () => setState(
              () => day = day!.add(const Duration(days: 1)),
            ),
            onClose: () => setState(() => day = null),
          )
        else if (searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Text(
              list.isEmpty
                  ? 'Ничего не найдено'
                  : 'Найдено ${list.length} по всем месяцам · '
                      'расходы ${formatMoney(_spent(list))}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          )
        else ...[
          MonthSwitcher(
            month: month,
            onChanged: (value) => setState(() => month = value),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              children: [
                StatRow(
                  'Потрачено за месяц',
                  formatMoney(_spent(base)),
                  color: kExpenseColor,
                ),
                StatRow(
                  'Пришло',
                  formatMoney(_received(base)),
                  color: kIncomeColor,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
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
        if (day != null) const SizedBox(height: 8),
        if (list.isEmpty && !searching)
          EmptyHint(
            day != null ? 'В этот день операций нет' : 'За этот месяц операций нет',
          ),
        ...children,
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Нажмите на дату, чтобы открыть только этот день.\n'
              'Смахните операцию влево, чтобы удалить.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
      ],
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

/// Дата и сколько потрачено за день.
class _DayHeader extends StatelessWidget {
  final String title;
  final double spent;
  final VoidCallback onTap;

  const _DayHeader({
    required this.title,
    required this.spent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade700,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: style)),
            if (spent > 0)
              Text(
                'потрачено ${formatMoney(spent)}',
                style: style.copyWith(color: kExpenseColor),
              ),
          ],
        ),
      ),
    );
  }
}

/// Итог за выбранный день: ‹ 28 октября › и суммы.
class _DaySummary extends StatelessWidget {
  final String title;
  final double spent;
  final double received;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const _DaySummary({
    required this.title,
    required this.spent,
    required this.received,
    required this.count,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                StatRow(
                  'Потрачено за день',
                  formatMoney(spent),
                  color: kExpenseColor,
                ),
                if (received > 0)
                  StatRow(
                    'Пришло',
                    formatMoney(received),
                    color: kIncomeColor,
                  ),
                StatRow(
                  'Операций',
                  '$count',
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onClose,
            child: const Text('Показать весь месяц'),
          ),
        ],
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
