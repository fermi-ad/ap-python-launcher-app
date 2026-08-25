import 'dart:convert' show jsonDecode;

import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:ap_python_launcher_app/connect/connect.dart' show navigateTo;
import 'package:http/http.dart' show Client, Request, Response;

import 'http_client/http_client.dart' show createHttpClient;

class AuthStatus {
  AuthStatus({required this.authenticated, this.subject, this.email});

  factory AuthStatus.fromJson(final Map<String, dynamic> json) {
    return AuthStatus(
      authenticated: (json['authenticated'] as bool?) ?? false,
      subject: json['subject'] as String?,
      email: json['email'] as String?,
    );
  }

  final bool authenticated;
  final String? subject;
  final String? email;
}

abstract class AuthService {
  Future<AuthStatus> getAuthStatus();

  void login();

  void logout();
}

class HttpAuthService implements AuthService {
  HttpAuthService({
    Config config = Config.defaults,
    final Client? client,
  }) : _baseUri = Uri.parse(
         config.apiBaseUrl.isEmpty ? 'http://localhost/' : config.apiBaseUrl,
       ),
       _client = client ?? createHttpClient();

  final Uri _baseUri;
  final Client _client;

  @override
  Future<AuthStatus> getAuthStatus() async {
    final uri = _baseUri.resolve('auth/status');

    final req = Request('GET', uri);
    req.headers['Accept'] = 'application/json';

    final streamed = await _client.send(req);
    final res = await Response.fromStream(streamed);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return AuthStatus(authenticated: false);
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return AuthStatus.fromJson(decoded);
    }

    return AuthStatus(authenticated: false);
  }

  @override
  void login() {
    final uri = _baseUri.resolve('auth/login');
    navigateTo(uri.toString());
  }

  @override
  void logout() {
    final uri = _baseUri.resolve('auth/logout');
    navigateTo(uri.toString());
  }
}
