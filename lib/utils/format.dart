/// Форматирование денег, дат и вспомогательные функции.
library;

const List<String> _monthsNominative = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

const List<String> _monthsGenitive = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// Валюты счетов.
const Map<String, String> currencySymbols = {
  'RUB': '₽',
  'USD': '\$',
  'EUR': '€',
  'CNY': '¥',
};

const Map<String, String> currencyTitles = {
  'RUB': 'Рубль, ₽',
  'USD': 'Доллар, \$',
  'EUR': 'Евро, €',
  'CNY': 'Юань, ¥',
};

String currencySymbol(String currency) {
  return currencySymbols[currency] ?? currency;
}

/// 15 000 ₽, 104 072,72 ₽, −500 ₽.
String formatMoney(double amount, {String currency = 'RUB'}) {
  final negative = amount < -0.004;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final kopecks = parts[1];

  final buffer = StringBuffer();

  for (var i = 0; i < intPart.length; i++) {
    buffer.write(intPart[i]);

    final positionFromEnd = intPart.length - i;

    if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
      buffer.write(' ');
    }
  }

  final number =
      kopecks == '00' ? buffer.toString() : '$buffer,$kopecks';

  return '${negative ? '−' : ''}$number ${currencySymbol(currency)}';
}

/// «+1 387,63 ₽» / «−500 ₽».
String formatSigned(double amount) {
  if (amount > 0.004) {
    return '+${formatMoney(amount)}';
  }

  return formatMoney(amount);
}

/// Сумма без копеек: «12 500 ₽» (для крупных итогов в аналитике).
String formatMoneyRound(double amount) {
  return formatMoney(amount.roundToDouble());
}

/// 16 → «16%», 7.5 → «7,5%».
String formatPercent(double value, {int digits = 1}) {
  final rounded = double.parse(value.toStringAsFixed(digits));

  if (rounded == rounded.roundToDouble()) {
    return '${rounded.round()}%';
  }

  return '${rounded.toStringAsFixed(digits).replaceAll('.', ',')}%';
}

/// Сумма для поля ввода: 15000 или 104072,72.
String moneyToInput(double amount) {
  final fixed = amount.toStringAsFixed(2);

  if (fixed.endsWith('.00')) {
    return fixed.substring(0, fixed.length - 3);
  }

  return fixed.replaceAll('.', ',');
}

/// Разбирает сумму из текста: «1 500,50», «1500.5», «-200».
double? parseMoney(String text) {
  final normalized = text
      .replaceAll(RegExp(r'[\s ₽]'), '')
      .replaceAll('−', '-')
      .replaceAll(',', '.');

  if (normalized.isEmpty) {
    return null;
  }

  return double.tryParse(normalized);
}

/// Округление до копеек, чтобы не копились ошибки double.
double roundMoney(double value) {
  return (value * 100).roundToDouble() / 100;
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');

  return '$day.$month.${date.year}';
}

/// «10 сентября» (год добавляется, если он не текущий).
String formatDayMonth(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final base = '${date.day} ${_monthsGenitive[date.month - 1]}';

  if (date.year != current.year) {
    return '$base ${date.year}';
  }

  return base;
}

/// «сентября».
String monthGenitive(int month) => _monthsGenitive[month - 1];

/// «Сентябрь».
String monthName(int month) => _monthsNominative[month - 1];

/// «Сен».
String monthShort(int month) => _monthsNominative[month - 1].substring(0, 3);

/// «Сентябрь 2026».
String monthTitle(int year, int month) {
  return '${_monthsNominative[month - 1]} $year';
}

DateTime dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Прибавить месяцы. 31 января + 1 месяц = 28/29 февраля.
DateTime addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + (total / 12).floor();
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;

  return DateTime(year, month, day);
}

/// Количество дней между датами (без учёта времени).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);

  return b.difference(a).inDays;
}

/// Сколько дней в году (365 или 366).
int daysInYear(int year) {
  return DateTime(year + 1, 1, 1).difference(DateTime(year, 1, 1)).inDays;
}

/// Дата с нужным числом месяца (31 → последний день короткого месяца).
DateTime withDay(DateTime month, int day) {
  final lastDay = DateTime(month.year, month.month + 1, 0).day;

  return DateTime(month.year, month.month, day > lastDay ? lastDay : day);
}

/// Номер месяца для сравнения: 2026*12 + 9.
int monthIndex(DateTime date) => date.year * 12 + date.month - 1;

/// Сколько календарных месяцев осталось до [to], включая текущий.
/// 17 октября → 15 мая следующего года = 8 (окт, ноя, …, май).
int monthsLeftInclusive(DateTime from, DateTime to) {
  final diff = monthIndex(to) - monthIndex(from) + 1;

  return diff < 1 ? 1 : diff;
}

/// Последний день месяца.
DateTime endOfMonth(DateTime date) => DateTime(date.year, date.month + 1, 0);

/// plural(5, 'день', 'дня', 'дней') → «дней».
String plural(int n, String one, String few, String many) {
  final mod10 = n.abs() % 10;
  final mod100 = n.abs() % 100;

  if (mod10 == 1 && mod100 != 11) {
    return one;
  }

  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return few;
  }

  return many;
}

int _lastId = 0;

/// Уникальный ID. В вебе время идёт с точностью до миллисекунд,
/// поэтому при создании нескольких записей подряд добавляем счётчик.
String newId() {
  var id = DateTime.now().microsecondsSinceEpoch;

  if (id <= _lastId) {
    id = _lastId + 1;
  }

  _lastId = id;

  return id.toString();
}
