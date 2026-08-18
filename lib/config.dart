import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http show Client, get;

/// Runtime configuration for the app.
///
/// Obtain an instance by calling [Config.load] once in `main()` and passing
/// the result down to wherever it is needed.
///
/// Example config.json:
/// ```json
/// { "apiBaseUrl": "https://ad-apps-internal.fnal.gov/ap-python-launcher/api" }
/// ```
class Config {
  const Config._({required this.apiBaseUrl});

  /// A default [Config] with an empty [apiBaseUrl].
  ///
  /// Useful in tests where [apiBaseUrl] is irrelevant because an `ApiService`
  /// is injected directly.
  static const Config defaults = Config._(apiBaseUrl: '');

  /// Base URL for the launcher API.
  ///
  /// Empty string means API requests are made relative to the current origin.
  final String apiBaseUrl;

  /// Loads and returns the runtime configuration.
  ///
  /// In debug mode, returns immediately with [apiBaseUrl] set to `''`.
  /// In release/profile mode, fetches `config.json` from the current origin.
  ///
  /// An optional [client] may be supplied to override the default HTTP client,
  /// which is useful in tests.
  static Future<Config> load({final http.Client? client}) async {
    const definedBaseUrl = String.fromEnvironment('API_BASE_URL');

    if (kDebugMode) {
      debugPrint(
        'Config.load(debug): API_BASE_URL(dart-define)="$definedBaseUrl"',
      );
    }

    if (definedBaseUrl.isNotEmpty) {
      return Config.defaults;
    }

    try {
      final response = await (client != null
          ? client.get(Uri.parse('config.json'))
          : http.get(Uri.parse('config.json')));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Config._(
          apiBaseUrl: (json['apiBaseUrl'] as String?) ?? '',
        );
      }
    } on Object catch (e) {
      debugPrint(
        'Config.load: could not fetch config.json, using defaults. Error: $e',
      );
    }

    return Config.defaults;
  }
}
