import 'dart:async' show Future, Timer, unawaited;

import 'package:frontend/api_service.dart' as api;
import 'package:frontend/job_store.dart' as jobs;
import 'package:frontend/launcher/launcher_models.dart'
    show RowState, RowStateKind;

/// Coordinates steady-state batch polling for tracked launch jobs.
class LauncherPoller {
  /// Creates a [LauncherPoller].
  LauncherPoller({
    required api.ApiService apiService,
    required jobs.JobStore jobStore,
    required Duration pollInterval,
    required void Function(String repo, String tag, RowState state) onRowState,
    required void Function(String text, void Function() notify) onStatus,
    void Function(api.LaunchStatus st, void Function() notify)? onLaunchJson,
  }) : _api = apiService,
       _jobs = jobStore,
       _pollInterval = pollInterval,
       _onRowState = onRowState,
       _onStatus = onStatus,
       _onLaunchJson = onLaunchJson;

  final api.ApiService _api;
  final jobs.JobStore _jobs;
  final Duration _pollInterval;
  final void Function(String repo, String tag, RowState state) _onRowState;
  final void Function(String text, void Function() notify) _onStatus;
  final void Function(api.LaunchStatus st, void Function() notify)?
  _onLaunchJson;

  final Map<String, _TrackedJob> _trackedJobs = {};

  Timer? _pollTimer;
  bool _pollInFlight = false;

  /// Stops all polling and forgets all tracked jobs.
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _trackedJobs.clear();
  }

  /// Starts tracking the given [launchId] for the app identified by [repo]
  /// and [tag].
  void startTracking(
    String launchId,
    String repo,
    String tag,
    void Function() notify, {
    bool updateLaunchJson = false,
  }) {
    _trackedJobs[launchId] = _TrackedJob(
      repo: repo,
      tag: tag,
      notify: notify,
      updateLaunchJson: updateLaunchJson,
    );
    _ensurePollTimer();
  }

  /// Stops tracking the given [launchId].
  void stopTracking(String launchId) {
    _trackedJobs.remove(launchId);
    if (_trackedJobs.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _ensurePollTimer() {
    if (_pollTimer != null) return;

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollTrackedJobs());
    });

    unawaited(_pollTrackedJobs());
  }

  Future<void> _pollTrackedJobs() async {
    if (_pollInFlight || _trackedJobs.isEmpty) return;
    _pollInFlight = true;

    final entries = _trackedJobs.entries.toList(growable: false);
    final launchIds = entries.map((entry) => entry.key).toList(growable: false);

    try {
      final statuses = await _api.getLaunchStatuses(launchIds);
      final statusesByLaunchId = <String, api.LaunchStatus>{
        for (final status in statuses) status.launchId: status,
      };

      for (final entry in entries) {
        final launchId = entry.key;
        final tracked = entry.value;
        final status = statusesByLaunchId[launchId];
        if (status == null) {
          await _jobs.removeJob(launchId);
          _onRowState(
            tracked.repo,
            tracked.tag,
            const RowState(kind: RowStateKind.idle),
          );
          stopTracking(launchId);
          continue;
        }

        await _applyPolledStatus(launchId, tracked, status);
      }
    } on Exception {
      for (final entry in entries) {
        final tracked = entry.value;
        _onRowState(
          tracked.repo,
          tracked.tag,
          const RowState(
            kind: RowStateKind.statusUnavailable,
            statusOverride: 'Status unavailable',
          ),
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _applyPolledStatus(
    String launchId,
    _TrackedJob tracked,
    api.LaunchStatus st,
  ) async {
    if (st.status == 'NotFound') {
      await _jobs.removeJob(launchId);
      _onRowState(
        tracked.repo,
        tracked.tag,
        const RowState(kind: RowStateKind.idle),
      );
      stopTracking(launchId);
      return;
    }

    if (tracked.updateLaunchJson) {
      _onLaunchJson?.call(st, tracked.notify);
    }

    final urls = st.access.urls;
    final accessStatus = st.access.status;

    if (urls.isNotEmpty && accessStatus == 'Ready') {
      _onStatus('App is reachable: ${urls.join(", ")}', tracked.notify);
      _onRowState(
        tracked.repo,
        tracked.tag,
        RowState(
          kind: RowStateKind.ready,
          launchId: launchId,
          connectUrl: urls.first,
        ),
      );
      tracked.updateLaunchJson = false;
      return;
    }

    if (st.status == 'Succeeded' || st.status == 'Failed') {
      _onStatus('Job ${st.status}; access cleaned up', tracked.notify);
      await _jobs.removeJob(launchId);
      _onRowState(
        tracked.repo,
        tracked.tag,
        const RowState(kind: RowStateKind.idle),
      );
      stopTracking(launchId);
      return;
    }

    final isPending =
        st.status.toLowerCase() == 'pending' ||
        st.access.status.toLowerCase() == 'pending';
    _onRowState(
      tracked.repo,
      tracked.tag,
      RowState(
        kind: isPending ? RowStateKind.pending : RowStateKind.running,
        launchId: launchId,
      ),
    );
    _onStatus('Waiting for container...', tracked.notify);
  }
}

class _TrackedJob {
  _TrackedJob({
    required this.repo,
    required this.tag,
    required this.notify,
    required this.updateLaunchJson,
  });

  final String repo;
  final String tag;
  final void Function() notify;
  bool updateLaunchJson;
}
