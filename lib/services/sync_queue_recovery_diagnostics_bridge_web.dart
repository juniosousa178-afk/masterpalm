// lib/services/sync_queue_recovery_diagnostics_bridge_web.dart
// Read-only browser bridge for recovery diagnostics. No mutation APIs.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;

import 'sync_queue_recovery_diagnostics.dart';

const String _bridgeKey = '__mpQueueRecoveryDiagnostics';

void installRecoveryDiagnosticsBridge() {
  try {
    // JsObject.jsify converts Dart Functions via allowInterop internally.
    js.context[_bridgeKey] = js.JsObject.jsify(<String, Object?>{
      'schemaVersion': SyncQueueRecoveryDiagnostics.schemaVersion,
      'readOnly': true,
      'getSnapshot': () {
        return js.JsObject.jsify(
          SyncQueueRecoveryDiagnostics.getRecoveryDiagnosticsSnapshot(),
        );
      },
    });
    // Explicitly do NOT expose processPending / retryItem / processOneById /
    // enqueue / backup / auth / Firestore methods.
  } catch (_) {}
}

void uninstallRecoveryDiagnosticsBridge() {
  try {
    js.context.deleteProperty(_bridgeKey);
  } catch (_) {}
}
