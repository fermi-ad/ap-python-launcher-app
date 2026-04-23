import 'dart:async' show Completer;

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/launcher/launcher_controller.dart'
    show LauncherController;
import 'package:frontend/launcher/launcher_models.dart' as models;

import 'fakes.dart' show FakeApiService, FakeJobStore, NotifyCounter;

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

    test('sets error status on failure', () async {
      final failingApi = _FailingLaunchApiService();
      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(apiService: failingApi, jobStore: jobs);

      await c.launch('ap-python/foo', 'latest', notify.call);

      expect(c.statusText, 'Launch failed');
      expect(c.launchJson, contains('error'));
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

  group('LauncherController polling', () {
    test(
      'transitions to ready and stops polling when url becomes available',
      () async {
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

        await Future<void>.delayed(Duration.zero);

        final st = c.rowStateFor('ap-python/foo', 'latest');
        expect(st.kind, models.RowStateKind.ready);
        expect(st.connectUrl, 'http://host:80/');

        c.dispose();
      },
    );

    test('removes job and sets idle when status is Succeeded', () async {
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
        pollInterval: Duration.zero,
      );

      await c.launch('ap-python/foo', 'latest', notify.call);

      await Future<void>.delayed(Duration.zero);

      expect(jobs.jobs, isEmpty);
      expect(
        c.rowStateFor('ap-python/foo', 'latest').kind,
        models.RowStateKind.idle,
      );

      c.dispose();
    });

    test('removes job and sets idle on 404 ApiException', () async {
      final fakeApi = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: 'id1',
          tag: 'latest',
          raw: const <String, dynamic>{'launchId': 'id1', 'tag': 'latest'},
        )
        ..launchStatusErrors['id1'] = api.ApiException(
          statusCode: 404,
          statusText: 'Not Found',
          body: '',
        );

      final jobs = FakeJobStore();
      final notify = NotifyCounter();
      final c = LauncherController(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
      );

      await c.launch('ap-python/foo', 'latest', notify.call);

      await Future<void>.delayed(Duration.zero);

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
  Future<api.LaunchResponse> postLaunch(String repo) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> deleteLaunch(String launchId) async {
    throw UnimplementedError();
  }
}
