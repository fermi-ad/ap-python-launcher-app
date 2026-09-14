import 'package:ap_python_launcher_app/http_client/http_client_stub.dart'
    if (dart.library.js_interop) 'package:ap_python_launcher_app/http_client/http_client_web.dart'
    as impl;
import 'package:http/http.dart' show Client;

/// Creates an HTTP client appropriate for the current platform.
Client createHttpClient() => impl.createHttpClient();
