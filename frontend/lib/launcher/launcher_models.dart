enum RowStateKind { idle, pending, running, ready, ending }

class RowState {
  const RowState({required this.kind, this.launchId, this.connectUrl});
  final RowStateKind kind;
  final String? launchId;
  final String? connectUrl;

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
