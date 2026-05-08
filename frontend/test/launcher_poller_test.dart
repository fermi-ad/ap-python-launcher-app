import 'dart:collection' show Queue;

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/launcher/launcher_models.dart' as models;
import 'package:frontend/launcher/launcher_poller.dart' show LauncherPoller;

import 'fakes.dart' show FakeApiService, FakeJobStore, pumpMicrotasks;

void main() {
  group('LauncherPoller', () {
    test('sets status to Unavailable when batch polling throws', () async {
      final fakeApi = FakeApiService()
        ..launchStatusErrors['id1'] = Exception('boom');

      final jobs = FakeJobStore();
      final rowStates = <String, models.RowState>{};
      final poller = LauncherPoller(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
        onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
        onStatus: (text, notify) {},
      )..startTracking('id1', 'ap-python/foo', 'latest', () {});

      await pumpMicrotasks();

      expect(
        rowStates['ap-python/foo:latest']?.kind,
        models.RowStateKind.statusUnavailable,
      );
      expect(
        rowStates['ap-python/foo:latest']?.statusOverride,
        'Status unavailable',
      );

      poller.dispose();
    });

    test('transitions to ready when url becomes available', () async {
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
      final rowStates = <String, models.RowState>{};
      var statusText = 'Ready';
      final poller = LauncherPoller(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
        onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
        onStatus: (text, _) => statusText = text,
      )..startTracking('id1', 'ap-python/foo', 'latest', () {});

      await pumpMicrotasks();

      final st = rowStates['ap-python/foo:latest'];
      expect(st?.kind, models.RowStateKind.ready);
      expect(st?.connectUrl, 'http://host:80/');
      expect(statusText, contains('App is reachable'));

      poller.dispose();
    });

    test('removes job and sets idle when status is Succeeded', () async {
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
      final rowStates = <String, models.RowState>{};
      final poller = LauncherPoller(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
        onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
        onStatus: (text, notify) {},
      )..startTracking('id1', 'ap-python/foo', 'latest', () {});

      await pumpMicrotasks();

      expect(jobs.jobs, isEmpty);
      expect(
        rowStates['ap-python/foo:latest']?.kind,
        models.RowStateKind.idle,
      );

      poller.dispose();
    });

    test('removes job and sets idle on 404 ApiException', () async {
      final fakeApi = FakeApiService()
        ..launchStatusErrors['id1'] = api.ApiException(
          statusCode: 404,
          statusText: 'Not Found',
          body: '',
        );

      final jobs = FakeJobStore();
      await jobs.saveJob('id1', 'ap-python/foo', 'latest');
      final rowStates = <String, models.RowState>{};
      final poller = LauncherPoller(
        apiService: fakeApi,
        jobStore: jobs,
        pollInterval: Duration.zero,
        onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
        onStatus: (text, notify) {},
      )..startTracking('id1', 'ap-python/foo', 'latest', () {});

      await pumpMicrotasks();

      expect(jobs.jobs, isEmpty);
      expect(
        rowStates['ap-python/foo:latest']?.kind,
        models.RowStateKind.idle,
      );

      poller.dispose();
    });

    test(
      'continues polling after ready and transitions to idle on Succeeded',
      () async {
        final fakeApi = FakeApiService();
        fakeApi.launchStatusQueue['id1'] = Queue.of([
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
            },
          ),
          api.LaunchStatus(
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
          ),
        ]);

        final jobs = FakeJobStore();
        await jobs.saveJob('id1', 'ap-python/foo', 'latest');
        final rowStates = <String, models.RowState>{};
        final poller = LauncherPoller(
          apiService: fakeApi,
          jobStore: jobs,
          pollInterval: Duration.zero,
          onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
          onStatus: (text, notify) {},
        )..startTracking('id1', 'ap-python/foo', 'latest', () {});

        await pumpMicrotasks();

        expect(jobs.jobs, isEmpty);
        expect(
          rowStates['ap-python/foo:latest']?.kind,
          models.RowStateKind.idle,
        );

        poller.dispose();
      },
    );

    test(
      'continues polling after ready and transitions to '
      'running when access is lost',
      () async {
        final runningStatus = api.LaunchStatus(
          launchId: 'id1',
          status: 'Running',
          access: api.LaunchAccess(status: 'Running', urls: const []),
          raw: const <String, dynamic>{
            'status': 'Running',
            'access': <String, dynamic>{
              'status': 'Running',
              'urls': <String>[],
            },
          },
        );
        final fakeApi = FakeApiService()..launchStatuses['id1'] = runningStatus;
        fakeApi.launchStatusQueue['id1'] = Queue.of([
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
            },
          ),
          runningStatus,
        ]);

        final jobs = FakeJobStore();
        final rowStates = <String, models.RowState>{};
        final poller = LauncherPoller(
          apiService: fakeApi,
          jobStore: jobs,
          pollInterval: Duration.zero,
          onRowState: (repo, tag, state) => rowStates['$repo:$tag'] = state,
          onStatus: (text, notify) {},
        )..startTracking('id1', 'ap-python/foo', 'latest', () {});

        await pumpMicrotasks();

        expect(
          rowStates['ap-python/foo:latest']?.kind,
          models.RowStateKind.running,
        );

        poller.dispose();
      },
    );
  });
}
