/// The possible states a launch row can be in.
enum RowStateKind {
  /// No active job for this app.
  idle,

  /// A saved launch ID was found on startup and its status is being verified
  /// with the backend.
  checking,

  /// A launch has been requested and is waiting to be scheduled.
  pending,

  /// The job is running but the app is not yet reachable.
  running,

  /// The app is running and reachable via a URL.
  ready,

  /// A termination request has been sent and is in progress.
  ending,

  /// The job is active, but status updates could not be fetched.
  statusUnavailable,
}

/// Holds the UI state for a single app row in the launcher table.
class RowState {
  /// Creates a [RowState] with the given [kind], and optional [launchId],
  /// [connectUrl], and [statusOverride].
  const RowState({
    required this.kind,
    this.launchId,
    this.connectUrl,
    this.statusOverride,
  });

  /// The current lifecycle state of this row.
  final RowStateKind kind;

  /// The launch job identifier, present when a job is active.
  final String? launchId;

  /// The URL to connect to, present when [kind] is [RowStateKind.ready].
  final String? connectUrl;

  /// Optional text to display in the Status column instead of the default
  /// label.
  final String? statusOverride;

  /// Returns a copy of this [RowState] with the given fields replaced.
  RowState copyWith({
    final RowStateKind? kind,
    final String? launchId,
    final String? connectUrl,
    final String? statusOverride,
  }) {
    return RowState(
      kind: kind ?? this.kind,
      launchId: launchId ?? this.launchId,
      connectUrl: connectUrl ?? this.connectUrl,
      statusOverride: statusOverride ?? this.statusOverride,
    );
  }
}
