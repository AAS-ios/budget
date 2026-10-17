import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import 'common.dart';

/// Полоска прогресса со скруглением.
class ProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;

  const ProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble(),
        minHeight: height,
        color: color ?? Theme.of(context).colorScheme.primary,
        backgroundColor: Colors.grey.shade200,
      ),
    );
  }
}

/// Строка «название ............ значение».
class StatRow extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;
  final bool bold;
  final double fontSize;

  const StatRow(
    this.title,
    this.value, {
    super.key,
    this.color,
    this.bold = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(title, style: style)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: color,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Мелкий серый поясняющий текст.
class Hint extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const Hint(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(top: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }
}

/// Строка-переход в меню «Ещё» и похожих списках.
class MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconBox(icon: icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

/// Выпадающий список счетов.
///
/// [allowNone] добавляет пункт [noneTitle] со значением null.
class AccountDropdown extends StatelessWidget {
  final AppData data;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  final String noneTitle;
  final bool Function(Account account)? filter;

  const AccountDropdown({
    super.key,
    required this.data,
    required this.value,
    required this.label,
    required this.onChanged,
    this.allowNone = false,
    this.noneTitle = 'Не указан',
    this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = data.accounts.accounts
        .where(
          (account) =>
              (!account.isClosed || account.id == value) &&
              (filter == null || filter!(account) || account.id == value),
        )
        .toList();

    final current = accounts.any((a) => a.id == value) ? value : null;

    return DropdownButtonFormField<String?>(
      key: ValueKey('acc-$label-$current-${accounts.length}'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowNone || current == null)
          DropdownMenuItem<String?>(
            value: null,
            child: Text(allowNone ? noneTitle : 'Выберите счёт'),
          ),
        ...accounts.map(
          (account) => DropdownMenuItem<String?>(
            value: account.id,
            child: Text(
              '${account.name} · ${account.money(account.balance)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Поле ввода суммы.
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool signed;
  final String suffix;
  final String? helper;

  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Сумма',
    this.autofocus = false,
    this.signed = false,
    this.suffix = '₽',
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 3,
      ),
    );
  }
}

/// Строка выбора даты в диалогах.
class DateTile extends StatelessWidget {
  final String title;
  final DateTime? date;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onClear;
  final String emptyText;

  const DateTile({
    super.key,
    required this.title,
    required this.date,
    required this.onChanged,
    this.onClear,
    this.emptyText = 'Не указана',
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(date == null ? emptyText : formatDate(date!)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onClear != null && date != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
          const Icon(Icons.calendar_today),
        ],
      ),
      onTap: () async {
        final picked = await pickDate(context, date ?? DateTime.now());
        if (picked != null) {
          onChanged(picked);
        }
      },
    );
  }
}

/// Карточка с предупреждением.
class WarningTile extends StatelessWidget {
  final FinWarning warning;

  const WarningTile({super.key, required this.warning});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (warning.level) {
      WarningLevel.danger => (Icons.error_outline, Colors.red.shade700),
      WarningLevel.warning => (Icons.warning_amber_rounded, kWarningColor),
      WarningLevel.info => (Icons.info_outline, Colors.blue.shade700),
    };

    return AppCard(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              warning.text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Простая столбчатая диаграмма по месяцам: два столбика
/// (доходы и расходы) на месяц.
class MonthBars extends StatelessWidget {
  final List<MonthSummary> months;

  const MonthBars({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    final maxValue = months.fold(
      0.0,
      (m, s) => [m, s.income, s.expense].reduce((a, b) => a > b ? a : b),
    );

    Widget bar(double value, Color color) {
      final height = maxValue <= 0 ? 0.0 : 110 * value / maxValue;
      return Container(
        width: 10,
        height: height < 2 && value > 0 ? 2 : height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: months.map((summary) {
              return Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    bar(summary.income, kIncomeColor),
                    const SizedBox(width: 3),
                    bar(summary.expense, kExpenseColor),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: months
              .map(
                (summary) => Expanded(
                  child: Text(
                    monthShort(summary.month.month),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend('Доходы', kIncomeColor),
            const SizedBox(width: 16),
            _legend('Расходы', kExpenseColor),
          ],
        ),
      ],
    );
  }

  Widget _legend(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Строка с полоской доли: «Еда ……… 12 000 ₽ · 31%».
class ShareBar extends StatelessWidget {
  final String title;
  final double amount;
  final double total;
  final Color color;
  final String? suffix;

  const ShareBar({
    super.key,
    required this.title,
    required this.amount,
    required this.total,
    required this.color,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final share =
        total > 0 ? (amount / total).clamp(0.0, 1.0).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  suffix ??
                      '${formatMoney(amount)} · ${(share * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(value: share, color: color),
        ],
      ),
    );
  }
}

void pushScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// Разобрать сумму из поля. Пустое поле → [empty].
double? readMoney(TextEditingController controller, {double? empty}) {
  if (controller.text.trim().isEmpty) {
    return empty;
  }
  return parseMoney(controller.text);
}
