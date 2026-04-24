import 'dart:async' show Completer;
import 'dart:collection' show Queue;

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/launcher/launcher_controller.dart'
    show LauncherController;
import 'package:frontend/launcher/launcher_models.dart' as models;

import 'fakes.dart'
    show FakeApiService, FakeJobStore, NotifyCounter, pumpMicrotasks;

void main() {
  group('LauncherController.refresh', () {
    test('loads apps and sets status', () async {
      final fakeApi = FakeApiService()
        ..apps = [
          api.AppInfo(repo: 'ap-python/foo', tag: 'latest', allTags: const []),
          api.AppInfo(repo: 'ap-python/bar', tag: null, allTags: const []),
        ];
      final jobs = FakeJobStore();
      final notify = NotifyCounter();

      final c = LauncherController(apiService: fakeApi, jobStore: jobs);
      await c.refresh(notify.call);

      expect(c.apps.length, 2);
      expect(c.statusText, 'Loaded 2 app(s)');
      expect(notify.count, greaterThan(0));

      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.idle,
      );
      expect(
        c.rowStateFor('ap-python/bar', 'latest').kind,
        models.RowStateKind.idle,
      );
    });

    test('sets error status and launchJson on failure', () async {
      final fakeApi = FakeApiService();
      fakeApi.launchStatusErrors['__apps__'] = Exception('boom');

      final failingApi = _FailingAppsApiService();
      final jobs = FakeJobStore();
      final notify = NotifyCounter();

      final c = LauncherController(apiService: failingApi, jobStore: jobs);
      await c.refresh(notify.call);

      expect(c.statusText, 'Refresh failed');
      expect(c.launchJson, contains('error'));
    });
  });

  group('LauncherController.launch', () {
    test('saves job, sets pending row state, and starts polling', () async {
      final fakeApi = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: 'id1',
          tag: 'latest',
          raw: const <String, dynamic>{'launchId': 'id1', 'tag': 'latest'},
        )
        ..launchStatuses['id1'] = api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(status: 'Pending', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Pending',
              'urls': <String>[],
            },
          },
        );

      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.launch('ap-python/foo', 'latest', notify.call);

      expect(jobs.jobs.single.launchId, 'id1');
      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.pending,
      );

      c.dispose();
    });

    test('notifies during background polling updates', () async {
      final fakeApi = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: 'id1',
          tag: 'latest',
          raw: const <String, dynamic>{'launchId': 'id1', 'tag': 'latest'},
        )
        ..launchStatuses['id1'] = api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(
            status: 'Ready',
            urls: const ['http://host:80/'],
          ),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Ready',
              'urls': <String>['http://host:80/'],
            },
          },
        );

      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
      );

      await c.launch('ap-python/foo', 'latest', notify.call);
      final notifyBeforePolling = notify.count;

      await pumpMicrotasks();

      expect(notify.count, greaterThan(notifyBeforePolling));
      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.ready,
      );
      expect(c.statusText, contains('App is reachable'));

      c.dispose();
    });

    test('sets error status on failure', () async {
      final failingApi = _FailingLaunchApiService();
      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(apiService: failingApi, jobStore: jobs);

      await c.launch('ap-python/foo', 'latest', notify.call);

      expect(c.statusText, 'Launch failed');
      expect(c.launchJson, contains('error'));
    });

    test('updates launchJson during polling until ready', () async {
      final fakeApi = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: 'id1',
          tag: 'latest',
          raw: const <String, dynamic>{
            'launchId': 'id1',
            'tag': 'latest',
            'source': 'launch-response',
          },
        );
      fakeApi.launchStatusQueue['id1'] = Queue.of([
        api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(status: 'Running', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Running',
              'urls': <String>[],
            },
            'source': 'poll-status-1',
          },
        ),
        api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(
            status: 'Ready',
            urls: const ['http://host:80/'],
          ),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Ready',
              'urls': <String>['http://host:80/'],
            },
            'source': 'poll-status-2',
          },
        ),
      ]);

      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
      );

      await c.launch('ap-python/foo', 'latest', notify.call);
      expect(c.launchJson, contains('launch-response'));

      await pumpMicrotasks();

      expect(c.launchJson, contains('poll-status-2'));

      final launchJsonAfterReady = c.launchJson;
      await pumpMicrotasks();
      expect(c.launchJson, launchJsonAfterReady);

      c.dispose();
    });
  });

  group('LauncherController.restoreJobs', () {
    test('sets checking state before status is known', () async {
      final completer = Completer<api.LaunchStatus>();
      final checkingApi = _SuspendingStatusApiService(completer.future);

      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'latest');

      final notify = NotifyCounter();
      final c = LauncherController(apiService: checkingApi, jobStore: jobs);

      final restoreFuture = c.restoreJobs(
        const {'ap-python/foo': 'latest'},
        notify.call,
      );

      await Future<void>.microtask(() {});

      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.checking,
      );

      completer.complete(
        api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(status: 'Pending', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Pending',
              'urls': <String>[],
            },
          },
        ),
      );
      await restoreFuture;

      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.running,
      );

      c.dispose();
    });

    test('does nothing when no saved jobs', () async {
      final fakeApi = FakeApiService();
      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.restoreJobs(const {'ap-python/foo': 'latest'}, notify.call);

      expect(fakeApi.getLaunchStatusCalls, isEmpty);
    });

    test('removes job when tag no longer matches currentTags', () async {
      final fakeApi = FakeApiService();
      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'old');

      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.restoreJobs(const {'ap-python/foo': 'latest'}, notify.call);

      expect(jobs.jobs, isEmpty);
    });

    test('sets ready state when access is Ready with urls', () async {
      final fakeApi = FakeApiService()
        ..launchStatuses['id1'] = api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(
            status: 'Ready',
            urls: const ['http://host:80/'],
          ),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Ready',
              'urls': <String>['http://host:80/'],
            },
          },
        );

      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'latest');

      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.restoreJobs(const {'ap-python/foo': 'latest'}, notify.call);

      final st = c.rowStateFor('ap-python/foo', 'latest');
      expect(st.kind, models.RowStateKind.ready);
      expect(st.connectUrl, 'http://host:80/');
    });

    test('removes Succeeded job on restore', () async {
      final fakeApi = FakeApiService()
        ..launchStatuses['id1'] = api.LaunchStatus(
          launchId: 'id1',
          status: 'Succeeded',
          access: api.LaunchAccess(status: 'Pending', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Succeeded',
            'access': <String, dynamic>{
              'status': 'Pending',
              'urls': <String>[],
            },
          },
        );

      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'latest');

      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.restoreJobs(const {'ap-python/foo': 'latest'}, notify.call);

      expect(jobs.jobs, isEmpty);
      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.idle,
      );
    });

    test('removes job on fetch error during restore', () async {
      final fakeApi = FakeApiService()
        ..launchStatusErrors['id1'] = Exception('gone');

      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'latest');

      final notify = NotifyCounter();
      final c = LauncherController(apiService: fakeApi, jobStore: jobs);

      await c.restoreJobs(const {'ap-python/foo': 'latest'}, notify.call);

      expect(jobs.jobs, isEmpty);
    });
  });

  group('LauncherController.end', () {
    test('stops background polling before end polling begins', () async {
      final fakeApi = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: 'id1',
          tag: 'latest',
          raw: const <String, dynamic>{'launchId': 'id1', 'tag': 'latest'},
        )
        ..launchStatuses['id1'] = api.LaunchStatus(
          launchId: 'id1',
          status: 'Succeeded',
          access: api.LaunchAccess(status: 'Pending', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Succeeded',
            'access': <String, dynamic>{
              'status': 'Pending',
              'urls': <String>[],
            },
          },
        );

      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: const Duration(days: 1),
        endPollInterval: Duration.zero,
      );

      await c.launch('ap-python/foo', 'latest', notify.call);
      expect(fakeApi.getLaunchStatusCalls, ['id1']);

      await c.end('id1', 'ap-python/foo', 'latest', notify.call);

      expect(fakeApi.deleteLaunchCalls, ['id1']);
      expect(fakeApi.getLaunchStatusCalls, ['id1', 'id1']);
      expect(jobs.jobs, isEmpty);
      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.idle,
      );

      c.dispose();
    });
  });
}

