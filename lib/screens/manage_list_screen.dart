import 'package:flutter/material.dart';

import '../widgets/common.dart';

class ManageListItem {
  final String id;
  final String name;
  final bool isDefault;

  const ManageListItem({
    required this.id,
    required this.name,
    required this.isDefault,
  });
}

/// Универсальный экран для списка названий:
/// категории расходов, источники дохода.
class ManageListScreen extends StatelessWidget {
  final String title;
  final String addTitle;
  final String addHint;
  final Listenable listenable;
  final List<ManageListItem> Function() items;
  final void Function(String name) onAdd;
  final void Function(String id) onDelete;

  const ManageListScreen({
    super.key,
    required this.title,
    required this.addTitle,
    required this.addHint,
    required this.listenable,
    required this.items,
    required this.onAdd,
    required this.onDelete,
  });

  Future<void> _add(BuildContext context) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(addTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Название',
              hintText: addHint,
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }

    onAdd(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final list = items();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              ...list.map(
                (item) => AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      if (item.isDefault)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'стандартная',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await confirmDialog(
                              context,
                              title: 'Удалить «${item.name}»?',
                              message: 'Старые операции с этим названием '
                                  'останутся в истории.',
                            );

                            if (confirmed) {
                              onDelete(item.id);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }
}
