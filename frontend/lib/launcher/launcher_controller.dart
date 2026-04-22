import 'dart:async' show Future, Timer;
import 'dart:convert' show JsonEncoder;

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/job_store.dart' as jobs;
import 'package:frontend/launcher/launcher_models.dart'
    show RowState, RowStateKind;

class LauncherController {
  LauncherController({
    api.ApiService? apiService,
    jobs.JobStore? jobStore,
    this.pollInterval = const Duration(seconds: 2),
    this.endPollInterval = const Duration(seconds: 2),
    this.endTimeout = const Duration(seconds: 30),
  }) : _api = apiService ?? api.HttpApiService(),
       _jobs = jobStore ?? jobs.JobStore();
  final api.ApiService _api;
  final jobs.JobStore _jobs;

  final Duration pollInterval;
  final Duration endPollInterval;
  final Duration endTimeout;

  List<api.AppInfo> apps = const [];
  String statusText = 'Ready';
  String launchJson = 'No new launches';

  final Map<String, RowState> _rowStates = {};
  final Map<String, Timer> _pollers = {};

  String _key(String repo, String tag) => '$repo:$tag';

  RowState rowStateFor(String repo, String tag) {
    return _rowStates[_key(repo, tag)] ??
        const RowState(kind: RowStateKind.idle);
  }

  void dispose() {
    for (final t in _pollers.values) {
      t.cancel();
    }
    _pollers.clear();
  }

  void _setStatus(String text, void Function() notify) {
    statusText = text;
    notify();
  }

  void _setLaunchJson(Object obj, void Function() notify) {
    launchJson = const JsonEncoder.withIndent('  ').convert(obj);
    notify();
  }

  void _setRowState(
    String repo,
    String tag,
    RowState state,
    void Function() notify,
  ) {
    _rowStates[_key(repo, tag)] = state;
    notify();
  }

  Future<void> refresh(void Function() notify) async {
    _setStatus('Refreshing...', notify);
    try {
      final loaded = await _api.getApps();
      apps = loaded;

      for (final a in loaded) {
        final tag = a.tag ?? 'latest';
        _rowStates.putIfAbsent(
          _key(a.repo, tag),
          () => const RowState(kind: RowStateKind.idle),
        );
      }

      final currentTags = <String, String>{
        for (final a in loaded) a.repo: (a.tag ?? 'latest'),
      };
      await _restoreJobs(currentTags, notify);

      _setStatus('Loaded ${loaded.length} app(s)', notify);
    } catch (e) {
      _setStatus('Refresh failed', notify);
      _setLaunchJson({'error': e.toString()}, notify);
    }
  }

  Future<void> launch(String repo, String tag, void Function() notify) async {
    _setStatus('Launching $repo...', notify);
    try {
      final resp = await _api.postLaunch(repo);
      _setLaunchJson(resp.raw, notify);
      _setStatus('Launch requested; waiting for LoadBalancer...', notify);

      final launchId = resp.launchId;
      final resolvedTag = resp.tag ?? tag;
      if (launchId.isEmpty) return;

      await _jobs.saveJob(launchId, repo, resolvedTag);
      _setRowState(
        repo,
        resolvedTag,
        RowState(kind: RowStateKind.pending, launchId: launchId),
        notify,
      );
      _startPolling(launchId, repo, resolvedTag, notify);
    } catch (e) {
      _setLaunchJson({'error': e.toString()}, notify);
      _setStatus('Launch failed', notify);
    }
  }

  Future<void> end(
    String launchId,
    String repo,
    String tag,
    void Function() notify,
  ) async {
    _setStatus('Ending job...', notify);
    _setRowState(
      repo,
      tag,
      RowState(kind: RowStateKind.ending, launchId: launchId),
      notify,
    );

    try {
      await _api.deleteLaunch(launchId);
    } catch (e) {
      _setStatus('Failed to end job: $e', notify);
      _setRowState(
        repo,
        tag,
        RowState(kind: RowStateKind.running, launchId: launchId),
        notify,
      );
      return;
    }

    final ended = await _pollUntilEnded(
      launchId,
      timeout: endTimeout,
      poll: endPollInterval,
      onStatus: (st) => _setLaunchJson(st.raw, notify),
    );

    await _jobs.removeJob(launchId);
    _stopPolling(launchId);

    if (ended) {
      _setStatus('Job ended', notify);
    } else {
      _setStatus('End requested; still terminating...', notify);
    }

    _setRowState(repo, tag, const RowState(kind: RowStateKind.idle), notify);
  }

  Future<void> restoreJobs(
    Map<String, String> currentTags,
    void Function() notify,
  ) async {
    await _restoreJobs(currentTags, notify);
  }

