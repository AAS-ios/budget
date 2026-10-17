import 'package:flutter/material.dart';

import '../models/category_store.dart';
import '../models/transaction.dart';
import '../services/app_data.dart';
import '../utils/format.dart';
import '../widgets/category_picker.dart';
import '../widgets/common.dart';
import 'budget_screen.dart' show showDistributionSheet;
import 'categories_screen.dart';
import 'manage_list_screen.dart';

/// Добавление новой операции или редактирование существующей.
class AddTransactionScreen extends StatefulWidget {
  final AppData data;
  final TransactionType initialType;

  /// Если задано — редактируем эту операцию.
  final Transaction? existing;

  /// Счёт, который выбрать по умолчанию.
  final String? initialAccountId;

  const AddTransactionScreen({
    super.key,
    required this.data,
    this.initialType = TransactionType.expense,
    this.existing,
    this.initialAccountId,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late TransactionType selectedType;

  final amountController = TextEditingController();
  final commentController = TextEditingController();

  String? selectedAccountId;
  String? selectedDestinationAccountId;
  String? selectedCategory;
  String? selectedSubcategory;
  String? selectedIncomeSourceId;

  TransactionPriority selectedPriority = TransactionPriority.necessary;

  DateTime selectedDate = DateTime.now();

  AppData get data => widget.data;

  bool get isEditing => widget.existing != null;

  bool get isAdjustment => selectedType == TransactionType.adjustment;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;
    final accounts = data.accounts.active;

    if (existing != null) {
      selectedType = existing.type;
      amountController.text = moneyToInput(existing.amount);
      commentController.text =
          existing.isMandatoryPayment ? '' : existing.comment;
      selectedDate = existing.date;

      selectedAccountId = data.accounts.getById(existing.accountId)?.id;
      selectedDestinationAccountId =
          data.accounts.getById(existing.destinationAccountId)?.id;
      selectedCategory = existing.category;
      selectedSubcategory = existing.subcategory;
      selectedIncomeSourceId =
          data.incomeSources.getByName(existing.incomeSource)?.id;
      selectedPriority = existing.priority ?? TransactionPriority.necessary;
    } else {
      selectedType = widget.initialType;

      selectedAccountId =
          data.accounts.getById(widget.initialAccountId)?.id ??
              (accounts.isNotEmpty ? accounts.first.id : null);
    }

    if (selectedCategory == null) {
      final regular = data.categories.topLevel
          .where((c) => c.name != CategoryStore.mandatoryCategoryName)
          .toList();
      selectedCategory = regular.isNotEmpty ? regular.first.name : null;
    }

    if (selectedIncomeSourceId == null &&
        data.incomeSources.sources.isNotEmpty) {
      selectedIncomeSourceId = data.incomeSources.sources.first.id;
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    commentController.dispose();
    super.dispose();
  }

  String get title {
    switch (selectedType) {
      case TransactionType.expense:
        return isEditing ? 'Расход' : 'Новый расход';
      case TransactionType.income:
        if (widget.existing?.isInterest ?? false) {
          return 'Проценты по вкладу';
        }
        return isEditing ? 'Доход' : 'Новый доход';
      case TransactionType.transfer:
        return isEditing ? 'Перевод' : 'Новый перевод';
      case TransactionType.adjustment:
        return 'Корректировка';
    }
  }

  Future<void> _selectDate() async {
    final pickedDate = await pickDate(context, selectedDate);

    if (pickedDate == null) {
      return;
    }

    setState(() {
      // Сохраняем текущее время, чтобы операции за один день
      // шли в порядке добавления.
      final now = DateTime.now();
      selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        now.hour,
        now.minute,
        now.second,
      );
    });
  }

  void _save() {
    final amount = parseMoney(amountController.text);

    if (amount == null || (isAdjustment ? amount == 0 : amount <= 0)) {
      showMessage(context, 'Введите корректную сумму.');
      return;
    }

    if (selectedAccountId == null) {
      showMessage(context, 'Выберите счёт.');
      return;
    }

    final isExpense = selectedType == TransactionType.expense;
    final isIncome = selectedType == TransactionType.income;
    final isTransfer = selectedType == TransactionType.transfer;

    final existing = widget.existing;
    final keepsMandatory =
        existing != null && existing.isMandatoryPayment && isExpense;

    final transaction = Transaction(
      id: existing?.id ?? newId(),
      type: selectedType,
      amount: roundMoney(amount),
      date: selectedDate,
      accountId: selectedAccountId!,
      destinationAccountId: isTransfer ? selectedDestinationAccountId : null,
      category: isExpense ? selectedCategory : null,
      subcategory: isExpense ? selectedSubcategory : null,
      priority: isExpense ? selectedPriority : null,
      incomeSource: isIncome
          ? (existing?.isInterest ?? false)
              ? existing!.incomeSource
              : data.incomeSources.getById(selectedIncomeSourceId)?.name
          : null,
      comment: keepsMandatory ? existing.comment : commentController.text.trim(),
      mandatoryExpenseId: isExpense ? existing?.mandatoryExpenseId : null,
      depositInterestFor: isIncome ? existing?.depositInterestFor : null,
    );

    final error = existing == null
        ? data.addTransaction(transaction)
        : data.updateTransaction(existing, transaction);

    if (error != null) {
      showMessage(context, error);
      return;
    }

    final navigator = Navigator.of(context);
    navigator.pop();

    // Крупный новый доход — сразу показываем, как его распределить.
    if (existing == null && isIncome && amount >= 5000) {
      showDistributionSheet(navigator.context, data, amount, selectedDate);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;

    if (existing == null) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удалить операцию?',
      message: 'Деньги вернутся на счёт, как будто операции не было.',
    );

    if (!confirmed || !mounted) {
      return;
    }

    data.deleteTransaction(existing);
    Navigator.of(context).pop();
  }

  Future<void> _openIncomeSourceManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManageListScreen(
          title: 'Источники дохода',
          addTitle: 'Новый источник дохода',
          addHint: 'Например: Премия',
          listenable: data.incomeSources,
          items: () => data.incomeSources.sources
              .map(
                (source) => ManageListItem(
                  id: source.id,
                  name: source.name,
                  isDefault: source.isDefault,
                ),
              )
              .toList(),
          onAdd: (name) {
            final id = data.incomeSources.addSource(name);
            if (id != null) {
              selectedIncomeSourceId = id;
            }
          },
          onDelete: data.incomeSources.deleteSource,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      if (data.incomeSources.getById(selectedIncomeSourceId) == null) {
        final sources = data.incomeSources.sources;
        selectedIncomeSourceId = sources.isNotEmpty ? sources.first.id : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isInterest = widget.existing?.isInterest ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isEditing)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (!isAdjustment && !isInterest) ...[
              _buildTypeSelector(),
              const SizedBox(height: 24),
            ],
            if (isAdjustment)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Корректировка исправляет баланс счёта. Сумма со знаком: '
                  '«500» — прибавить, «-500» — убавить.',
                ),
              ),
            if (isInterest)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Начисление создано автоматически. Если банк начислил '
                  'другую сумму — исправьте её здесь.',
                ),
              ),
            _buildAmountField(),
            const SizedBox(height: 16),
            _buildAccountSelector(),
            const SizedBox(height: 16),
            if (selectedType == TransactionType.transfer) ...[
              _buildDestinationAccountSelector(),
              const SizedBox(height: 16),
            ],
            if (selectedType == TransactionType.expense)
              _buildExpenseFields(),
            if (selectedType == TransactionType.income && !isInterest)
              _buildIncomeFields(),
            const SizedBox(height: 16),
            _buildDateSelector(),
            const SizedBox(height: 16),
            _buildCommentField(),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Сохранить',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return SegmentedButton<TransactionType>(
      segments: const [
        ButtonSegment(
          value: TransactionType.expense,
          label: Text('Расход'),
        ),
        ButtonSegment(
          value: TransactionType.income,
          label: Text('Доход'),
        ),
        ButtonSegment(
          value: TransactionType.transfer,
          label: Text('Перевод'),
        ),
      ],
      showSelectedIcon: false,
      selected: {selectedType},
      onSelectionChanged: (selection) {
        setState(() {
          selectedType = selection.first;
        });
      },
    );
  }

  Widget _buildAmountField() {
    return TextField(
      controller: amountController,
      autofocus: !isEditing,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: isAdjustment,
      ),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: isAdjustment ? 'Изменение баланса' : 'Сумма',
        suffixText: currencySymbol(
          data.accounts.getById(selectedAccountId)?.currency ?? 'RUB',
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _accountDropdown({
    required String? value,
    required String label,
    required String keyPrefix,
    required bool Function(String id) exclude,
    required ValueChanged<String?> onChanged,
  }) {
    final accounts = data.accounts.accounts
        .where((a) => (!a.isClosed || a.id == value) && !exclude(a.id))
        .toList();
    final current = accounts.any((a) => a.id == value) ? value : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('$keyPrefix-$current-${accounts.length}'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: accounts.map((account) {
        return DropdownMenuItem<String>(
          value: account.id,
          child: Text(
            '${account.name} · ${account.money(account.balance)}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildAccountSelector() {
    return _accountDropdown(
      value: selectedAccountId,
      keyPrefix: 'account',
      label: selectedType == TransactionType.income
          ? 'На счёт'
          : selectedType == TransactionType.transfer
              ? 'Со счёта'
              : 'Счёт',
      exclude: (_) => false,
      onChanged: (value) {
        setState(() {
          selectedAccountId = value;
          if (selectedDestinationAccountId == value) {
            selectedDestinationAccountId = null;
          }
        });
      },
    );
  }

  Widget _buildDestinationAccountSelector() {
    return _accountDropdown(
      value: selectedDestinationAccountId,
      keyPrefix: 'destination-$selectedAccountId',
      label: 'На счёт',
      exclude: (id) => id == selectedAccountId,
      onChanged: (value) {
        setState(() {
          selectedDestinationAccountId = value;
        });
      },
    );
  }

  Widget _buildExpenseFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CategoryPicker(
                data: data,
                category: selectedCategory,
                subcategory: selectedSubcategory,
                outlined: true,
                onChanged: (category, subcategory) {
                  setState(() {
                    selectedCategory = category;
                    selectedSubcategory = subcategory;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Управление категориями',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CategoriesScreen(data: data),
                  ),
                );
                if (mounted) {
                  setState(() {});
                }
              },
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Насколько это было нужно?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...TransactionPriority.values.map(_buildPriorityOption),
      ],
    );
  }

  Widget _buildPriorityOption(TransactionPriority priority) {
    final selected = selectedPriority == priority;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? colorScheme.primaryContainer : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() {
              selectedPriority = priority;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(priority.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        priority.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        priority.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? colorScheme.primary : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncomeFields() {
    final sources = data.incomeSources.sources;

    final value = sources.any((s) => s.id == selectedIncomeSourceId)
        ? selectedIncomeSourceId
        : null;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('source-$value-${sources.length}'),
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Источник дохода',
              border: OutlineInputBorder(),
            ),
            items: sources.map((source) {
              return DropdownMenuItem<String>(
                value: source.id,
                child: Text(source.name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedIncomeSourceId = value;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Управление источниками дохода',
          onPressed: _openIncomeSourceManager,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final String label;

    if (isSameDay(selectedDate, now)) {
      label = 'Сегодня, ${formatDayMonth(selectedDate)}';
    } else if (isSameDay(selectedDate, now.subtract(const Duration(days: 1)))) {
      label = 'Вчера, ${formatDayMonth(selectedDate)}';
    } else {
      label = formatDate(selectedDate);
    }

    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Дата',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildCommentField() {
    return TextField(
      controller: commentController,
      maxLines: 3,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: isAdjustment ? 'Причина' : 'Комментарий',
        hintText: 'Можно оставить пустым',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Открыть экран редактирования операции.
void openTransactionEditor(
  BuildContext context,
  AppData data,
  Transaction transaction,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AddTransactionScreen(
        data: data,
        existing: transaction,
      ),
    ),
  );
}

/// Меню «Добавить операцию»: расход, доход, перевод.
void showAddOperationSheet(
  BuildContext context,
  AppData data, {
  String? accountId,
}) {
  if (data.accounts.active.isEmpty) {
    showMessage(context, 'Сначала добавьте счёт в разделе «Счета».');
    return;
  }

  void open(TransactionType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          data: data,
          initialType: type,
          initialAccountId: accountId,
        ),
      ),
    );
  }

  Widget option({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required TransactionType type,
    required BuildContext sheetContext,
  }) {
    return ListTile(
      leading: IconBox(
        icon: icon,
        color: color,
        background: color.withValues(alpha: 0.1),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      onTap: () {
        Navigator.pop(sheetContext);
        open(type);
      },
    );
  }

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Добавить операцию',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              option(
                icon: Icons.arrow_upward,
                color: kExpenseColor,
                title: 'Расход',
                subtitle: 'Покупка или другая трата денег',
                type: TransactionType.expense,
                sheetContext: sheetContext,
              ),
              option(
                icon: Icons.arrow_downward,
                color: kIncomeColor,
                title: 'Доход',
                subtitle: 'Зарплата, подработка, возврат и т.д.',
                type: TransactionType.income,
                sheetContext: sheetContext,
              ),
              option(
                icon: Icons.swap_horiz,
                color: kTransferColor,
                title: 'Перевод',
                subtitle: 'Между своими счетами, пополнение вклада',
                type: TransactionType.transfer,
                sheetContext: sheetContext,
              ),
            ],
          ),
        ),
      );
    },
  );
}
