import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:http/http.dart' show Client, Request, Response;

/// Exception thrown when an HTTP API call returns a non-2xx status code.
class ApiException implements Exception {
  /// Creates an [ApiException] with the given HTTP [statusCode], [statusText],
  /// and response [body].
  ApiException({
    required this.statusCode,
    required this.statusText,
    required this.body,
  });

  /// The HTTP status code returned by the server.
  final int statusCode;

  /// The HTTP reason phrase returned by the server.
  final String statusText;

  /// The raw response body returned by the server.
  final String body;

  @override
  String toString() => '$statusCode $statusText: $body';
}

/// Metadata about a launchable application returned by the API.
class AppInfo {
  /// Creates an [AppInfo] with the given [repo], [tag], and [allTags].
  AppInfo({required this.repo, required this.tag, required this.allTags});

  /// Deserializes an [AppInfo] from a JSON map.
  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      repo: (json['repo'] as String?) ?? '',
      tag: json['tag'] as String?,
      allTags:
          (json['allTags'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// The repository identifier for this app.
  final String repo;

  /// The currently selected tag, or `null` if none is set.
  final String? tag;

  /// All available tags for this app.
  final List<String> allTags;
}

/// Access information for a running launch, including its status and URLs.
class LaunchAccess {
  /// Creates a [LaunchAccess] with the given [status] and [urls].
  LaunchAccess({required this.status, required this.urls});

  /// Deserializes a [LaunchAccess] from a nullable JSON map.
  factory LaunchAccess.fromJson(Map<String, dynamic>? json) {
    final m = json ?? const <String, dynamic>{};
    return LaunchAccess(
      status: (m['status'] as String?) ?? 'Pending',
      urls: (m['urls'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// The access readiness status (e.g. `'Pending'`, `'Ready'`).
  final String status;

  /// The list of URLs through which the app can be reached.
  final List<String> urls;
}

/// The current status of a launch job returned by the API.
class LaunchStatus {
  /// Creates a [LaunchStatus] with the given fields.
  LaunchStatus({
    required this.launchId,
    required this.status,
    required this.access,
    required this.raw,
  });

  /// Deserializes a [LaunchStatus] from a JSON map.
  factory LaunchStatus.fromJson(Map<String, dynamic> json) {
    return LaunchStatus(
      launchId: (json['launchId'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      access: LaunchAccess.fromJson(json['access'] as Map<String, dynamic>?),
      raw: json,
    );
  }

  /// The unique identifier for this launch job.
  final String launchId;

  /// The job status string (e.g. `'Pending'`, `'Running'`, `'Succeeded'`).
  final String status;

  /// Access details for this launch.
  final LaunchAccess access;

  /// The raw JSON map as returned by the server.
  final Map<String, dynamic> raw;
}

/// The response returned when a launch is requested.
class LaunchResponse {
  /// Creates a [LaunchResponse] with the given fields.
  LaunchResponse({
    required this.launchId,
    required this.tag,
    required this.raw,
  });

  /// Deserializes a [LaunchResponse] from a JSON map.
  factory LaunchResponse.fromJson(Map<String, dynamic> json) {
    return LaunchResponse(
      launchId: (json['launchId'] as String?) ?? '',
      tag: json['tag'] as String?,
      raw: json,
    );
  }

  /// The unique identifier assigned to the new launch job.
  final String launchId;

  /// The resolved tag used for this launch, or `null` if not provided.
  final String? tag;

  /// The raw JSON map as returned by the server.
  final Map<String, dynamic> raw;
}

/// Abstract interface for communicating with the AP Python Launcher API.
abstract class ApiService {
  /// Returns the list of available applications.
  Future<List<AppInfo>> getApps();

  /// Requests a launch for the given [repo] and returns the response.
  Future<LaunchResponse> postLaunch(String repo);

  /// Returns the current status of the launch identified by [launchId].
  Future<LaunchStatus> getLaunchStatus(String launchId);

  /// Returns the current statuses for the given [launchIds].
  Future<List<LaunchStatus>> getLaunchStatuses(List<String> launchIds);

  /// Deletes (ends) the launch identified by [launchId].
  Future<Map<String, dynamic>> deleteLaunch(String launchId);
}

/// HTTP implementation of [ApiService] that communicates with the backend.
class HttpApiService implements ApiService {
  /// Creates an [HttpApiService].
  ///
  /// [baseUrl] is the absolute base URL of the API server (e.g.
  /// `'http://localhost:8080'`). All API paths are resolved relative to it.
  /// Defaults to an empty string, which resolves paths relative to the current
  /// document origin — suitable when the Flutter app is served directly from
  /// the FastAPI server at `/`.
  ///
  /// An optional HTTP [client] can be injected for testing.
  HttpApiService({String baseUrl = '', Client? client})
    : _baseUri = Uri.parse(baseUrl.isEmpty ? '' : baseUrl),
      _client = client ?? Client();

  final Uri _baseUri;
  final Client _client;

  Future<Map<String, dynamic>> _fetchJson(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = _baseUri.resolve(path);

    final req = Request(method, uri);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.body = body is String ? body : jsonEncode(body);
    }

    final streamed = await _client.send(req);
    final res = await Response.fromStream(streamed);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        statusCode: res.statusCode,
        statusText: res.reasonPhrase ?? 'Error',
        body: res.body,
      );
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Future<List<AppInfo>> getApps() async {
    final data = await _fetchJson('apps');
    final apps = (data['apps'] as List?) ?? const [];
    return apps
        .whereType<Map<String, dynamic>>()
        .map(AppInfo.fromJson)
        .toList();
  }

  @override
  Future<LaunchResponse> postLaunch(String repo) async {
    final data = await _fetchJson(
      'launch',
      method: 'POST',
      headers: const {'Content-Type': 'application/json'},
      body: {'repo': repo},
    );
    return LaunchResponse.fromJson(data);
  }

  @override
  Future<LaunchStatus> getLaunchStatus(String launchId) async {
    final data = await _fetchJson('launch/$launchId');
    return LaunchStatus.fromJson(data);
  }

  @override
  Future<List<LaunchStatus>> getLaunchStatuses(List<String> launchIds) async {
    final data = await _fetchJson(
      'launch/status',
      method: 'POST',
      headers: const {'Content-Type': 'application/json'},
      body: {'launchIds': launchIds},
    );
    final launches = (data['launches'] as List?) ?? const [];
    return launches
        .whereType<Map<String, dynamic>>()
        .map(LaunchStatus.fromJson)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    return _fetchJson('launch/$launchId', method: 'DELETE');
  }
}
