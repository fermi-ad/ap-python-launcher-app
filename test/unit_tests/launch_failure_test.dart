import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode;

import 'package:ap_python_launcher_app/api_service.dart' as api;
import 'package:ap_python_launcher_app/launcher/controller.dart'
    show LauncherController;
import 'package:ap_python_launcher_app/launcher/models.dart' show RowStateKind;
import 'package:ap_python_launcher_app/launcher/poller.dart'
    show LauncherPoller;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart' show MockClient;

import 'fakes.dart' show FakeApiService, FakeJobStore, pumpMicrotasks;

const _repo = 'ap-python/foo';
const _id = 'opaque-launch-20261021t211142123456';

api.LaunchStatus _failed({
  String? code,
  String message = 'Storage unavailable. Contact the administrator.',
  String status = 'Failed',
  String accessStatus = 'Failed',
}) => api.LaunchStatus.fromJson({
  'launchId': _id,
  'status': status,
  'access': {'status': accessStatus, 'url': 'http://stale-url/'},
  if (code != null) 'failure': {'code': code, 'message': message},
});

void main() {
  for (final code in [
    'StorageCollision',
    'StorageInitializationFailed',
    'FutureFailureCode',
    null,
  ]) {
    test('single and batch HTTP responses accept failure $code', () async {
      final status = _failed(code: code);
      final client = MockClient((request) async {
        return Response(
          jsonEncode(
            request.url.path == '/launch/status'
                ? {
                    'launches': [status.raw],
                  }
                : status.raw,
          ),
          200,
        );
      });
      addTearDown(client.close);
      final service = api.HttpApiService(
        baseUrl: 'http://launcher/',
        client: client,
      );
      final single = await service.getLaunchStatus(_id);
      final batch = await service.getLaunchStatuses([_id]);
      for (final result in [single, batch.single]) {
        expect(result.launchId, _id);
        expect(result.isFailed, isTrue);
        expect(result.failure?.code, code);
        expect(result.raw, status.raw);
        expect(result.failureMessage, isNotEmpty);
      }
    });

    test(
      'polling failure $code stops tracking and notifies failed state',
      () async {
        final fake = FakeApiService()
          ..launchStatuses[_id] = _failed(code: code);
        final jobs = FakeJobStore();
        await jobs.saveJob(_id, _repo, 'latest');
        RowStateKind? kind;
        String? diagnostic;
        var notifiedFailed = false;
        final poller = LauncherPoller(
          apiService: fake,
          jobStore: jobs,
          pollInterval: const Duration(milliseconds: 1),
          onRowState: (repo, tag, state) => kind = state.kind,
          onStatus: (text, notify) => notify(),
          onFailure: (repo, message, notify) {
            diagnostic = message;
            notify();
          },
        );
        addTearDown(poller.dispose);
        poller.startTracking(_id, _repo, 'latest', () {
          notifiedFailed = kind == RowStateKind.failed;
        });
        await pumpMicrotasks();
        expect(kind, RowStateKind.failed);
        expect(notifiedFailed, isTrue);
        expect(diagnostic, _failed(code: code).failureMessage);
        expect(jobs.jobs, isEmpty);
        expect(fake.getLaunchStatusCalls, [_id]);
      },
    );

    test('restored failure $code remains visible after Refresh', () async {
      final fake = FakeApiService()
        ..apps = [api.AppInfo(repo: _repo, tag: 'latest', allTags: const [])]
        ..launchStatuses[_id] = _failed(code: code);
      final jobs = FakeJobStore();
      await jobs.saveJob(_id, _repo, 'latest');
      final controller = LauncherController(apiService: fake, jobStore: jobs);
      addTearDown(controller.dispose);
      await controller.refresh(() {});
      final error = controller.launchError;
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
      expect(error, '$_repo: ${_failed(code: code).failureMessage}');
      expect(jobs.jobs, isEmpty);
      await controller.refresh(() {});
      expect(controller.launchError, error);
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
      expect(fake.getLaunchStatusCalls, [_id]);
    });
  }

  test('failure without details and blank message has a fallback', () {
    expect(_failed().failure, isNull);
    expect(
      _failed(code: 'StorageCollision', message: ' ').failureMessage,
      _failed().failureMessage,
    );
    expect(api.LaunchStatus.fromJson({'status': 'Pending'}).isFailed, isFalse);
  });

  for (final status in [400, 409, 503]) {
    test(
      'HTTP $status performs one request and preserves server detail',
      () async {
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          return Response(
            '{"detail":"Launch rejected by the service"}',
            status,
          );
        });
        addTearDown(client.close);
        final controller = LauncherController(
          apiService: api.HttpApiService(
            baseUrl: 'http://launcher/',
            client: client,
          ),
          jobStore: FakeJobStore(),
        );
        addTearDown(controller.dispose);
        await controller.launch(_repo, 'latest', () {});
        expect(requests, 1);
        expect(
          controller.launchError,
          '$_repo: Launch rejected by the service',
        );
        expect(
          controller.rowStateFor(_repo, 'latest').kind,
          RowStateKind.failed,
        );
      },
    );
  }

  test(
    'latest error replaces older errors and clears at launch start',
    () async {
      final fake = _DelayedLaunchApi()
        ..postLaunchError = Exception('first failure');
      final controller = LauncherController(
        apiService: fake,
        jobStore: FakeJobStore(),
      );
      addTearDown(controller.dispose);
      await controller.launch(_repo, 'latest', () {});
      expect(controller.launchError, contains('first failure'));
      fake.postLaunchError = Exception('second failure');
      await controller.launch('ap-python/bar', 'latest', () {});
      expect(
        controller.launchError,
        'ap-python/bar: Exception: second failure',
      );
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
      fake
        ..postLaunchError = null
        ..response = Completer<api.LaunchResponse>();
      final launch = controller.launch('ap-python/bar', 'latest', () {});
      expect(controller.launchError, isNull);
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
      fake.response!.complete(
        api.LaunchResponse(launchId: _id, tag: 'latest', raw: const {}),
      );
      fake.launchStatuses[_id] = api.LaunchStatus.fromJson({
        'launchId': _id,
        'status': 'Running',
        'access': {'status': 'Pending'},
      });
      await launch;
      await pumpMicrotasks();
      expect(controller.launchError, isNull);
    },
  );

  test(
    'ready-to-failed polling retains error during unrelated updates',
    () async {
      final fake = FakeApiService()
        ..launchResponse = api.LaunchResponse(
          launchId: _id,
          tag: 'latest',
          raw: const {},
        )
        ..launchStatuses[_id] = api.LaunchStatus.fromJson({
          'launchId': _id,
          'status': 'Running',
          'access': {'status': 'Ready', 'url': 'http://ready/'},
        });
      final jobs = FakeJobStore();
      final controller = LauncherController(
        apiService: fake,
        jobStore: jobs,
        pollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(controller.dispose);
      await controller.launch(_repo, 'latest', () {});
      await pumpMicrotasks();
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.ready);
      fake.launchStatuses[_id] = _failed(
        code: 'StorageCollision',
        status: 'Running',
      );
      await pumpMicrotasks();
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
      expect(controller.rowStateFor(_repo, 'latest').connectUrl, isNull);
      final error = controller.launchError;
      expect(error, isNotNull);
      await jobs.saveJob('another-id', 'ap-python/bar', 'latest');
      fake.launchStatuses['another-id'] = api.LaunchStatus.fromJson({
        'launchId': 'another-id',
        'status': 'Running',
        'access': {'status': 'Ready', 'url': 'http://other/'},
      });
      await controller.restoreJobs({'ap-python/bar': 'latest'}, () {});
      await pumpMicrotasks();
      expect(controller.launchError, error);
      expect(controller.rowStateFor(_repo, 'latest').kind, RowStateKind.failed);
    },
  );
}

class _DelayedLaunchApi extends FakeApiService {
  Completer<api.LaunchResponse>? response;

  @override
  Future<api.LaunchResponse> postLaunch(String repo) {
    final pending = response;
    return pending == null ? super.postLaunch(repo) : pending.future;
  }
}
