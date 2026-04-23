import 'dart:async' show Future, unawaited;
import 'dart:convert' show JsonEncoder;

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/job_store.dart' as jobs;
import 'package:frontend/launcher/launcher_models.dart'
    show RowState, RowStateKind;

/// Manages a single active poll loop for one launch job.
///
/// The loop runs until [stop] is called or the job reaches a terminal state.
/// Each iteration awaits the network call before scheduling the next.
class PollSession {
  PollSession._({
    required String launchId,
    required Duration interval,
    required api.ApiService apiService,
    required jobs.JobStore jobStore,
    required void Function(RowState) onRowState,
    required void Function(String) onStatus,
    required void Function(Object) onJson,
  }) : _launchId = launchId,
       _interval = interval,
       _api = apiService,
       _jobs = jobStore,
       _onRowState = onRowState,
       _onStatus = onStatus,
       _onJson = onJson;

  /// Creates a [PollSession] and immediately starts the poll loop.
  factory PollSession.start({
    required String launchId,
    required Duration interval,
    required api.ApiService apiService,
    required jobs.JobStore jobStore,
    required void Function(RowState) onRowState,
    required void Function(String) onStatus,
    required void Function(Object) onJson,
  }) {
    final session = PollSession._(
      launchId: launchId,
      interval: interval,
      apiService: apiService,
      jobStore: jobStore,
      onRowState: onRowState,
      onStatus: onStatus,
      onJson: onJson,
    );
    unawaited(session._run());
    return session;
  }

  final String _launchId;
  final Duration _interval;
  final api.ApiService _api;
  final jobs.JobStore _jobs;
  final void Function(RowState) _onRowState;
  final void Function(String) _onStatus;
  final void Function(Object) _onJson;

  bool _stopped = false;

  /// Stops the poll loop. Any in-flight network call completes but its result
  /// is discarded.
  void stop() {
    _stopped = true;
  }

  Future<void> _run() async {
    while (!_stopped) {
      await Future<void>.delayed(_interval);
      if (_stopped) return;
      await _tick();
    }
  }

  Future<void> _tick() async {
    api.LaunchStatus st;
    try {
      st = await _api.getLaunchStatus(_launchId);
    } on Exception catch (e) {
      if (_stopped) return;
      if (e is api.ApiException && e.statusCode == 404) {
        await _jobs.removeJob(_launchId);
        _onRowState(const RowState(kind: RowStateKind.idle));
      } else {
        await _jobs.removeJob(_launchId);
        _onStatus('Job no longer found; cleared from saved jobs');
        _onRowState(const RowState(kind: RowStateKind.idle));
      }
      stop();
      return;
    }

    if (_stopped) return;

    if (st.status == 'NotFound') {
      await _jobs.removeJob(_launchId);
      _onRowState(const RowState(kind: RowStateKind.idle));
      stop();
      return;
    }

    _onJson(st.raw);

    final urls = st.access.urls;
    final accessStatus = st.access.status;

    if (urls.isNotEmpty && accessStatus == 'Ready') {
      _onStatus('App is reachable: ${urls.join(", ")}');
      _onRowState(
        RowState(
          kind: RowStateKind.ready,
          launchId: _launchId,
          connectUrl: urls.first,
        ),
      );
      stop();
      return;
    }

    if (st.status == 'Succeeded' || st.status == 'Failed') {
      _onStatus('Job ${st.status}; access cleaned up');
      await _jobs.removeJob(_launchId);
      _onRowState(const RowState(kind: RowStateKind.idle));
      stop();
      return;
    }

    final isPending =
        st.status.toLowerCase() == 'pending' ||
        st.access.status.toLowerCase() == 'pending';
    _onRowState(
      RowState(
        kind: isPending ? RowStateKind.pending : RowStateKind.running,
        launchId: _launchId,
      ),
    );
    _onStatus(
      urls.isNotEmpty
          ? 'Waiting for container...'
          : 'Waiting for LoadBalancer...',
    );
  }
}

