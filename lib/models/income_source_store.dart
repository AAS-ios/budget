import 'package:flutter/foundation.dart';

import '../utils/format.dart';
import 'income_source.dart';

class IncomeSourceStore extends ChangeNotifier {
  final List<IncomeSource> _sources = [];

  List<IncomeSource> get sources => List.unmodifiable(_sources);

  static List<IncomeSource> defaults() {
    return const [
      IncomeSource(id: 'salary', name: 'Зарплата', isDefault: true),
      IncomeSource(id: 'side_work', name: 'Подработка', isDefault: true),
      IncomeSource(id: 'cashback', name: 'Кэшбэк', isDefault: true),
      IncomeSource(id: 'refund', name: 'Возврат денег', isDefault: true),
      IncomeSource(
        id: 'deposit_interest',
        name: 'Проценты по вкладу',
        isDefault: true,
      ),
      IncomeSource(id: 'tax_refund', name: 'Налоговый вычет', isDefault: true),
      IncomeSource(id: 'transfer', name: 'Перевод', isDefault: true),
      IncomeSource(id: 'other', name: 'Другое', isDefault: true),
    ];
  }

  void replaceAll(Iterable<IncomeSource> sources) {
    _sources
      ..clear()
      ..addAll(sources);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() {
    return _sources.map((source) => source.toJson()).toList();
  }

  IncomeSource? getById(String? id) {
    for (final source in _sources) {
      if (source.id == id) {
        return source;
      }
    }

    return null;
  }

  IncomeSource? getByName(String? name) {
    for (final source in _sources) {
      if (source.name == name) {
        return source;
      }
    }

    return null;
  }

  /// Возвращает ID нового (или уже существующего) источника.
  String? addSource(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return null;
    }

    for (final source in _sources) {
      if (source.name.toLowerCase() == trimmedName.toLowerCase()) {
        return source.id;
      }
    }

    final source = IncomeSource(id: newId(), name: trimmedName);

    _sources.add(source);
    notifyListeners();

    return source.id;
  }

  void deleteSource(String id) {
    final index = _sources.indexWhere((source) => source.id == id);

    if (index == -1) {
      return;
    }

    // Стандартные источники удалить нельзя.
    if (_sources[index].isDefault) {
      return;
    }

    _sources.removeAt(index);
    notifyListeners();
  }
}
