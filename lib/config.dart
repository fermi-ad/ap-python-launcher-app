import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

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
  static Future<Config> load() async {
    if (kDebugMode) {
      return Config.defaults;
    }

    try {
      final response = await http.get(Uri.parse('config.json'));
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
    // Fallback: relative-origin API calls (missing / malformed config file)
    return Config.defaults;
  }
}
