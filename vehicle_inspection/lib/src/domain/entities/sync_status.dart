/// Where a locally-created record stands in its journey to the backend.
enum SyncStatus {
  /// Draft that has not been submitted yet, so it is not queued for upload.
  draftLocal('local', 'Local draft'),

  /// Queued and waiting for connectivity or its next retry window.
  pending('pending', 'Pending sync'),

  /// Currently being uploaded.
  syncing('syncing', 'Uploading'),

  /// Accepted by the backend.
  synced('synced', 'Synced'),

  /// Upload failed and the retry budget is exhausted; needs manual retry.
  failed('failed', 'Sync failed');

  const SyncStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static SyncStatus fromWire(String? value) {
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return draftLocal;
  }

  /// Records the sync engine should attempt to push.
  bool get isQueued => this == pending || this == syncing;

  /// Anything the dashboard counts as "not yet on the server".
  bool get isUnsynced => this != synced;
}
