import 'package:flutter/foundation.dart';

import '../utils/format.dart';
import 'category.dart';

class CategoryStore extends ChangeNotifier {
  /// Категория, в которую попадают оплаты обязательных платежей
  /// без своей категории.
  static const String mandatoryCategoryName = 'Обязательные платежи';

  final List<ExpenseCategory> _categories = [];

  List<ExpenseCategory> get categories => List.unmodifiable(_categories);

  static List<ExpenseCategory> defaults() {
    ExpenseCategory top(String id, String name) =>
        ExpenseCategory(id: id, name: name, isDefault: true);

    ExpenseCategory sub(String parent, String id, String name) =>
        ExpenseCategory(id: id, name: name, parentId: parent);

    return [
      top('home', 'Дом'),
      sub('home', 'home_utilities', 'Коммунальные'),
      sub('home', 'home_internet', 'Интернет'),
      sub('home', 'home_goods', 'Бытовые товары'),
      top('food', 'Еда'),
      sub('food', 'food_products', 'Продукты'),
      sub('food', 'food_cafe', 'Кафе'),
      sub('food', 'food_delivery', 'Доставка'),
      top('transport', 'Транспорт'),
      sub('transport', 'transport_fuel', 'Бензин'),
      sub('transport', 'transport_public', 'Общественный транспорт'),
      sub('transport', 'transport_taxi', 'Такси'),
      top('personal', 'Личное'),
      sub('personal', 'personal_cosmetics', 'Косметика'),
      sub('personal', 'personal_clothes', 'Одежда'),
      sub('personal', 'personal_fun', 'Развлечения'),
      top('education', 'Учёба'),
      sub('education', 'education_books', 'Учебники'),
      sub('education', 'education_courses', 'Курсы'),
      sub('education', 'education_materials', 'Материалы'),
      top('health', 'Здоровье'),
      top('communication', 'Связь'),
      top('other', 'Прочее'),
      top('mandatory', mandatoryCategoryName),
    ];
  }

  void replaceAll(Iterable<ExpenseCategory> categories) {
    _categories
      ..clear()
      ..addAll(categories);

    // Категория для обязательных платежей должна быть всегда.
    final hasMandatory = _categories.any(
      (category) => category.name == mandatoryCategoryName,
    );

    if (!hasMandatory) {
      _categories.add(
        const ExpenseCategory(
          id: 'mandatory',
          name: mandatoryCategoryName,
          isDefault: true,
        ),
      );
    }

    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() {
    return _categories.map((category) => category.toJson()).toList();
  }

  /// Категории верхнего уровня.
  List<ExpenseCategory> get topLevel {
    return _categories.where((category) => category.isTopLevel).toList();
  }

  List<ExpenseCategory> childrenOf(String id) {
    return _categories.where((category) => category.parentId == id).toList();
  }

  ExpenseCategory? getById(String? id) {
    for (final category in _categories) {
      if (category.id == id) {
        return category;
      }
    }

    return null;
  }

  /// Категория верхнего уровня по имени.
  ExpenseCategory? getByName(String? name) {
    for (final category in _categories) {
      if (category.isTopLevel && category.name == name) {
        return category;
      }
    }

    return null;
  }

  /// Подкатегория по имени родителя и своему имени.
  ExpenseCategory? getSub(String? parentName, String? name) {
    final parent = getByName(parentName);

    if (parent == null || name == null) {
      return null;
    }

    for (final category in childrenOf(parent.id)) {
      if (category.name == name) {
        return category;
      }
    }

    return null;
  }

  /// Добавить категорию (или подкатегорию, если задан [parentId]).
  /// Возвращает ID новой (или уже существующей) категории.
  String? addCategory(String name, {String? parentId}) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return null;
    }

    for (final category in _categories) {
      if (category.parentId == parentId &&
          category.name.toLowerCase() == trimmedName.toLowerCase()) {
        return category.id;
      }
    }

    final category = ExpenseCategory(
      id: newId(),
      name: trimmedName,
      parentId: parentId,
    );

    _categories.add(category);
    notifyListeners();

    return category.id;
  }

  void updateCategory(ExpenseCategory category) {
    final index = _categories.indexWhere((item) => item.id == category.id);

    if (index == -1) {
      return;
    }

    _categories[index] = category;
    notifyListeners();
  }

  /// Удалить категорию вместе с подкатегориями.
  ///
  /// Категорию для обязательных платежей удалить нельзя.
  void deleteCategory(String id) {
    final category = getById(id);

    if (category == null || category.name == mandatoryCategoryName) {
      return;
    }

    _categories.removeWhere((item) => item.id == id || item.parentId == id);
    notifyListeners();
  }
}