  Future<void> _restoreJobs(
    Map<String, String> currentTags,
    void Function() notify,
  ) async {
    final saved = await _jobs.loadJobs();

    for (final job in saved) {
      if (currentTags.containsKey(job.repo) &&
          currentTags[job.repo] != job.tag) {
        await _jobs.removeJob(job.launchId);
        continue;
      }

      api.LaunchStatus st;
      try {
        st = await _api.getLaunchStatus(job.launchId);
      } catch (_) {
        await _jobs.removeJob(job.launchId);
        continue;
      }

      final urls = st.access.urls;
      final accessStatus = st.access.status;

      if (urls.isNotEmpty && accessStatus == 'Ready') {
        _setRowState(
          job.repo,
          job.tag,
          RowState(
            kind: RowStateKind.ready,
            launchId: job.launchId,
            connectUrl: urls.first,
          ),
          notify,
        );
      } else if (st.status == 'Succeeded' || st.status == 'Failed') {
        await _jobs.removeJob(job.launchId);
        _setRowState(
          job.repo,
          job.tag,
          const RowState(kind: RowStateKind.idle),
          notify,
        );
      } else {
        _setRowState(
          job.repo,
          job.tag,
          RowState(kind: RowStateKind.running, launchId: job.launchId),
          notify,
        );
        _startPolling(job.launchId, job.repo, job.tag, notify);
      }
    }
  }

  void _startPolling(
    String launchId,
    String repo,
    String tag,
    void Function() notify,
  ) {
    _stopPolling(launchId);

    _pollers[launchId] = Timer.periodic(pollInterval, (_) async {
      final saved = await _jobs.loadJobs();
      if (!saved.any((j) => j.launchId == launchId)) {
        _stopPolling(launchId);
        return;
      }

      api.LaunchStatus st;
      try {
        st = await _api.getLaunchStatus(launchId);
      } catch (e) {
        if (e is api.ApiException && e.statusCode == 404) {
          await _jobs.removeJob(launchId);
          _setRowState(
            repo,
            tag,
            const RowState(kind: RowStateKind.idle),
            notify,
          );
          _stopPolling(launchId);
          return;
        }

        await _jobs.removeJob(launchId);
        _setStatus('Job no longer found; cleared from saved jobs', notify);
        _setRowState(
          repo,
          tag,
          const RowState(kind: RowStateKind.idle),
          notify,
        );
        _stopPolling(launchId);
        return;
      }

      if (st.status == 'NotFound') {
        await _jobs.removeJob(launchId);
        _setRowState(
          repo,
          tag,
          const RowState(kind: RowStateKind.idle),
          notify,
        );
        _stopPolling(launchId);
        return;
      }

      _setLaunchJson(st.raw, notify);

      final urls = st.access.urls;
      final accessStatus = st.access.status;

      if (urls.isNotEmpty && accessStatus == 'Ready') {
        _setStatus('App is reachable: ${urls.join(", ")}', notify);
        _setRowState(
          repo,
          tag,
          RowState(
            kind: RowStateKind.ready,
            launchId: launchId,
            connectUrl: urls.first,
          ),
          notify,
        );
        _stopPolling(launchId);
        return;
      }

      if (st.status == 'Succeeded' || st.status == 'Failed') {
        _setStatus('Job ${st.status}; access cleaned up', notify);
        await _jobs.removeJob(launchId);
        _setRowState(
          repo,
          tag,
          const RowState(kind: RowStateKind.idle),
          notify,
        );
        _stopPolling(launchId);
        return;
      }

      final pending = _isPendingStatus(st);
      _setRowState(
        repo,
        tag,
        RowState(
          kind: pending ? RowStateKind.pending : RowStateKind.running,
          launchId: launchId,
        ),
        notify,
      );

      _setStatus('Waiting for LoadBalancer...', notify);
    });
  }

  void _stopPolling(String launchId) {
    _pollers.remove(launchId)?.cancel();
  }

  bool _isPendingStatus(api.LaunchStatus st) {
    final status = st.status.toLowerCase();
    final accessStatus = st.access.status.toLowerCase();
    return status == 'pending' || accessStatus == 'pending';
  }

  Future<bool> _pollUntilEnded(
    String launchId, {
    required Duration timeout,
    required Duration poll,
    required void Function(api.LaunchStatus st) onStatus,
  }) async {
    final start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      try {
        final st = await _api.getLaunchStatus(launchId);
        onStatus(st);
        if (st.status == 'NotFound' ||
            st.status == 'Succeeded' ||
            st.status == 'Failed') {
          return true;
        }
      } catch (_) {
        return true;
      }

      await Future<void>.delayed(poll);
    }

    return false;
  }
}
