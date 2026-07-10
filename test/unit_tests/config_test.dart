import 'dart:convert' show jsonEncode;

import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart' show MockClient;

void main() {
  group('Config.defaults', () {
    test('has an empty apiBaseUrl', () {
      expect(Config.defaults.apiBaseUrl, '');
    });
  });

  group('Config.load', () {
    test('returns apiBaseUrl from a 200 config.json response', () async {
      const url = 'https://example.fnal.gov/api';
      final client = MockClient(
        (_) async => Response(
          jsonEncode({'apiBaseUrl': url}),
          200,
        ),
      );

      final config = await Config.load(client: client);

      expect(config.apiBaseUrl, url);
    });

    test(
      'falls back to defaults when apiBaseUrl is absent from JSON',
      () async {
        final client = MockClient(
          (_) async => Response(jsonEncode(<String, dynamic>{}), 200),
        );

        final config = await Config.load(client: client);

        expect(config.apiBaseUrl, '');
      },
    );

    test('falls back to defaults on a non-200 response', () async {
      final client = MockClient(
        (_) async => Response('Not Found', 404),
      );

      final config = await Config.load(client: client);

      expect(config.apiBaseUrl, '');
    });

    test('falls back to defaults when the HTTP client throws', () async {
      final client = MockClient(
        (_) async => throw Exception('network error'),
      );

      final config = await Config.load(client: client);

      expect(config.apiBaseUrl, '');
    });

    test(
      'falls back to defaults when the response body is not valid JSON',
      () async {
        final client = MockClient(
          (_) async => Response('not-json', 200),
        );

        final config = await Config.load(client: client);

        expect(config.apiBaseUrl, '');
      },
    );
  });
}
