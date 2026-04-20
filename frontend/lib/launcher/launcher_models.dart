enum RowStateKind { idle, pending, running, ready, ending }

class RowState {
  final RowStateKind kind;
  final String? launchId;
  final String? connectUrl;

  const RowState({required this.kind, this.launchId, this.connectUrl});

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
