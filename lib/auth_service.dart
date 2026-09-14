import 'dart:convert' show jsonDecode;

import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:ap_python_launcher_app/connect/connect.dart' show navigateTo;
import 'package:ap_python_launcher_app/http_client/http_client.dart'
    show createHttpClient;
import 'package:http/http.dart' show Client, Request, Response;

/// Represents the authentication state returned by the backend.
class AuthStatus {
  /// Creates an [AuthStatus].
  AuthStatus({required this.authenticated, this.subject, this.email});

  /// Deserializes an [AuthStatus] from a JSON response.
  factory AuthStatus.fromJson(final Map<String, dynamic> json) {
    return AuthStatus(
      authenticated: (json['authenticated'] as bool?) ?? false,
      subject: json['subject'] as String?,
      email: json['email'] as String?,
    );
  }

  /// Whether the user has an authenticated session.
  final bool authenticated;

  /// The authenticated subject identifier, when available.
  final String? subject;

  /// The authenticated user's email address, when available.
  final String? email;
}

/// Defines the authentication actions used by the launcher.
abstract class AuthService {
  /// Retrieves the user's current authentication status.
  Future<AuthStatus> getAuthStatus();

  /// Starts the login flow.
  void login();

  /// Starts the logout flow.
  void logout();
}

/// Implements [AuthService] through the launcher HTTP API.
class HttpAuthService implements AuthService {
  /// Creates an [HttpAuthService].
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
