/// Web implementation: sets the browser tab title.
///
/// This file is only imported when `dart.library.js_interop` exists, so the
/// Android build never sees `dart:js_interop` (which is unavailable on the VM).
library;

import 'dart:js_interop';

@JS('document')
external _WebDoc get _doc;

extension type _WebDoc._(JSObject _) implements JSObject {
  external set title(String value);
}

void setBrowserTitle(String title) {
  try {
    _doc.title = title;
  } catch (_) {}
}
