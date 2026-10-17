import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/transaction.dart';
import '../services/app_data.dart';
import '../services/insights.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';

class AccountScreen extends StatefulWidget {
  final AppData data;

  const AccountScreen({
    super.key,
    required this.data,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool showClosed = false;

  AppData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data.all,
      builder: (context, child) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final store = data.accounts;
    final closed = store.closed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Счета'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'ОБЩИЙ КАПИТАЛ',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatMoney(store.totalMoney),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                StatRow('Доступные деньги', formatMoney(store.availableMoney)),
                StatRow(
                  'На накопительных счетах',
                  formatMoney(store.savingsMoney),
                  color: kSavingsColor,
                ),
                StatRow(
                  'Во вкладах',
                  formatMoney(store.depositMoney),
                  color: kTransferColor,
                ),
                const Hint(
                  '«Доступно» — то, из чего считается дневной лимит. '
                  'Вклады в него не входят, но входят в капитал.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          for (final type in AccountType.values)
            if (store.byType(type).isNotEmpty) ...[
              SectionHeader(title: type.groupTitle),
              ...store.byType(type).map(
                    (account) => AccountCard(
                      data: data,
                      account: account,
                      onTap: () => pushScreen(
                        context,
                        AccountDetailsScreen(data: data, accountId: account.id),
                      ),
                    ),
                  ),
              const SizedBox(height: 14),
            ],

          if (store.accounts.isEmpty)
            const EmptyHint(
              'Счетов пока нет.\n'
              'Добавьте карты, наличные, накопления и вклады.',
            ),

          OutlinedButton.icon(
            onPressed: () => showAccountDialog(context, data),
            icon: const Icon(Icons.add),
            label: const Text('Добавить счёт'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          if (closed.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => setState(() => showClosed = !showClosed),
              icon: Icon(showClosed ? Icons.expand_less : Icons.expand_more),
              label: Text('Закрытые счета (${closed.length})'),
            ),
            if (showClosed)
              ...closed.map(
                (account) => AccountCard(
                  data: data,
                  account: account,
                  onTap: () => pushScreen(
                    context,
                    AccountDetailsScreen(data: data, accountId: account.id),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────
// КАРТОЧКА СЧЁТА
// ─────────────────────────────

class AccountCard extends StatelessWidget {
  final AppData data;
  final Account account;
  final VoidCallback onTap;

  const AccountCard({
    super.key,
    required this.data,
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deposit = account.deposit;
    final notes = <String>[
      if (account.isClosed) 'Закрыт',
      if (deposit != null)
        '${formatPercent(deposit.rate, digits: 2)} годовых'
            '${deposit.capitalization ? ', капитализация' : ''}',
      if (account.type == AccountType.deposit && deposit == null)
        'Укажите условия вклада',
      if (!account.isClosed &&
          account.type != AccountType.deposit &&
          !account.includeInAvailableMoney)
        'Не входит в доступные',
      if (!account.isRub) 'Валюта: ${account.currency}',
    ];

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBox(icon: accountIcon(account.type), size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: account.isClosed ? Colors.grey : null,
                  ),
                ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      notes.join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            account.money(account.balance),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

// ─────────────────────────────
// ПОДРОБНОСТИ СЧЁТА
// ─────────────────────────────

class AccountDetailsScreen extends StatelessWidget {
  final AppData data;
  final String accountId;

  const AccountDetailsScreen({
    super.key,
    required this.data,
    required this.accountId,
  });

  Future<void> _delete(BuildContext context, Account account) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Удалить счёт «${account.name}»?',
      message: 'Счёт исчезнет совсем. Операции по нему останутся в истории '
          'с пометкой «Удалённый счёт». Если счёт просто больше не нужен — '
          'лучше закрыть его, тогда история сохранится полностью.',
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    Navigator.of(context).pop();
    data.deleteAccount(account.id);
  }

  void _close(BuildContext context, Account account) {
    if (account.isClosed) {
      data.reopenAccount(account.id);
      return;
    }
    final error = data.closeAccount(account.id);
    showMessage(context, error ?? 'Счёт закрыт. Он виден в разделе «Закрытые».');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data.all,
      builder: (context, child) {
        final account = data.accounts.getById(accountId);

        if (account == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyHint('Счёт удалён'),
          );
        }

        final transactions = data.transactions.forAccount(account.id);
        final now = DateTime.now();

        return Scaffold(
          appBar: AppBar(
            title: Text(account.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      showAccountDialog(context, data, account: account);
                    case 'adjust':
                      showAdjustDialog(context, data, account);
                    case 'close':
                      _close(context, account);
                    case 'delete':
                      _delete(context, account);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  const PopupMenuItem(
                    value: 'adjust',
                    child: Text('Исправить баланс'),
                  ),
                  PopupMenuItem(
                    value: 'close',
                    child: Text(
                      account.isClosed ? 'Открыть снова' : 'Закрыть счёт',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить счёт'),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              AppCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Text(
                      [
                        account.type.title.toUpperCase(),
                        if (account.isClosed) 'ЗАКРЫТ',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      account.money(account.balance),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (account.openDate != null)
                      Hint('Открыт ${formatDate(account.openDate!)}'),
                    if (account.type != AccountType.deposit &&
                        !account.includeInAvailableMoney)
                      const Hint('Не учитывается в доступных деньгах'),
                    if (account.comment.isNotEmpty) Hint(account.comment),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: account.isClosed
                                ? null
                                : () => showAddOperationSheet(
                                      context,
                                      data,
                                      accountId: account.id,
                                    ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Операция'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                showAdjustDialog(context, data, account),
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('Исправить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (account.type == AccountType.deposit)
                _DepositBlock(data: data, account: account, now: now),
              const SizedBox(height: 12),
              const SectionHeader(title: 'История изменений'),
              ..._journal(context, account, transactions),
            ],
          ),
        );
      },
    );
  }

  /// Журнал: каждая операция и баланс после неё.
  List<Widget> _journal(
    BuildContext context,
    Account account,
    List<Transaction> transactions,
  ) {
    final rows = <Widget>[];
    var running = account.balance;

    for (final transaction in transactions) {
      final after = running;
      running -= transaction.effectOn(account.id);

      rows.add(
        TransactionTile(
          transaction: transaction,
          data: data,
          perspectiveAccountId: account.id,
          note: 'баланс ${account.money(after)}',
          onTap: () => openTransactionEditor(context, data, transaction),
        ),
      );
    }

    rows.add(
      AppCard(
        color: Colors.white.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            const IconBox(icon: Icons.flag_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Начальный баланс',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (account.openDate != null)
                    Hint('Открытие ${formatDate(account.openDate!)}'),
                ],
              ),
            ),
            Text(
              account.money(roundMoney(running)),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    return rows;
  }
}

class _DepositBlock extends StatelessWidget {
  final AppData data;
  final Account account;
  final DateTime now;

  const _DepositBlock({
    required this.data,
    required this.account,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final deposit = account.deposit;

    if (deposit == null || account.openDate == null) {
      return AppCard(
        onTap: () => showAccountDialog(context, data, account: account),
        child: const Text(
          'Укажите условия вклада (ставку, дату открытия, капитализацию) — '
          'тогда проценты будут начисляться автоматически.',
        ),
      );
    }

    final stats = Insights(data, now).depositStats(account);
    final interestAccount = data.accounts.getById(deposit.interestAccountId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const SectionHeader(title: 'Условия'),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              if (deposit.bank.isNotEmpty) StatRow('Банк', deposit.bank),
              StatRow('Ставка', '${formatPercent(deposit.rate, digits: 2)} годовых'),
              StatRow('Открыт', formatDate(account.openDate!)),
              StatRow(
                'Окончание',
                deposit.endDate == null
                    ? 'бессрочный'
                    : formatDate(deposit.endDate!),
              ),
              StatRow(
                'Проценты',
                deposit.period == InterestPeriod.atEnd
                    ? 'в конце срока'
                    : '${deposit.period.title.toLowerCase()}, '
                        '${deposit.payoutDay} числа',
              ),
              StatRow(
                'Капитализация',
                deposit.capitalization
                    ? 'да'
                    : 'нет → «${interestAccount?.name ?? account.name}»',
              ),
              StatRow(
                'Пополнение / снятие',
                '${deposit.canTopUp ? 'можно' : 'нельзя'} / '
                    '${deposit.canWithdraw ? 'можно' : 'нельзя'}',
              ),
              StatRow(
                'Проценты начислены по',
                formatDate(deposit.lastAccrualDate),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader(title: 'Доходность'),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              StatRow('Внесено', formatMoney(stats.deposited)),
              StatRow(
                'Начислено процентов',
                formatMoney(stats.interestTotal),
                color: kIncomeColor,
                bold: true,
              ),
              StatRow('В этом месяце', formatMoney(stats.interestThisMonth)),
              StatRow('За ${now.year} год', formatMoney(stats.interestThisYear)),
              if (stats.effectiveYield != null)
                StatRow(
                  'Фактическая доходность',
                  '${formatPercent(stats.effectiveYield!, digits: 2)} годовых',
                ),
              StatRow('Текущий баланс', formatMoney(account.balance)),
              if (stats.nextPayout != null)
                StatRow(
                  'Следующее начисление',
                  '≈ ${formatMoney(stats.nextPayout!.amount)}, '
                      '${formatDayMonth(stats.nextPayout!.date, now: now)}',
                ),
              const Divider(height: 20),
              StatRow(
                deposit.endDate != null && deposit.endDate!.isAfter(now)
                    ? 'К окончанию (${formatDate(stats.projectionDate)})'
                    : 'Через год (${formatDate(stats.projectionDate)})',
                formatMoney(stats.projection.balance),
                bold: true,
              ),
              StatRow(
                'Ожидаемые проценты',
                '+${formatMoney(stats.projection.interest)}',
                color: kIncomeColor,
              ),
              const Hint(
                'Проценты считаются по дням от суммы на вкладе на начало '
                'каждого дня, поэтому пополнения и снятия учитываются '
                'точно. Если банк начислил немного другую сумму — нажмите '
                'на начисление в истории и исправьте её.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────
// ДИАЛОГИ
// ─────────────────────────────

/// Диалог создания или редактирования счёта.
void showAccountDialog(
  BuildContext context,
  AppData data, {
  Account? account,
}) {
  final isNew = account == null;
  final deposit = account?.deposit;

  final nameController = TextEditingController(text: account?.name ?? '');
  final balanceController = TextEditingController();
  final commentController = TextEditingController(text: account?.comment ?? '');
  final bankController = TextEditingController(text: deposit?.bank ?? '');
  final initialController = TextEditingController(
    text: deposit == null || deposit.initialAmount == 0
        ? ''
        : moneyToInput(deposit.initialAmount),
  );
  final rateController = TextEditingController(
    text: deposit == null ? '' : moneyToInput(deposit.rate),
  );

  AccountType selectedType = account?.type ?? AccountType.debitCard;
  String currency = account?.currency ?? 'RUB';
  bool includeInAvailable = account?.includeInAvailableMoney ?? true;
  DateTime? openDate = account?.openDate;
  DateTime? endDate = deposit?.endDate;
  InterestPeriod period = deposit?.period ?? InterestPeriod.monthly;
  int? payoutDay = deposit?.payoutDay;
  bool capitalization = deposit?.capitalization ?? true;
  bool canTopUp = deposit?.canTopUp ?? true;
  bool canWithdraw = deposit?.canWithdraw ?? false;
  String? interestAccountId = deposit?.interestAccountId;
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final isDeposit = selectedType == AccountType.deposit;

          return AlertDialog(
            title: Text(isNew ? 'Новый счёт' : 'Изменить счёт'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Например, Т-Банк',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AccountType>(
                    isExpanded: true,
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Тип счёта'),
                    items: AccountType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.title),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedType = value;
                        includeInAvailable = value == AccountType.debitCard ||
                            value == AccountType.cash;
                      });
                    },
                  ),
                  Hint(selectedType.hint),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: 'Валюта'),
                    items: currencyTitles.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => currency = value);
                      }
                    },
                  ),
                  if (currency != 'RUB')
                    const Hint(
                      'Валютные счета показываются отдельно и не входят '
                      'в рублёвые итоги.',
                    ),
                  const SizedBox(height: 12),
                  if (isNew)
                    MoneyField(
                      controller: balanceController,
                      label: 'Текущий баланс',
                      signed: true,
                      suffix: currencySymbol(currency),
                    )
                  else
                    Hint(
                      'Баланс: ${account.money(account.balance)}. Чтобы '
                      'исправить его, используйте «Исправить баланс» — '
                      'изменение сохранится в истории.',
                    ),
                  DateTile(
                    title: 'Дата открытия',
                    date: openDate,
                    onChanged: (value) => setDialogState(() {
                      openDate = value;
                      payoutDay ??= value.day;
                    }),
                    onClear: isDeposit
                        ? null
                        : () => setDialogState(() => openDate = null),
                  ),
                  if (!isDeposit)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Учитывать в доступных деньгах'),
                      subtitle: const Text(
                        'Из этих денег считается, сколько можно '
                        'тратить в день',
                      ),
                      value: includeInAvailable,
                      onChanged: (value) =>
                          setDialogState(() => includeInAvailable = value),
                    ),
                  if (isDeposit) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Условия вклада',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextField(
                      controller: bankController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Банк'),
                    ),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: initialController,
                      label: 'Первоначальная сумма',
                      helper: isNew
                          ? 'Сколько внесли при открытии. Если пусто — '
                              'равна текущему балансу.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: rateController,
                      label: 'Ставка',
                      suffix: '% годовых',
                    ),
                    DateTile(
                      title: 'Дата окончания',
                      date: endDate,
                      emptyText: 'Бессрочный',
                      onChanged: (value) =>
                          setDialogState(() => endDate = value),
                      onClear: () => setDialogState(() => endDate = null),
                    ),
                    DropdownButtonFormField<InterestPeriod>(
                      isExpanded: true,
                      initialValue: period,
                      decoration: const InputDecoration(
                        labelText: 'Начисление процентов',
                      ),
                      items: InterestPeriod.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.title),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => period = value);
                        }
                      },
                    ),
                    if (period != InterestPeriod.atEnd) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: payoutDay ?? openDate?.day ?? 1,
                        decoration: const InputDecoration(
                          labelText: 'Число месяца, когда начисляются проценты',
                        ),
                        items: List.generate(
                          31,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (value) =>
                            setDialogState(() => payoutDay = value),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Капитализация'),
                      subtitle: const Text(
                        'Проценты прибавляются к вкладу, и дальше '
                        'начисляются уже на них',
                      ),
                      value: capitalization,
                      onChanged: (value) =>
                          setDialogState(() => capitalization = value),
                    ),
                    if (!capitalization)
                      AccountDropdown(
                        data: data,
                        value: interestAccountId,
                        label: 'Куда приходят проценты',
                        allowNone: true,
                        noneTitle: 'На сам вклад',
                        filter: (a) => a.id != account?.id,
                        onChanged: (value) =>
                            setDialogState(() => interestAccountId = value),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Можно пополнять'),
                      value: canTopUp,
                      onChanged: (value) =>
                          setDialogState(() => canTopUp = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Можно снимать до окончания'),
                      value: canWithdraw,
                      onChanged: (value) =>
                          setDialogState(() => canWithdraw = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
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
                  final name = nameController.text.trim();
                  final balance = readMoney(balanceController, empty: 0);

                  if (name.isEmpty) {
                    setDialogState(() => errorText = 'Введите название.');
                    return;
                  }

                  if (balance == null) {
                    setDialogState(
                      () => errorText = 'Баланс введён неправильно.',
                    );
                    return;
                  }

                  DepositInfo? newDeposit;

                  if (isDeposit) {
                    final rate = parseMoney(rateController.text);
                    final initial = readMoney(initialController);

                    if (rate == null || rate < 0) {
                      setDialogState(() => errorText = 'Укажите ставку.');
                      return;
                    }
                    if (openDate == null) {
                      setDialogState(
                        () => errorText = 'Укажите дату открытия вклада.',
                      );
                      return;
                    }

                    newDeposit = DepositInfo(
                      bank: bankController.text.trim(),
                      initialAmount: roundMoney(
                        initial ?? (isNew ? balance : account.balance),
                      ),
                      rate: rate,
                      endDate: endDate,
                      period: period,
                      payoutDay: payoutDay ?? openDate!.day,
                      capitalization: capitalization,
                      canTopUp: canTopUp,
                      canWithdraw: canWithdraw,
                      interestAccountId:
                          capitalization ? null : interestAccountId,
                      lastAccrualDate:
                          deposit?.lastAccrualDate ?? dateOnly(openDate!),
                    );
                  }

                  final result = Account(
                    id: account?.id ?? newId(),
                    name: name,
                    type: selectedType,
                    balance: isNew ? roundMoney(balance) : account.balance,
                    includeInAvailableMoney: isDeposit ? false : includeInAvailable,
                    currency: currency,
                    openDate: openDate,
                    comment: commentController.text.trim(),
                    isClosed: account?.isClosed ?? false,
                    deposit: newDeposit,
                  );

                  if (isNew) {
                    data.addAccount(result);
                  } else {
                    data.updateAccount(result);
                  }

                  Navigator.pop(dialogContext);
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Исправление баланса с указанием причины.
void showAdjustDialog(BuildContext context, AppData data, Account account) {
  final balanceController = TextEditingController(
    text: moneyToInput(account.balance),
  );
  final reasonController = TextEditingController();
  DateTime date = DateTime.now();
  String? errorText;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final newBalance = parseMoney(balanceController.text);
          final delta =
              newBalance == null ? null : newBalance - account.balance;

          return AlertDialog(
            title: const Text('Исправить баланс'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сейчас в приложении: ${account.money(account.balance)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: balanceController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Должно быть',
                      suffixText: currencySymbol(account.currency),
                      helperText: delta == null || delta.abs() < 0.005
                          ? null
                          : 'Изменение: ${delta > 0 ? '+' : ''}'
                              '${account.money(delta)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Причина',
                      hintText: 'Например: не записала кэшбэк',
                    ),
                  ),
                  DateTile(
                    title: 'Дата',
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  const Hint(
                    'Будет создана операция «Корректировка» — история '
                    'не удаляется, и всегда видно, почему изменился баланс.',
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
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
                  if (newBalance == null) {
                    setState(() => errorText = 'Введите сумму.');
                    return;
                  }
                  final now = DateTime.now();
                  final error = data.adjustBalance(
                    account.id,
                    newBalance,
                    reason: reasonController.text,
                    date: isSameDay(date, now) ? now : date,
                  );
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                  Navigator.pop(dialogContext);
                },
                child: const Text('Исправить'),
              ),
            ],
          );
        },
      );
    },
  );
}