/// Manages the business logic for the launcher UI.
///
/// Handles refreshing the app list, launching and ending jobs, polling for
/// status updates, and persisting job state across sessions.
class LauncherController {
  /// Creates a [LauncherController].
  ///
  /// Optional [apiService] and [jobStore] can be injected for testing.
  /// [pollInterval] controls how often running jobs are polled.
  /// [endPollInterval] controls how often a terminating job is polled.
  /// [endTimeout] is how long to wait for confirmation before stopping
  /// tracking and returning the row to idle.
  LauncherController({
    api.ApiService? apiService,
    jobs.JobStore? jobStore,
    this.pollInterval = const Duration(seconds: 2),
    this.endPollInterval = const Duration(seconds: 2),
    this.endTimeout = const Duration(seconds: 60),
  }) : _api = apiService ?? api.HttpApiService(),
       _jobs = jobStore ?? jobs.JobStore();
  final api.ApiService _api;
  final jobs.JobStore _jobs;

  /// How often active jobs are polled for status updates.
  final Duration pollInterval;

  /// How often a terminating job is polled while waiting for it to end.
  final Duration endPollInterval;

  /// How long to wait for termination confirmation before stopping tracking
  /// and returning the row to idle.
  final Duration endTimeout;

  /// The current list of available apps, updated by [refresh].
  List<api.AppInfo> apps = const [];

  /// A human-readable status message for display in the UI.
  String statusText = 'Ready';

  /// The pretty-printed JSON of the most recent launch status response.
  String launchJson = 'No new launches';

  final Map<String, RowState> _rowStates = {};
  final Map<String, PollSession> _sessions = {};

  String _key(String repo, String tag) => '$repo:$tag';

  /// Returns the current [RowState] for the given [repo] and [tag].
  RowState rowStateFor(String repo, String tag) {
    return _rowStates[_key(repo, tag)] ??
        const RowState(kind: RowStateKind.idle);
  }

  /// Stops all active poll sessions and releases resources.
  void dispose() {
    for (final s in _sessions.values) {
      s.stop();
    }
    _sessions.clear();
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

  /// Fetches the app list from the API and restores any persisted jobs.
  ///
  /// Calls [notify] after each state change so the UI can rebuild.
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
    } on Exception catch (e) {
      _setStatus('Refresh failed', notify);
      _setLaunchJson({'error': e.toString()}, notify);
    }
  }

  /// Requests a launch for [repo] at [tag] and begins polling for status.
  ///
  /// Calls [notify] after each state change so the UI can rebuild.
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
      _startSession(launchId, repo, resolvedTag, notify);
    } on Exception catch (e) {
      _setLaunchJson({'error': e.toString()}, notify);
      _setStatus('Launch failed', notify);
    }
  }

  /// Sends a termination request for [launchId] and waits for the job to end.
  ///
  /// Calls [notify] after each state change so the UI can rebuild.
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
    } on Exception catch (e) {
      _setStatus('Failed to end job: $e', notify);
      _setRowState(
        repo,
        tag,
        RowState(kind: RowStateKind.running, launchId: launchId),
        notify,
      );
      return;
    }

    await _pollUntilEnded(
      launchId,
      timeout: endTimeout,
      poll: endPollInterval,
      onStatus: (st) => _setLaunchJson(st.raw, notify),
    );

    await _jobs.removeJob(launchId);
    _stopSession(launchId);

    _setStatus('Job ended', notify);
    _setRowState(repo, tag, const RowState(kind: RowStateKind.idle), notify);
  }

  /// Restores persisted jobs against the given [currentTags] map.
  ///
  /// Calls [notify] after each state change so the UI can rebuild.
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
      } on Exception {
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
        _startSession(job.launchId, job.repo, job.tag, notify);
      }
    }
  }

  void _startSession(
    String launchId,
    String repo,
    String tag,
    void Function() notify,
  ) {
    _stopSession(launchId);

    _sessions[launchId] = PollSession.start(
      launchId: launchId,
      interval: pollInterval,
      apiService: _api,
      jobStore: _jobs,
      onRowState: (state) => _setRowState(repo, tag, state, notify),
      onStatus: (text) => _setStatus(text, notify),
      onJson: (obj) => _setLaunchJson(obj, notify),
    );
  }

  void _stopSession(String launchId) {
    _sessions.remove(launchId)?.stop();
  }

  Future<void> _pollUntilEnded(
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
          return;
        }
      } on Exception {
        return;
      }

      await Future<void>.delayed(poll);
    }
  }
}
