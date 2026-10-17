import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/category_store.dart';
import '../models/mandatory_expense.dart';
import '../services/app_data.dart';
import '../utils/format.dart';
import '../widgets/category_picker.dart';
import '../widgets/common.dart';
import 'home_screen.dart' show dueStatus;

class MandatoryExpensesScreen extends StatelessWidget {
  final AppData data;

  const MandatoryExpensesScreen({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обязательные платежи'),
      ),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, child) {
          final now = DateTime.now();
          final expenses = data.mandatory.unpaidExpenses;
          final regular = expenses.where((e) => !e.isRare).toList();
          final rare = expenses.where((e) => e.isRare).toList();
          final paid = data.mandatory.paidExpenses;

          final end = data.periodEnd(now);
          final due = data.dueUntil(now, end);
          final dueTotal = due.fold(0.0, (s, i) => s + i.expense.amount);

          // Сколько в среднем уходит на обязательные платежи в месяц.
          final monthlyLoad = data.mandatory.expenses
              .where((expense) => expense.intervalMonths > 0)
              .fold(
                0.0,
                (sum, expense) =>
                    sum + expense.amount / expense.intervalMonths,
              );

          final reserveNeed = rare.fold(
            0.0,
            (sum, e) => sum + data.reserveMonthlyNeed(e, now),
          );

          Widget card(MandatoryExpense expense) => ExpenseCard(
                data: data,
                expense: expense,
                now: now,
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заплатить до ${formatDayMonth(end, now: now)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(dueTotal),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (due.isNotEmpty)
                      Hint(
                        '${due.length} '
                        '${plural(due.length, 'платёж', 'платежа', 'платежей')}',
                      ),
                    const SizedBox(height: 8),
                    StatRow(
                      'Все неоплаченные',
                      formatMoney(data.mandatory.unpaidTotal),
                    ),
                    StatRow('В среднем в месяц', formatMoney(monthlyLoad)),
                    if (reserveNeed > 0)
                      StatRow(
                        'Откладывать на редкие в месяц',
                        formatMoney(reserveNeed),
                        color: kSavingsColor,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (expenses.isEmpty)
                const EmptyHint(
                  'Все обязательные платежи оплачены 🎉\n'
                  'Нажмите «Добавить», чтобы завести новый.',
                ),
              if (regular.isNotEmpty) ...[
                const SectionHeader(title: 'Каждый месяц'),
                ...regular.map(card),
              ],
              if (rare.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionHeader(title: 'Редкие и разовые'),
                const Hint(
                  'На такие платежи лучше откладывать заранее — '
                  'приложение подскажет, сколько в месяц.',
                  padding: EdgeInsets.only(bottom: 10, left: 4),
                ),
                ...rare.map(card),
              ],
              if (paid.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionHeader(title: 'Оплаченные разовые'),
                ...paid.map(
                  (expense) => AppCard(
                    padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: kIncomeColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${expense.name} · ${formatMoney(expense.amount)}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'unpaid') {
                              data.mandatory.markAsUnpaid(expense.id);
                            }
                            if (value == 'delete') {
                              data.mandatory.deleteExpense(expense.id);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'unpaid',
                              child: Text('Вернуть в неоплаченные'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'mandatory-fab',
        onPressed: () => showExpenseDialog(context, data),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }
}

/// Карточка обязательного платежа с кнопкой «Оплатить».
class ExpenseCard extends StatelessWidget {
  final AppData data;
  final MandatoryExpense expense;
  final DateTime now;

  const ExpenseCard({
    super.key,
    required this.data,
    required this.expense,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final status = dueStatus(expense.dueDate, now);
    final average = data.averagePayment(expense.id);
    final account = data.accounts.getById(expense.accountId);
    final category = expense.category == null
        ? null
        : [expense.category, expense.subcategory]
            .whereType<String>()
            .join(' · ');

    final details = [
      ?category,
      if (account != null) 'со счёта «${account.name}»',
    ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  expense.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    showExpenseDialog(context, data, expense: expense);
                  }
                  if (value == 'history') {
                    showPaymentHistory(context, data, expense);
                  }
                  if (value == 'delete') {
                    final confirmed = await confirmDialog(
                      context,
                      title: 'Удалить платёж?',
                      message: '«${expense.name}» будет удалён из списка '
                          'обязательных платежей. Уже проведённые оплаты '
                          'останутся в истории.',
                    );
                    if (confirmed) {
                      data.mandatory.deleteExpense(expense.id);
                    }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  PopupMenuItem(value: 'history', child: Text('История оплат')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                '${expense.isVariableAmount ? '≈ ' : ''}'
                '${formatMoney(expense.amount)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  expense.periodText,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status.text,
            style: TextStyle(
              color: status.color ?? Colors.grey.shade700,
              fontWeight:
                  status.color != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (details.isNotEmpty) Hint(details.join(' · ')),
          if (average != null && expense.isVariableAmount)
            Hint(
              'Фактически в среднем ${formatMoney(average)} '
              '(${data.paymentsOf(expense.id).length} '
              '${plural(data.paymentsOf(expense.id).length, 'оплата', 'оплаты', 'оплат')})',
            ),
          if (expense.comment.isNotEmpty) Hint(expense.comment),
          if (expense.isRare) ...[
            const SizedBox(height: 10),
            _ReserveBlock(data: data, expense: expense, now: now),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showPaymentDialog(context, data, expense),
                icon: const Icon(Icons.check),
                label: const Text('Оплатить'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReserveBlock extends StatelessWidget {
  final AppData data;
  final MandatoryExpense expense;
  final DateTime now;

  const _ReserveBlock({
    required this.data,
    required this.expense,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final months = monthsLeftInclusive(now, expense.dueDate);
    final need = data.reserveMonthlyNeed(expense, now);
    final left = data.reserveLeftThisMonth(expense, now);
    final reserved = expense.reserved;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Отложено ${formatMoney(reserved)} из '
                  '${formatMoney(expense.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => showReserveDialog(context, data, expense),
                child: const Text('Отложить'),
              ),
            ],
          ),
          ProgressBar(
            value: expense.amount <= 0 ? 0 : reserved / expense.amount,
            color: kSavingsColor,
          ),
          const SizedBox(height: 6),
          Text(
            need > 0
                ? 'До платежа $months '
                    '${plural(months, 'месяц', 'месяца', 'месяцев')}. '
                    'Откладывать примерно ${formatMoneyRound(need)} в месяц'
                    '${left > 0 ? ', в этом месяце осталось ${formatMoney(left)}' : ' — в этом месяце уже отложено'}.'
                : 'Сумма на платёж собрана.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────
// ДИАЛОГИ
// ─────────────────────────────

/// Создание или изменение обязательного платежа.
/// [preset] — заготовка (например, из повторяющихся расходов).
void showExpenseDialog(
  BuildContext context,
  AppData data, {
  MandatoryExpense? expense,
  MandatoryExpense? preset,
}) {
  final source = expense ?? preset;
  final nameController = TextEditingController(text: source?.name ?? '');
  final amountController = TextEditingController(
    text: source == null ? '' : moneyToInput(source.amount),
  );
  final commentController = TextEditingController(
    text: source?.comment ?? '',
  );

  DateTime selectedDate = source?.dueDate ?? dateOnly(DateTime.now());
  ExpensePeriod selectedPeriod = source?.period ?? ExpensePeriod.monthly;
  bool isVariableAmount = source?.isVariableAmount ?? false;
  int customIntervalMonths = source?.customIntervalMonths ?? 2;
  String? category = source?.category;
  String? subcategory = source?.subcategory;
  String? accountId = source?.accountId ??
      data.accounts.active
          .where((a) => a.includeInAvailableMoney)
          .firstOrNull
          ?.id;
  String? reserveAccountId = source?.reserveAccountId;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final isRare = selectedPeriod != ExpensePeriod.monthly &&
              !(selectedPeriod == ExpensePeriod.custom &&
                  customIntervalMonths == 1);

          return AlertDialog(
            title: Text(
              expense == null ? 'Новый платёж' : 'Редактировать платёж',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Например, Интернет',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MoneyField(
                    controller: amountController,
                    label: 'Плановая сумма',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Сумма каждый раз разная'),
                    subtitle: const Text(
                      'Например, коммунальные: фактическую сумму вводите '
                      'при оплате, приложение посчитает среднее',
                    ),
                    value: isVariableAmount,
                    onChanged: (value) =>
                        setState(() => isVariableAmount = value),
                  ),
                  DropdownButtonFormField<ExpensePeriod>(
                    isExpanded: true,
                    initialValue: selectedPeriod,
                    decoration: const InputDecoration(
                      labelText: 'Периодичность',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ExpensePeriod.once,
                        child: Text('Один раз'),
                      ),
                      DropdownMenuItem(
                        value: ExpensePeriod.monthly,
                        child: Text('Каждый месяц'),
                      ),
                      DropdownMenuItem(
                        value: ExpensePeriod.yearly,
                        child: Text('Каждый год'),
                      ),
                      DropdownMenuItem(
                        value: ExpensePeriod.custom,
                        child: Text('Своя периодичность'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedPeriod = value);
                      }
                    },
                  ),
                  if (selectedPeriod == ExpensePeriod.custom) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: customIntervalMonths,
                      decoration: const InputDecoration(
                        labelText: 'Повторять каждые',
                      ),
                      items: List.generate(12, (index) {
                        final months = index + 1;
                        return DropdownMenuItem(
                          value: months,
                          child: Text(
                            '$months '
                            '${plural(months, 'месяц', 'месяца', 'месяцев')}',
                          ),
                        );
                      }),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => customIntervalMonths = value);
                        }
                      },
                    ),
                  ],
                  DateTile(
                    title: selectedPeriod == ExpensePeriod.once
                        ? 'Дата платежа'
                        : 'Ближайшая дата платежа',
                    date: selectedDate,
                    onChanged: (value) => setState(() => selectedDate = value),
                  ),
                  CategoryPicker(
                    data: data,
                    category: category,
                    subcategory: subcategory,
                    allowNone: true,
                    noneTitle: CategoryStore.mandatoryCategoryName,
                    onChanged: (c, s) => setState(() {
                      category = c;
                      subcategory = s;
                    }),
                  ),
                  const SizedBox(height: 12),
                  AccountDropdown(
                    data: data,
                    value: accountId,
                    label: 'Обычно платится со счёта',
                    allowNone: true,
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  if (isRare) ...[
                    const SizedBox(height: 12),
                    AccountDropdown(
                      data: data,
                      value: reserveAccountId,
                      label: 'Где копить резерв',
                      allowNone: true,
                      noneTitle: 'На доступных счетах',
                      onChanged: (value) =>
                          setState(() => reserveAccountId = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий',
                      hintText: 'Необязательно',
                    ),
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
                  final amount = parseMoney(amountController.text);

                  if (name.isEmpty || amount == null || amount <= 0) {
                    setState(() {
                      errorText = 'Введите название и корректную сумму';
                    });
                    return;
                  }

                  final newExpense = MandatoryExpense(
                    id: expense?.id ?? newId(),
                    name: name,
                    amount: roundMoney(amount),
                    dueDate: selectedDate,
                    period: selectedPeriod,
                    customIntervalMonths:
                        selectedPeriod == ExpensePeriod.custom
                            ? customIntervalMonths
                            : null,
                    isVariableAmount: isVariableAmount,
                    comment: commentController.text.trim(),
                    isPaid: expense?.isPaid ?? false,
                    accountId: accountId,
                    category: category,
                    subcategory: category == null ? null : subcategory,
                    reserveLog: expense?.reserveLog ?? const [],
                    reserveAccountId: isRare ? reserveAccountId : null,
                  );

                  if (expense == null) {
                    data.mandatory.addExpense(newExpense);
                  } else {
                    data.mandatory.updateExpense(newExpense);
                  }

                  Navigator.pop(dialogContext);
                },
                child: Text(expense == null ? 'Добавить' : 'Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Оплата платежа.
void showPaymentDialog(
  BuildContext context,
  AppData data,
  MandatoryExpense expense,
) {
  final accounts = data.accounts.active;

  if (accounts.isEmpty) {
    showMessage(context, 'Сначала добавьте счёт в разделе «Счета».');
    return;
  }

  final amountController = TextEditingController(
    text: expense.isVariableAmount ? '' : moneyToInput(expense.amount),
  );
  final average = data.averagePayment(expense.id);

  String? accountId = data.accounts.getById(expense.accountId)?.isClosed == false
      ? expense.accountId
      : accounts
          .firstWhere(
            (account) => account.includeInAvailableMoney,
            orElse: () => accounts.first,
          )
          .id;

  DateTime date = DateTime.now();
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final nextText = expense.period == ExpensePeriod.once
              ? 'Разовый платёж будет отмечен как оплаченный.'
              : 'Следующий платёж: '
                  '${formatDate(addMonths(expense.dueDate, expense.intervalMonths))}.';

          return AlertDialog(
            title: Text('Оплатить «${expense.name}»'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyField(
                    controller: amountController,
                    autofocus: expense.isVariableAmount,
                    label: expense.isVariableAmount
                        ? 'Фактическая сумма'
                        : 'Сумма',
                    helper: expense.isVariableAmount
                        ? 'План ${formatMoney(expense.amount)}'
                            '${average != null ? ', в среднем ${formatMoney(average)}' : ''}'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  AccountDropdown(
                    data: data,
                    value: accountId,
                    label: 'Списать со счёта',
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  DateTile(
                    title: 'Дата оплаты',
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  if (expense.reserved > 0)
                    Hint(
                      'Отложенный резерв ${formatMoney(expense.reserved)} '
                      'будет считаться потраченным на этот платёж.',
                    ),
                  Hint(nextText),
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
                  final amount = parseMoney(amountController.text);

                  if (amount == null || amount <= 0) {
                    setState(() => errorText = 'Введите корректную сумму.');
                    return;
                  }
                  if (accountId == null) {
                    setState(() => errorText = 'Выберите счёт.');
                    return;
                  }

                  final now = DateTime.now();
                  final error = data.payMandatory(
                    expense,
                    amount: amount,
                    accountId: accountId!,
                    date: isSameDay(date, now) ? now : date,
                  );

                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }

                  Navigator.pop(dialogContext);
                },
                child: const Text('Оплатить'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Отложить на редкий платёж или забрать из резерва.
void showReserveDialog(
  BuildContext context,
  AppData data,
  MandatoryExpense expense,
) {
  final now = DateTime.now();
  final left = data.reserveLeftThisMonth(expense, now);
  final amountController = TextEditingController(
    text: left > 0 ? moneyToInput(left) : '',
  );
  final reserveAccount = data.accounts.getById(expense.reserveAccountId);
  String? fromAccountId;
  if (reserveAccount != null && !reserveAccount.includeInAvailableMoney) {
    fromAccountId = data.accounts.active
        .where((a) => a.includeInAvailableMoney && a.id != reserveAccount.id)
        .firstOrNull
        ?.id;
  }
  bool withdraw = false;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Резерв: ${expense.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Отложено ${formatMoney(expense.reserved)} из '
                    '${formatMoney(expense.amount)}.',
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Отложить')),
                      ButtonSegment(value: true, label: Text('Забрать')),
                    ],
                    selected: {withdraw},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setState(() => withdraw = value.first),
                  ),
                  const SizedBox(height: 8),
                  MoneyField(controller: amountController, autofocus: true),
                  if (reserveAccount != null) ...[
                    const SizedBox(height: 12),
                    AccountDropdown(
                      data: data,
                      value: fromAccountId,
                      label: withdraw ? 'Вернуть на счёт' : 'Перевести со счёта',
                      allowNone: true,
                      noneTitle: 'Не переводить',
                      filter: (Account a) => a.id != reserveAccount.id,
                      onChanged: (value) =>
                          setState(() => fromAccountId = value),
                    ),
                    Hint('Резерв хранится на счёте «${reserveAccount.name}».'),
                  ] else
                    const Hint(
                      'Резерв хранится на доступных счетах: деньги остаются '
                      'на месте, но перестают считаться свободными.',
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
                  final amount = parseMoney(amountController.text);
                  if (amount == null || amount <= 0) {
                    setState(() => errorText = 'Введите сумму.');
                    return;
                  }
                  final error = data.addToReserve(
                    expense,
                    withdraw ? -amount : amount,
                    fromAccountId: fromAccountId,
                  );
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                  Navigator.pop(dialogContext);
                },
                child: const Text('Готово'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// История фактических оплат платежа.
void showPaymentHistory(
  BuildContext context,
  AppData data,
  MandatoryExpense expense,
) {
  final payments = data.paymentsOf(expense.id);
  final average = data.averagePayment(expense.id);

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                expense.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              StatRow('Плановая сумма', formatMoney(expense.amount)),
              if (average != null)
                StatRow('Средняя фактическая', formatMoney(average), bold: true),
              const SizedBox(height: 12),
              if (payments.isEmpty) const EmptyHint('Оплат пока не было'),
              ...payments.map(
                (t) => StatRow(
                  '${monthName(t.date.month)} ${t.date.year} · '
                  '${formatDate(t.date)}',
                  formatMoney(t.amount),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
