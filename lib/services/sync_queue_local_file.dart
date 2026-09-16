// VM/desktop/test local file helper for queue recovery backups.
import 'dart:io';

Future<void> writeSyncQueueBackupFile(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}
