import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/category_store.dart';
import '../services/app_data.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Категории расходов: подкатегории, переименование, планы на месяц.
class CategoriesScreen extends StatelessWidget {
  final AppData data;

  const CategoriesScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Категории расходов')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final store = data.categories;
          final now = DateTime.now();
          final totalLimit = store.topLevel.fold(
            0.0,
            (sum, c) => sum + (c.monthlyLimit ?? 0),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Hint(
                'Нажмите на категорию, чтобы переименовать её, задать план '
                'на месяц или добавить подкатегорию.'
                '${totalLimit > 0 ? '\nСумма планов: ${formatMoney(totalLimit)} в месяц.' : ''}',
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              ),
              ...store.topLevel.map((category) {
                final children = store.childrenOf(category.id);
                final spent =
                    data.categorySpent(category.name, now.year, now.month);
                final limit = category.monthlyLimit;

                return AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _menu(context, category),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          limit == null
                              ? 'В этом месяце: ${formatMoney(spent)} · без плана'
                              : 'В этом месяце: ${formatMoney(spent)} из '
                                  '${formatMoney(limit)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: limit != null && spent > limit
                                ? kExpenseColor
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      if (limit != null) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ProgressBar(
                            value: limit <= 0 ? 0 : spent / limit,
                            color: spent > limit ? kExpenseColor : kIncomeColor,
                            height: 6,
                          ),
                        ),
                      ],
                      if (children.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 0,
                          children: children
                              .map(
                                (sub) => InputChip(
                                  label: Text(sub.name),
                                  onPressed: () =>
                                      _subMenu(context, category, sub),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await askName(context, title: 'Новая категория');
          if (name != null) {
            data.categories.addCategory(name);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Категория'),
      ),
    );
  }

  Widget _menu(BuildContext context, ExpenseCategory category) {
    final isMandatory = category.name == CategoryStore.mandatoryCategoryName;

    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'sub':
            final name = await askName(
              context,
              title: 'Подкатегория в «${category.name}»',
            );
            if (name != null) {
              data.categories.addCategory(name, parentId: category.id);
            }
          case 'limit':
            _editLimit(context, category);
          case 'rename':
            final name = await askName(
              context,
              title: 'Переименовать',
              initial: category.name,
            );
            if (name != null) {
              data.renameCategory(category.id, name);
            }
          case 'delete':
            final ok = await confirmDialog(
              context,
              title: 'Удалить «${category.name}»?',
              message: 'Подкатегории тоже удалятся. Старые операции '
                  'с этой категорией останутся в истории.',
            );
            if (ok) {
              data.categories.deleteCategory(category.id);
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'sub', child: Text('Добавить подкатегорию')),
        const PopupMenuItem(value: 'limit', child: Text('План на месяц')),
        if (!isMandatory) ...const [
          PopupMenuItem(value: 'rename', child: Text('Переименовать')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ],
    );
  }

  Future<void> _subMenu(
    BuildContext context,
    ExpenseCategory parent,
    ExpenseCategory sub,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${parent.name} · ${sub.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (action == 'rename') {
      final name = await askName(
        context,
        title: 'Переименовать',
        initial: sub.name,
      );
      if (name != null) {
        data.renameCategory(sub.id, name);
      }
    } else if (action == 'delete') {
      data.categories.deleteCategory(sub.id);
    }
  }

  Future<void> _editLimit(BuildContext context, ExpenseCategory category) async {
    final controller = TextEditingController(
      text: category.monthlyLimit == null
          ? ''
          : moneyToInput(category.monthlyLimit!),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('План: ${category.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyField(
              controller: controller,
              label: 'Сколько планируете тратить в месяц',
              autofocus: true,
              helper: 'Оставьте пустым, чтобы убрать план.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result == null) {
      return;
    }

    final limit = parseMoney(result);
    data.categories.updateCategory(
      limit == null || limit <= 0
          ? category.copyWith(clearLimit: true)
          : category.copyWith(monthlyLimit: roundMoney(limit)),
    );
  }
}

/// Спросить название. null — отмена.
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) async {
  final controller = TextEditingController(text: initial);

  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Название', hintText: hint),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Готово'),
        ),
      ],
    ),
  );

  if (name == null || name.trim().isEmpty) {
    return null;
  }

  return name.trim();
}
