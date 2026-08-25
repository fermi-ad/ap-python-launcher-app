import 'package:http/http.dart' show Client;

import 'http_client_stub.dart'
    if (dart.library.js_interop) 'http_client_web.dart'
    as impl;

Client createHttpClient() => impl.createHttpClient();
