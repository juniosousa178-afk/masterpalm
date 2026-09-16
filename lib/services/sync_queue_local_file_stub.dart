// Web stub — raw queue backup stays in-memory via exportRawBackupBundle.
Future<void> writeSyncQueueBackupFile(String path, List<int> bytes) async {
  throw UnsupportedError(
    'Local file queue backup is not available on web; use exportRawBackupBundle()',
  );
}
