// Recovery-mode runtime observability (local patch).
// Counters/flags only — no PII / payload exposure.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/auto_sync_service.dart';
import 'package:master_palm/services/sync_queue_recovery_diagnostics.dart';
import 'package:master_palm/services/sync_queue_recovery_mode.dart';
import 'package:master_palm/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String hivePath;

  setUpAll(() async {
    final dir =
        await Directory.systemTemp.createTemp('hive_queue_recovery_obs_');
    hivePath = dir.path;
    Hive.init(hivePath);
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SyncQueueRecoveryMode.resetForTests();
    SyncQueueService.debugOneItemExecuteHook = null;
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    SyncQueueRecoveryMode.resetForTests();
    SyncQueueService.debugOneItemExecuteHook = null;
    await SyncQueueService.clearQueue();
  });

  Future<String> seedItem() async {
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertCliente,
      lojaId: 'loja-obs',
      boxName: 'box_loja-obs',
      entityKey: 1,
      scheduleProcess: false,
    );
    final list = await SyncQueueService.listQueueMetadata(storeId: 'loja-obs');
    return list.first.queueItemId;
  }

  group('observability normal mode', () {
    test('OBSERVABILITY_NORMAL_MODE_TEST', () async {
      expect(SyncQueueRecoveryMode.isActive, isFalse);
      final snap = SyncQueueRecoveryDiagnostics.getRecoveryDiagnosticsSnapshot();
      expect(snap['recoveryModeActive'], isFalse);
      expect(snap['bootstrapAutosyncSuppressedCount'], 0);
      await seedItem();
      final r = await SyncQueueService.processPending(scopeLojaId: 'loja-obs');
      expect(r.blockedByRecoveryMode, isFalse);
      expect(SyncQueueRecoveryDiagnostics.processPendingBlockedCount, 0);
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 0);
    });
  });

  group('observability recovery', () {
    test('PRE_BOOTSTRAP_ORDER_TEST', () {
      SyncQueueRecoveryMode.resolveFromUri(
        Uri.parse('https://app.mastepalm.com.br/?mpQueueRecovery=1'),
      );
      expect(SyncQueueRecoveryDiagnostics.recoveryModeResolved, isTrue);
      SyncQueueRecoveryDiagnostics.noteBootstrapAutosyncSuppressed();
      expect(
        SyncQueueRecoveryDiagnostics.recoveryResolvedBeforeBootstrap,
        isTrue,
      );
      final trace = SyncQueueRecoveryDiagnostics.eventTrace;
      expect(trace.indexOf('recovery_resolved'), lessThan(trace.indexOf('bootstrap_started')));
      expect(
        trace.indexOf('bootstrap_started'),
        lessThan(trace.indexOf('bootstrap_autosync_suppressed')),
      );
    });

    test('BOOTSTRAP_OBSERVABILITY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      await seedItem();
      SyncQueueRecoveryDiagnostics.noteBootstrapAutosyncSuppressed();
      final r = await SyncQueueService.processPending(scopeLojaId: 'loja-obs');
      expect(r.blockedByRecoveryMode, isTrue);
      expect(SyncQueueRecoveryDiagnostics.bootstrapAutosyncSuppressedCount, 1);
      expect(SyncQueueRecoveryDiagnostics.processPendingBlockedCount, 1);
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 0);
      final left =
          await SyncQueueService.listQueueMetadata(storeId: 'loja-obs');
      expect(left.length, 1);
    });

    test('HOME_OBSERVABILITY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      SyncQueueRecoveryDiagnostics.noteHomeAutosyncSuppressed();
      final r = await AutoSyncService.syncCompleto();
      expect(r.erro, 'queue_recovery_mode');
      expect(SyncQueueRecoveryDiagnostics.homeAutosyncSuppressedCount, 1);
      expect(SyncQueueRecoveryDiagnostics.autoSyncServiceSuppressedCount, 1);
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 0);
    });

    test('AUTOSYNC_OBSERVABILITY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final r = await AutoSyncService.syncCompleto();
      expect(r.erro, 'queue_recovery_mode');
      expect(SyncQueueRecoveryDiagnostics.autoSyncServiceSuppressedCount, 1);
    });

    test('CONNECTIVITY_OBSERVABILITY_TEST', () {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      SyncQueueRecoveryDiagnostics.noteConnectivityAutosyncSuppressed();
      expect(
        SyncQueueRecoveryDiagnostics.connectivityAutosyncSuppressedCount,
        1,
      );
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 0);
    });

    test('PROCESS_PENDING_OBSERVABILITY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      await seedItem();
      final before =
          await SyncQueueService.listQueueMetadata(storeId: 'loja-obs');
      final r = await SyncQueueService.processPending(scopeLojaId: 'loja-obs');
      expect(r.blockedByRecoveryMode, isTrue);
      expect(SyncQueueRecoveryDiagnostics.processPendingBlockedCount, 1);
      final after =
          await SyncQueueService.listQueueMetadata(storeId: 'loja-obs');
      expect(after.length, before.length);
    });

    test('RETRY_ITEM_OBSERVABILITY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final id = await seedItem();
      final ok = await SyncQueueService.retryItem(id);
      expect(ok, isFalse);
      expect(SyncQueueRecoveryDiagnostics.retryItemBlockedCount, 1);
      expect(SyncQueueRecoveryDiagnostics.processPendingBlockedCount, 0);
      final left =
          await SyncQueueService.listQueueMetadata(storeId: 'loja-obs');
      expect(left.length, 1);
    });

    test('QUEUE_HANDLER_ESCAPE_COUNTER_TEST', () {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 0);
      // Intentional unit bypass to validate counter wiring.
      SyncQueueRecoveryDiagnostics.noteQueueHandlerExecution();
      expect(SyncQueueRecoveryDiagnostics.queueHandlerExecutionCount, 1);
    });

    test('DIAGNOSTIC_SNAPSHOT_PRIVACY_TEST', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-obs',
        boxName: 'box_loja-obs',
        entityKey: 99,
        lastError: 'customer maria@example.com phone +5511999999999 produto X',
        scheduleProcess: false,
      );
      final snap =
          SyncQueueRecoveryDiagnostics.getRecoveryDiagnosticsSnapshot();
      final encoded = snap.toString();
      expect(encoded.contains('maria@example.com'), isFalse);
      expect(encoded.contains('+5511999999999'), isFalse);
      expect(encoded.contains('produto X'), isFalse);
      expect(snap.containsKey('eventTrace'), isTrue);
      expect(snap['diagnosticSchemaVersion'], 1);
    });

    test('BROWSER_BRIDGE_READ_ONLY_TEST conceptual', () {
      // Bridge install is web-only; on VM we assert snapshot API is read-only
      // and diagnostics type exposes no mutating queue methods.
      final snap =
          SyncQueueRecoveryDiagnostics.getRecoveryDiagnosticsSnapshot();
      expect(snap.keys.contains('processPending'), isFalse);
      expect(snap.keys.contains('retryItem'), isFalse);
      expect(snap.keys.contains('processOneById'), isFalse);
      expect(snap.keys.contains('enqueue'), isFalse);
    });
  });
}
