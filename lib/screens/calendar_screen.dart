import 'package:flutter/material.dart';

import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transactions_screen.dart' show MonthSwitcher;

/// Финансовый календарь: прошлые операции и будущие движения денег.
class CalendarScreen extends StatefulWidget {
  final AppData data;

  const CalendarScreen({super.key, required this.data});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime month;
  DateTime? selectedDay;

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
      appBar: AppBar(title: const Text('Календарь')),
      body: ListenableBuilder(
        listenable: data.all,
        builder: (context, _) {
          final now = DateTime.now();
          final today = dateOnly(now);
          final events =
              Insights(data, now).events(month, endOfMonth(month));
          final byDay = <DateTime, List<FinEvent>>{};
          for (final event in events) {
            byDay.putIfAbsent(event.date, () => []).add(event);
          }

          final visible = selectedDay == null
              ? events.where((e) => !e.date.isBefore(today)).toList()
              : byDay[selectedDay] ?? const <FinEvent>[];

          final futureOut = events
              .where((e) =>
                  !e.date.isBefore(today) &&
                  (e.kind == EventKind.payment))
              .fold(0.0, (s, e) => s + (e.amount ?? 0));
          final futureIn = events
              .where((e) =>
                  !e.date.isBefore(today) &&
                  (e.kind == EventKind.income || e.kind == EventKind.interest))
              .fold(0.0, (s, e) => s + (e.amount ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
            children: [
              MonthSwitcher(
                month: month,
                onChanged: (value) => setState(() {
                  month = value;
                  selectedDay = null;
                }),
              ),
              AppCard(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: _grid(byDay, today),
              ),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _legend('Платёж', kExpenseColor),
                  _legend('Доход', kIncomeColor),
                  _legend('Проценты', kSavingsColor),
                  _legend('Цель / вклад', kTransferColor),
                  _legend('Прошлые траты', Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              if (futureOut > 0 || futureIn > 0)
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      StatRow('Ожидается поступлений', formatMoney(futureIn),
                          color: kIncomeColor),
                      StatRow('Ожидается платежей', formatMoney(futureOut),
                          color: kExpenseColor),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedDay == null
                            ? 'Предстоящие события'
                            : '${selectedDay!.day} ${monthGenitive(selectedDay!.month)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (selectedDay != null)
                      TextButton(
                        onPressed: () => setState(() => selectedDay = null),
                        child: const Text('Все'),
                      ),
                  ],
                ),
              ),
              if (visible.isEmpty)
                const EmptyHint('Событий нет'),
              ...visible.map((event) => _eventTile(event, now)),
            ],
          );
        },
      ),
    );
  }

  Color _colorOf(FinEvent event) {
    switch (event.kind) {
      case EventKind.payment:
        return kExpenseColor;
      case EventKind.income:
        return kIncomeColor;
      case EventKind.interest:
        return kSavingsColor;
      case EventKind.goal:
      case EventKind.depositEnd:
        return kTransferColor;
      case EventKind.pastIncome:
        return kIncomeColor.withValues(alpha: 0.5);
      case EventKind.pastExpense:
        return Colors.grey;
    }
  }

  Widget _grid(Map<DateTime, List<FinEvent>> byDay, DateTime today) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = endOfMonth(month).day;
    final offset = first.weekday - 1;
    final cells = offset + daysInMonth;
    final rows = (cells / 7).ceil();
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Column(
      children: [
        Row(
          children: weekdays
              .map(
                (d) => Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: List.generate(7, (c) {
              final index = r * 7 + c - offset + 1;
              if (index < 1 || index > daysInMonth) {
                return const Expanded(child: SizedBox(height: 46));
              }
              final day = DateTime(month.year, month.month, index);
              final events = byDay[day] ?? const <FinEvent>[];
              final isToday = day == today;
              final isSelected = day == selectedDay;
              final colors = events.map(_colorOf).toSet().take(3).toList();

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(
                    () => selectedDay = isSelected ? null : day,
                  ),
                  child: Container(
                    height: 46,
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                            color: day.isBefore(today)
                                ? Colors.grey.shade500
                                : null,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: colors
                              .map(
                                (color) => Container(
                                  width: 6,
                                  height: 6,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _legend(String title, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(title, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _eventTile(FinEvent event, DateTime now) {
    final color = _colorOf(event);
    final sign = event.amount == null
        ? ''
        : event.isIncoming
            ? '+'
            : '−';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: event.overdue ? Colors.red.shade700 : null,
                  ),
                ),
                Text(
                  formatDayMonth(event.date, now: now),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (event.amount != null)
            Text(
              '$sign${formatMoney(event.amount!)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
        ],
      ),
    );
  }
}
