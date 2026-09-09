import 'package:http/http.dart' show Client;

/// Creates the default HTTP client for non-web platforms.
Client createHttpClient() => Client();
