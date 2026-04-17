import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String statusText;
  final String body;

  ApiException({
    required this.statusCode,
    required this.statusText,
    required this.body,
  });

  @override
  String toString() => '$statusCode $statusText: $body';
}

class AppInfo {
  final String repo;
  final String? tag;
  final List<String> allTags;

  AppInfo({required this.repo, required this.tag, required this.allTags});

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      repo: (json['repo'] as String?) ?? '',
      tag: json['tag'] as String?,
      allTags:
          (json['allTags'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

class LaunchAccess {
  final String status;
  final List<String> urls;

  LaunchAccess({required this.status, required this.urls});

  factory LaunchAccess.fromJson(Map<String, dynamic>? json) {
    final m = json ?? const <String, dynamic>{};
    return LaunchAccess(
      status: (m['status'] as String?) ?? 'Pending',
      urls: (m['urls'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

class LaunchStatus {
  final String launchId;
  final String status;
  final LaunchAccess access;
  final Map<String, dynamic> raw;

  LaunchStatus({
    required this.launchId,
    required this.status,
    required this.access,
    required this.raw,
  });

  factory LaunchStatus.fromJson(Map<String, dynamic> json) {
    return LaunchStatus(
      launchId: (json['launchId'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      access: LaunchAccess.fromJson(json['access'] as Map<String, dynamic>?),
      raw: json,
    );
  }
}

class LaunchResponse {
  final String launchId;
  final String? tag;
  final Map<String, dynamic> raw;

  LaunchResponse({
    required this.launchId,
    required this.tag,
    required this.raw,
  });

  factory LaunchResponse.fromJson(Map<String, dynamic> json) {
    return LaunchResponse(
      launchId: (json['launchId'] as String?) ?? '',
      tag: json['tag'] as String?,
      raw: json,
    );
  }
}

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> _fetchJson(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = Uri.parse(path);

    final req = http.Request(method, uri);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.body = body is String ? body : jsonEncode(body);
    }

    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        statusCode: res.statusCode,
        statusText: res.reasonPhrase ?? 'Error',
        body: res.body,
      );
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<AppInfo>> getApps() async {
    final data = await _fetchJson('apps');
    final apps = (data['apps'] as List?) ?? const [];
    return apps
        .whereType<Map>()
        .map((m) => AppInfo.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<LaunchResponse> postLaunch(String repo) async {
    final data = await _fetchJson(
      'launch',
      method: 'POST',
      headers: const {'Content-Type': 'application/json'},
      body: {'repo': repo},
    );
    return LaunchResponse.fromJson(data);
  }

  Future<LaunchStatus> getLaunchStatus(String launchId) async {
    final data = await _fetchJson('launch/$launchId');
    return LaunchStatus.fromJson(data);
  }

  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    return _fetchJson('launch/$launchId', method: 'DELETE');
  }
}
