import 'dart:async' show Future;
import 'dart:collection' show Queue;

import 'package:ap_python_launcher_app/api_service.dart'
    show
        ApiException,
        ApiService,
        AppInfo,
        LaunchAccess,
        LaunchResponse,
        LaunchStatus;
import 'package:ap_python_launcher_app/job_store.dart' show JobStore, SavedJob;

class FakeApiService implements ApiService {
  List<AppInfo> apps = const [];

  LaunchResponse launchResponse = LaunchResponse(
    launchId: '',
    tag: null,
    raw: const <String, dynamic>{},
  );

  final Map<String, LaunchStatus> launchStatuses = {};
  final Map<String, Object> launchStatusErrors = {};

  /// Per-launch queues of responses returned in order. When a queue is
  /// non-empty, the next entry is dequeued and returned before the fallback
  /// map is consulted.
  final Map<String, Queue<LaunchStatus>> launchStatusQueue = {};

  final List<String> postLaunchCalls = [];
  final List<String> getLaunchStatusCalls = [];
  final List<String> deleteLaunchCalls = [];

  @override
  Future<List<AppInfo>> getApps() async => apps;

  @override
  Future<LaunchResponse> postLaunch(final String repo) async {
    postLaunchCalls.add(repo);
    return launchResponse;
  }

  @override
  Future<LaunchStatus> getLaunchStatus(final String launchId) async {
    getLaunchStatusCalls.add(launchId);

    final err = launchStatusErrors[launchId];
    if (err != null) {
      if (err is Exception) throw err;
      throw Exception(err.toString());
    }

    final queue = launchStatusQueue[launchId];
    if (queue != null && queue.isNotEmpty) {
      return queue.removeFirst();
    }

    final st = launchStatuses[launchId];
    if (st == null) {
      throw ApiException(statusCode: 404, statusText: 'Not Found', body: '');
    }

    return st;
  }

  @override
  Future<List<LaunchStatus>> getLaunchStatuses(
    final List<String> launchIds,
  ) async {
    final statuses = <LaunchStatus>[];
    for (final launchId in launchIds) {
      try {
        statuses.add(await getLaunchStatus(launchId));
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          statuses.add(
            LaunchStatus(
              launchId: launchId,
              status: 'NotFound',
              access: LaunchAccess(status: 'Pending', urls: const []),
              raw: const <String, dynamic>{'status': 'NotFound'},
            ),
          );
          continue;
        }
        rethrow;
      }
    }
    return statuses;
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(final String launchId) async {
    deleteLaunchCalls.add(launchId);
    return const <String, dynamic>{'ok': true};
  }
}

class FakeJobStore implements JobStore {
  final List<SavedJob> _jobs = [];

  List<SavedJob> get jobs => List.unmodifiable(_jobs);

  @override
  Future<List<SavedJob>> loadJobs() async => List.unmodifiable(_jobs);

  @override
  Future<void> saveJob(
    final String launchId,
    final String repo,
    final String tag,
  ) async {
    _jobs
      ..removeWhere((final j) => j.repo == repo && j.tag == tag)
      ..add(SavedJob(launchId: launchId, repo: repo, tag: tag));
  }

  @override
  Future<void> removeJob(final String launchId) async {
    _jobs.removeWhere((final j) => j.launchId == launchId);
  }
}

class NotifyCounter {
  int count = 0;

  void call() {
    count += 1;
  }
}

Future<void> pumpMicrotasks([final int times = 20]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
