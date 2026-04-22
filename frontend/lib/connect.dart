// Cross-platform helper to open a URL.
//
// - On web: uses `dart:js_interop` + `package:web`.
// - On other platforms (and in unit/widget tests): no-op.

import 'package:frontend/connect_stub.dart'
    if (dart.library.js_interop) 'connect_web.dart'
    as impl;

void openInNewTab(String url) => impl.openInNewTab(url);
