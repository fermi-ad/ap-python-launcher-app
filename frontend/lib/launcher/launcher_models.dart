/// The possible states a launch row can be in.
enum RowStateKind {
  /// No active job for this app.
  idle,

  /// A launch has been requested and is waiting to be scheduled.
  pending,

  /// The job is running but the app is not yet reachable.
  running,

  /// The app is running and reachable via a URL.
  ready,

  /// A termination request has been sent and is in progress.
  ending,
}

/// Holds the UI state for a single app row in the launcher table.
class RowState {
  /// Creates a [RowState] with the given [kind], and optional [launchId] and
  /// [connectUrl].
  const RowState({required this.kind, this.launchId, this.connectUrl});

  /// The current lifecycle state of this row.
  final RowStateKind kind;

  /// The launch job identifier, present when a job is active.
  final String? launchId;

  /// The URL to connect to, present when [kind] is [RowStateKind.ready].
  final String? connectUrl;

  /// Returns a copy of this [RowState] with the given fields replaced.
  RowState copyWith({
    RowStateKind? kind,
    String? launchId,
    String? connectUrl,
  }) {
    return RowState(
      kind: kind ?? this.kind,
      launchId: launchId ?? this.launchId,
      connectUrl: connectUrl ?? this.connectUrl,
    );
  }
}
