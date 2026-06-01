// Cross-platform helper to open a URL.
//
// - On web: uses `dart:js_interop` + `package:web`.
// - On other platforms (and in unit/widget tests): no-op.

import 'package:ap_python_launcher_app/connect_stub.dart'
    if (dart.library.js_interop) 'connect_web.dart'
    as impl;

/// Opens [url] in a new browser tab.
///
/// On non-web platforms and in tests this is a no-op.
void openInNewTab(String url) => impl.openInNewTab(url);
