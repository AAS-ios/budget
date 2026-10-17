import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_data.dart';
import '../services/export.dart';
import '../utils/file_saver.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'categories_screen.dart';
import 'forecast_screen.dart';
import 'goals_screen.dart';
import 'manage_list_screen.dart';
import 'mandatory_expenses_screen.dart';
import 'recurring_screen.dart';
import 'transactions_screen.dart';

class MoreScreen extends StatelessWidget {
  final AppData data;

  const MoreScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const SectionHeader(title: 'Планирование'),
          MenuTile(
            icon: Icons.flag_outlined,
            title: 'Цели',
            subtitle: 'Подушка, отпуск, ремонт — сколько откладывать',
            onTap: () => pushScreen(context, GoalsScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.calendar_month_outlined,
            title: 'Финансовый календарь',
            subtitle: 'Платежи, доходы и проценты по датам',
            onTap: () => pushScreen(context, CalendarScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.trending_up,
            title: 'Прогноз',
            subtitle: 'Что будет с деньгами при текущем темпе',
            onTap: () => pushScreen(context, ForecastScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Обязательные платежи',
            onTap: () =>
                pushScreen(context, MandatoryExpensesScreen(data: data)),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Анализ'),
          MenuTile(
            icon: Icons.insights,
            title: 'Аналитика',
            subtitle: 'Куда уходят деньги, сравнения, средние',
            onTap: () => pushScreen(context, AnalyticsScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.repeat,
            title: 'Повторяющиеся расходы',
            onTap: () => pushScreen(context, RecurringScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.list_alt,
            title: 'История операций',
            onTap: () => pushScreen(context, TransactionsScreen(data: data)),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Настройки'),
          MenuTile(
            icon: Icons.category_outlined,
            title: 'Категории расходов',
            subtitle: 'Подкатегории и планы на месяц',
            onTap: () => pushScreen(context, CategoriesScreen(data: data)),
          ),
          MenuTile(
            icon: Icons.payments_outlined,
            title: 'Источники дохода',
            onTap: () => pushScreen(
              context,
              ManageListScreen(
                title: 'Источники дохода',
                addTitle: 'Новый источник дохода',
                addHint: 'Например: Премия',
                listenable: data.incomeSources,
                items: () => data.incomeSources.sources
                    .map(
                      (s) => ManageListItem(
                        id: s.id,
                        name: s.name,
                        isDefault: s.isDefault,
                      ),
                    )
                    .toList(),
                onAdd: data.incomeSources.addSource,
                onDelete: data.incomeSources.deleteSource,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Экспорт'),
          MenuTile(
            icon: Icons.table_chart_outlined,
            title: 'Выгрузить в Excel (CSV)',
            subtitle: 'Операции, счета, вклады, цели, аналитика',
            onTap: () => _showExport(context),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Резервная копия'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
            child: Text(
              'Все данные хранятся только на этом телефоне: без сервера, '
              'регистрации и интернета. Если удалить приложение или '
              'очистить данные Safari — они пропадут. Время от времени '
              'сохраняйте резервную копию в «Файлы» или в Telegram.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          if (filesSupported) ...[
            MenuTile(
              icon: Icons.save_alt,
              title: 'Сохранить копию в файл',
              onTap: () => _saveBackupFile(context),
            ),
            MenuTile(
              icon: Icons.file_open_outlined,
              title: 'Восстановить из файла',
              onTap: () => _restoreFromFile(context),
            ),
          ],
          MenuTile(
            icon: Icons.copy_all_outlined,
            title: 'Скопировать копию в буфер',
            onTap: () => _export(context),
          ),
          MenuTile(
            icon: Icons.content_paste_go,
            title: 'Восстановить из буфера',
            onTap: () => _import(context),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Опасная зона'),
          MenuTile(
            icon: Icons.delete_forever_outlined,
            title: 'Удалить все данные',
            color: Colors.red.shade700,
            onTap: () => _reset(context),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Мой бюджет · версия 2.0',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  String get _stamp {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _deliver(
    BuildContext context,
    String fileName,
    String content,
    String mime,
  ) async {
    final result = await saveTextFile(fileName, content, mime: mime);

    if (!context.mounted) {
      return;
    }

    switch (result) {
      case SaveResult.shared:
        break;
      case SaveResult.downloaded:
        showMessage(context, 'Файл «$fileName» сохранён');
      case SaveResult.unsupported:
        await Clipboard.setData(ClipboardData(text: content));
        if (context.mounted) {
          showMessage(
            context,
            'Сохранить файл не получилось — содержимое скопировано в буфер.',
          );
        }
    }
  }

  void _showExport(BuildContext context) {
    final export = CsvExport(data, DateTime.now());
    final files = <(String, String, String Function())>[
      ('Операции', 'operations', export.transactions),
      ('Счета', 'accounts', export.accounts),
      ('Вклады', 'deposits', export.deposits),
      ('Обязательные платежи', 'payments', export.mandatory),
      ('Цели', 'goals', export.goals),
      ('Бюджеты по категориям', 'budgets', export.budgets),
      ('Аналитика по месяцам', 'analytics', export.analytics),
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Выгрузка в CSV',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const Hint(
              'Файлы открываются в Excel, «Числах» и Google Таблицах.',
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            ),
            ...files.map(
              (file) => ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(file.$1),
                trailing: const Icon(Icons.ios_share),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deliver(
                    context,
                    '${file.$2}-$_stamp.csv',
                    file.$3(),
                    'text/csv',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveBackupFile(BuildContext context) {
    return _deliver(
      context,
      'moy-budget-$_stamp.json',
      data.exportJson(),
      'application/json',
    );
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    final text = await pickTextFile();

    if (text == null || !context.mounted) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Восстановить из файла?',
      message: 'Все текущие данные будут заменены данными из копии.',
      confirmText: 'Восстановить',
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      data.importJson(text);
      data.processScheduled(DateTime.now());
      showMessage(context, 'Данные восстановлены');
    } on FormatException catch (error) {
      showMessage(context, error.message);
    }
  }

  Future<void> _export(BuildContext context) async {
    final json = data.exportJson();
    await Clipboard.setData(ClipboardData(text: json));

    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Копия скопирована'),
        content: Text(
          'Резервная копия (${(json.length / 1024).toStringAsFixed(1)} КБ) '
          'в буфере обмена. Вставьте её в Заметки или отправьте себе '
          'в Telegram — и сохраните.\n\n'
          'Чтобы восстановить данные, скопируйте этот текст целиком '
          'и нажмите «Восстановить из буфера».',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final controller = TextEditingController();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboard?.text ?? '';

    if (clipboardText.contains('"moy-budget"')) {
      controller.text = clipboardText;
    }

    if (!context.mounted) {
      return;
    }

    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setState) {
            return AlertDialog(
              title: const Text('Восстановить из копии'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Все текущие данные будут заменены данными из копии.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      maxLines: 5,
                      minLines: 3,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Вставьте сюда текст резервной копии',
                        border: const OutlineInputBorder(),
                        errorText: errorText,
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final clip =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        setState(() {
                          controller.text = clip?.text ?? '';
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Вставить из буфера'),
                    ),
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
                    try {
                      data.importJson(controller.text);
                      data.processScheduled(DateTime.now());
                    } on FormatException catch (error) {
                      setState(() => errorText = error.message);
                      return;
                    }

                    Navigator.pop(dialogContext);
                    showMessage(context, 'Данные восстановлены');
                  },
                  child: const Text('Восстановить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Удалить все данные?',
      message: 'Счета, операции, платежи, цели и доходы будут удалены без '
          'возможности восстановления. Сначала сделайте резервную копию, '
          'если она нужна.',
      confirmText: 'Удалить всё',
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    data.resetAll();
    showMessage(context, 'Все данные удалены · ${formatDate(DateTime.now())}');
  }
}
