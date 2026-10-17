/// Файлы в браузере: «Поделиться» (айфон) или скачивание.
library;

import 'dart:async';
import 'dart:js_interop';

enum SaveResult {
  shared,
  downloaded,
  unsupported,
}

bool get filesSupported => true;

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny?> parts, _TypeOptions options);
}

@JS('File')
extension type _File._(JSObject _) implements JSObject {
  external factory _File(
    JSArray<JSAny?> parts,
    String name,
    _TypeOptions options,
  );

  external JSPromise<JSString> text();
}

extension type _TypeOptions._(JSObject _) implements JSObject {
  external factory _TypeOptions({String type});
}

extension type _ShareData._(JSObject _) implements JSObject {
  external factory _ShareData({JSArray<_File> files, String title});
}

extension type _Navigator._(JSObject _) implements JSObject {
  external JSFunction? get share;
  external JSFunction? get canShare;

  @JS('share')
  external JSPromise<JSAny?> callShare(_ShareData data);

  @JS('canShare')
  external bool callCanShare(_ShareData data);
}

@JS('navigator')
external _Navigator get _navigator;

extension type _Element._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external set type(String value);
  external set accept(String value);
  external void click();
  external void remove();
  external _FileList? get files;
  external set onchange(JSFunction? handler);
  external set oncancel(JSFunction? handler);
  external _Style get style;
}

extension type _Style._(JSObject _) implements JSObject {
  external set display(String value);
}

extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _File? item(int index);
}

extension type _Body._(JSObject _) implements JSObject {
  external void appendChild(_Element element);
}

@JS('document.createElement')
external _Element _createElement(String tag);

@JS('document.body')
external _Body get _body;

@JS('URL.createObjectURL')
external String _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

Future<SaveResult> saveTextFile(
  String fileName,
  String content, {
  String mime = 'text/plain',
}) async {
  final parts = <JSAny?>[content.toJS].toJS;
  final type = '$mime;charset=utf-8';

  // На айфоне удобнее всего системное меню «Поделиться»:
  // можно сохранить в «Файлы», отправить в Telegram и т.д.
  try {
    if (_navigator.share != null && _navigator.canShare != null) {
      final file = _File(parts, fileName, _TypeOptions(type: type));
      final data = _ShareData(files: [file].toJS, title: fileName);

      if (_navigator.callCanShare(data)) {
        await _navigator.callShare(data).toDart;
        return SaveResult.shared;
      }
    }
  } catch (_) {
    // Отмена или запрет — пробуем обычное скачивание.
  }

  try {
    final blob = _Blob(parts, _TypeOptions(type: type));
    final url = _createObjectUrl(blob);
    final link = _createElement('a')
      ..href = url
      ..download = fileName;
    link.style.display = 'none';
    _body.appendChild(link);
    link.click();
    link.remove();
    Timer(const Duration(seconds: 30), () => _revokeObjectUrl(url));
    return SaveResult.downloaded;
  } catch (_) {
    return SaveResult.unsupported;
  }
}

Future<String?> pickTextFile({String accept = '.json,.txt'}) {
  final completer = Completer<String?>();
  final input = _createElement('input')
    ..type = 'file'
    ..accept = accept;
  input.style.display = 'none';

  void finish(String? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
    input.remove();
  }

  input.onchange = ((JSAny? _) {
    final file = input.files?.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    file.text().toDart.then(
          (text) => finish(text.toDart),
          onError: (Object _) => finish(null),
        );
  }).toJS;
  input.oncancel = ((JSAny? _) => finish(null)).toJS;

  _body.appendChild(input);
  input.click();

  return completer.future;
}
