/// Заглушка для сборок без браузера.
library;

enum SaveResult {
  shared,
  downloaded,
  unsupported,
}

/// Работа с файлами доступна.
bool get filesSupported => false;

Future<SaveResult> saveTextFile(
  String fileName,
  String content, {
  String mime = 'text/plain',
}) async {
  return SaveResult.unsupported;
}

/// Выбрать текстовый файл. null — отмена или не поддерживается.
Future<String?> pickTextFile({String accept = '.json,.txt'}) async {
  return null;
}
