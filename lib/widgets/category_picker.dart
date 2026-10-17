import 'package:flutter/material.dart';

import '../models/category_store.dart';
import '../services/app_data.dart';

/// Выбор категории и подкатегории (по именам, как они хранятся
/// в операциях).
class CategoryPicker extends StatelessWidget {
  final AppData data;
  final String? category;
  final String? subcategory;
  final void Function(String? category, String? subcategory) onChanged;

  /// Показывать «Обязательные платежи» в списке.
  final bool includeMandatory;

  /// Разрешить пустой выбор категории.
  final bool allowNone;
  final String noneTitle;
  final bool outlined;

  const CategoryPicker({
    super.key,
    required this.data,
    required this.category,
    required this.subcategory,
    required this.onChanged,
    this.includeMandatory = false,
    this.allowNone = false,
    this.noneTitle = 'Без категории',
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final store = data.categories;
    final tops = store.topLevel
        .where(
          (c) =>
              includeMandatory ||
              c.name != CategoryStore.mandatoryCategoryName ||
              c.name == category,
        )
        .toList();

    final current = tops.any((c) => c.name == category) ? category : null;
    final parent = store.getByName(current);
    final subs = parent == null ? const [] : store.childrenOf(parent.id);
    final currentSub =
        subs.any((c) => c.name == subcategory) ? subcategory : null;

    InputDecoration decoration(String label) => InputDecoration(
          labelText: label,
          border: outlined ? const OutlineInputBorder() : null,
        );

    return Column(
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey('cat-$current-${tops.length}'),
          initialValue: current,
          isExpanded: true,
          decoration: decoration('Категория'),
          items: [
            if (allowNone || current == null)
              DropdownMenuItem<String?>(
                value: null,
                child: Text(allowNone ? noneTitle : 'Выберите категорию'),
              ),
            ...tops.map(
              (c) => DropdownMenuItem<String?>(
                value: c.name,
                child: Text(c.name),
              ),
            ),
          ],
          onChanged: (value) => onChanged(value, null),
        ),
        if (subs.isNotEmpty) ...[
          SizedBox(height: outlined ? 16 : 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('sub-$current-$currentSub-${subs.length}'),
            initialValue: currentSub,
            isExpanded: true,
            decoration: decoration('Подкатегория'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— без подкатегории —'),
              ),
              ...subs.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.name,
                  child: Text(c.name),
                ),
              ),
            ],
            onChanged: (value) => onChanged(current, value),
          ),
        ],
      ],
    );
  }
}
