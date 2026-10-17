import 'package:flutter/foundation.dart';

import '../utils/format.dart';

enum GoalPriority {
  high,
  medium,
  low,
}

extension GoalPriorityTitle on GoalPriority {
  String get title {
    switch (this) {
      case GoalPriority.high:
        return 'Высокий';
      case GoalPriority.medium:
        return 'Средний';
      case GoalPriority.low:
        return 'Низкий';
    }
  }
}

/// Пополнение (или снятие, если сумма отрицательная) цели.
class GoalContribution {
  final String id;
  final DateTime date;
  final double amount;
  final String comment;

  const GoalContribution({
    required this.id,
    required this.date,
    required this.amount,
    this.comment = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'amount': amount,
        'comment': comment,
      };

  factory GoalContribution.fromJson(Map<String, dynamic> json) {
    return GoalContribution(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toDouble(),
      comment: json['comment'] as String? ?? '',
    );
  }
}

/// Финансовая цель: подушка, отпуск, ремонт…
class Goal {
  final String id;
  final String name;
  final double target;
  final DateTime? deadline;
  final GoalPriority priority;

  /// Счёт, на котором хранятся деньги цели.
  final String? accountId;

  /// Сколько откладывать в месяц, если срок не задан.
  final double? monthlyPlan;

  final List<GoalContribution> contributions;
  final bool isArchived;
  final DateTime createdAt;

  const Goal({
    required this.id,
    required this.name,
    required this.target,
    this.deadline,
    this.priority = GoalPriority.medium,
    this.accountId,
    this.monthlyPlan,
    this.contributions = const [],
    this.isArchived = false,
    required this.createdAt,
  });

  double get current => roundMoney(
        contributions.fold(0.0, (sum, item) => sum + item.amount),
      );

  double get remaining {
    final value = target - current;
    return value > 0 ? roundMoney(value) : 0;
  }

  bool get isReached => current + 0.004 >= target;

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0).toDouble();

  double contributedInMonth(int year, int month) {
    return contributions
        .where((item) => item.date.year == year && item.date.month == month)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  /// Сколько нужно откладывать в месяц, чтобы успеть к сроку.
  /// Считается от суммы на начало текущего месяца, чтобы
  /// не менялось после каждого пополнения.
  double monthlyNeed(DateTime now) {
    if (isArchived || isReached) {
      return 0;
    }

    if (deadline == null) {
      return monthlyPlan ?? 0;
    }

    final before = current - contributedInMonth(now.year, now.month);
    final left = target - before;

    if (left <= 0) {
      return 0;
    }

    return roundMoney(left / monthsLeftInclusive(now, deadline!));
  }

  /// Сколько ещё отложить в этом месяце по плану.
  double leftThisMonth(DateTime now) {
    final need = monthlyNeed(now) - contributedInMonth(now.year, now.month);
    return need > 0 ? roundMoney(need) : 0;
  }

  Goal copyWith({
    String? name,
    double? target,
    DateTime? deadline,
    bool clearDeadline = false,
    GoalPriority? priority,
    String? accountId,
    double? monthlyPlan,
    bool clearMonthlyPlan = false,
    List<GoalContribution>? contributions,
    bool? isArchived,
  }) {
    return Goal(
      id: id,
      name: name ?? this.name,
      target: target ?? this.target,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      priority: priority ?? this.priority,
      accountId: accountId ?? this.accountId,
      monthlyPlan:
          clearMonthlyPlan ? null : (monthlyPlan ?? this.monthlyPlan),
      contributions: contributions ?? this.contributions,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'deadline': deadline?.toIso8601String(),
        'priority': priority.name,
        'accountId': accountId,
        'monthlyPlan': monthlyPlan,
        'contributions': contributions.map((item) => item.toJson()).toList(),
        'isArchived': isArchived,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Goal.fromJson(Map<String, dynamic> json) {
    final deadline = json['deadline'] as String?;
    final priority = json['priority'] as String?;
    final createdAt = json['createdAt'] as String?;

    return Goal(
      id: json['id'] as String,
      name: json['name'] as String,
      target: (json['target'] as num).toDouble(),
      deadline: deadline == null ? null : DateTime.parse(deadline),
      priority: priority == null
          ? GoalPriority.medium
          : GoalPriority.values.byName(priority),
      accountId: json['accountId'] as String?,
      monthlyPlan: (json['monthlyPlan'] as num?)?.toDouble(),
      contributions: (json['contributions'] as List<dynamic>? ?? const [])
          .map(
            (item) => GoalContribution.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      isArchived: json['isArchived'] as bool? ?? false,
      createdAt:
          createdAt == null ? DateTime.now() : DateTime.parse(createdAt),
    );
  }
}

class GoalStore extends ChangeNotifier {
  final List<Goal> _goals = [];

  List<Goal> get goals => List.unmodifiable(_goals);

  /// Активные цели: сначала важные, потом по сроку.
  List<Goal> get active {
    return _goals.where((goal) => !goal.isArchived).toList()
      ..sort((a, b) {
        final byPriority = a.priority.index.compareTo(b.priority.index);
        if (byPriority != 0) {
          return byPriority;
        }
        final aDate = a.deadline ?? DateTime(2100);
        final bDate = b.deadline ?? DateTime(2100);
        return aDate.compareTo(bDate);
      });
  }

  List<Goal> get archived =>
      _goals.where((goal) => goal.isArchived).toList();

  void replaceAll(Iterable<Goal> goals) {
    _goals
      ..clear()
      ..addAll(goals);
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() =>
      _goals.map((goal) => goal.toJson()).toList();

  Goal? getById(String? id) {
    for (final goal in _goals) {
      if (goal.id == id) {
        return goal;
      }
    }
    return null;
  }

  void add(Goal goal) {
    _goals.add(goal);
    notifyListeners();
  }

  void update(Goal goal) {
    final index = _goals.indexWhere((item) => item.id == goal.id);
    if (index == -1) {
      return;
    }
    _goals[index] = goal;
    notifyListeners();
  }

  void delete(String id) {
    _goals.removeWhere((goal) => goal.id == id);
    notifyListeners();
  }
}
