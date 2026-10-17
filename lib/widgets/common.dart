import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/transaction.dart';
import '../services/app_data.dart';
import '../utils/format.dart';

export 'ui.dart';

const Color kBackground = Color(0xFFF6F7F9);

final Color kExpenseColor = Colors.red.shade700;
final Color kIncomeColor = Colors.green.shade700;
final Color kTransferColor = Colors.blue.shade700;
final Color kSavingsColor = Colors.teal.shade700;
final Color kWarningColor = Colors.orange.shade800;

IconData accountIcon(AccountType type) {
  switch (type) {
    case AccountType.debitCard:
      return Icons.credit_card_outlined;
    case AccountType.savings:
      return Icons.savings_outlined;
    case AccountType.deposit:
      return Icons.lock_outline;
    case AccountType.cash:
      return Icons.payments_outlined;
  }
}

/// Белая карточка со скруглёнными углами.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(17),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Квадратик с иконкой слева в карточках.
class IconBox extends StatelessWidget {
  final IconData icon;
  final Color? background;
  final Color? color;
  final double size;

  const IconBox({
    super.key,
    required this.icon,
    this.background,
    this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final String text;

  const EmptyHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// Строка операции в истории.
///
/// Если задан [perspectiveAccountId], знак перевода
/// считается с точки зрения этого счёта.
class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final AppData data;
  final String? perspectiveAccountId;
  final VoidCallback? onTap;

  /// Подпись под суммой (например, баланс после операции).
  final String? note;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.data,
    this.perspectiveAccountId,
    this.onTap,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = data.accounts;

    late final IconData icon;
    late final Color color;
    late final String sign;
    late final String subtitle;

    switch (transaction.type) {
      case TransactionType.adjustment:
        icon = Icons.tune;
        color = Colors.blueGrey.shade700;
        sign = transaction.amount >= 0 ? '+' : '';
        subtitle = accounts.nameOf(transaction.accountId);
      case TransactionType.expense:
        icon = transaction.isMandatoryPayment
            ? Icons.receipt_long_outlined
            : Icons.arrow_upward;
        color = kExpenseColor;
        sign = '−';
        subtitle = accounts.nameOf(transaction.accountId);
      case TransactionType.income:
        icon = transaction.isInterest ? Icons.percent : Icons.arrow_downward;
        color = kIncomeColor;
        sign = '+';
        subtitle = accounts.nameOf(transaction.accountId);
      case TransactionType.transfer:
        icon = Icons.swap_horiz;
        subtitle = '${accounts.nameOf(transaction.accountId)} → '
            '${accounts.nameOf(transaction.destinationAccountId)}';

        if (perspectiveAccountId == null) {
          color = kTransferColor;
          sign = '';
        } else if (perspectiveAccountId ==
            transaction.destinationAccountId) {
          color = kIncomeColor;
          sign = '+';
        } else {
          color = kExpenseColor;
          sign = '−';
        }
    }

    final details = <String>[
      formatDate(transaction.date),
      if (transaction.type == TransactionType.expense &&
          transaction.subcategory != null &&
          !transaction.isMandatoryPayment)
        transaction.category ?? '',
      subtitle,
      if (transaction.priority != null &&
          !transaction.isMandatoryPayment)
        transaction.priority!.emoji,
    ];

    final comment = transaction.isMandatoryPayment ? '' : transaction.comment;
    final currency =
        data.accounts.getById(transaction.accountId)?.currency ?? 'RUB';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        children: [
          IconBox(
            icon: icon,
            color: color,
            background: color.withValues(alpha: 0.08),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    comment,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${formatMoney(transaction.amount, currency: currency)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    note!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Диалог подтверждения. Возвращает true, если нажали «да».
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Удалить',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Выбор даты на русском.
Future<DateTime?> pickDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    locale: const Locale('ru'),
  );
}