class _FailingAppsApiService implements api.ApiService {
  @override
  Future<List<api.AppInfo>> getApps() async {
    throw Exception('boom');
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    throw UnimplementedError();
  }

  @override
  Future<api.LaunchStatus> getLaunchStatus(String launchId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<api.LaunchStatus>> getLaunchStatuses(
    List<String> launchIds,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<api.LaunchResponse> postLaunch(String repo) async {
    throw UnimplementedError();
  }
}

class _FailingLaunchApiService implements api.ApiService {
  @override
  Future<List<api.AppInfo>> getApps() async => const [];

  @override
  Future<api.LaunchResponse> postLaunch(String repo) async {
    throw Exception('boom');
  }

  @override
  Future<api.LaunchStatus> getLaunchStatus(String launchId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<api.LaunchStatus>> getLaunchStatuses(
    List<String> launchIds,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    throw UnimplementedError();
  }
}

class _SuspendingStatusApiService implements api.ApiService {
  _SuspendingStatusApiService(this._statusFuture);

  final Future<api.LaunchStatus> _statusFuture;

  @override
  Future<List<api.AppInfo>> getApps() async => const [];

  @override
  Future<api.LaunchStatus> getLaunchStatus(String launchId) => _statusFuture;

  @override
  Future<List<api.LaunchStatus>> getLaunchStatuses(
    List<String> launchIds,
  ) async {
    return Future.wait(launchIds.map(getLaunchStatus));
  }

  @override
  Future<api.LaunchResponse> postLaunch(String repo) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    throw UnimplementedError();
  }
}
