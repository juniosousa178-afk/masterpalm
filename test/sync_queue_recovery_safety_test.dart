// Recovery-safety layer for Nathy queue reconnect (local diagnostic patch).
// Does not touch production / live Nathy profiles.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/sync_queue_recovery_mode.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:master_palm/services/auto_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_queue_recovery_');
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

  Future<String> seedItem({
    required SyncOperationType type,
    required String lojaId,
    required int entityKey,
    String? lastError,
    String? stockIntentJson,
  }) async {
    await SyncQueueService.enqueue(
      type: type,
      lojaId: lojaId,
      boxName: 'box_$lojaId',
      entityKey: entityKey,
      lastError: lastError,
      scheduleProcess: false,
      stockIntentJson: stockIntentJson,
    );
    final list = await SyncQueueService.listQueueMetadata(
      storeId: lojaId,
      type: type,
    );
    return list.firstWhere((e) => e.entityKey == entityKey).queueItemId;
  }

  Future<String> queueFingerprint() async {
    await SyncQueueService.init();
    // Stable fingerprint of queue records only (exclude export timestamp).
    final entries = await SyncQueueService.listQueueMetadata();
    final stable = entries
        .map((e) =>
            '${e.queueItemId}|${e.itemType}|${e.storeId}|${e.entityKey}|'
            '${e.attemptCount}|${e.deadLetter}|${e.payloadFingerprint}')
        .toList()
      ..sort();
    return sha256.convert(utf8.encode(stable.join('\n'))).toString();
  }

  group('recovery mode default / URI', () {
    test('RECOVERY_MODE_DEFAULT off', () {
      expect(SyncQueueRecoveryMode.isActive, isFalse);
      expect(SyncQueueRecoveryMode.defaultsToOff, isTrue);
      expect(SyncQueueRecoveryMode.allowsAutomaticQueueProcessing, isTrue);
    });

    test('explicit URI opt-in activates session mode', () {
      final uri = Uri.parse(
        'https://app.mastepalm.com.br/?mpQueueRecovery=1',
      );
      expect(SyncQueueRecoveryMode.resolveFromUri(uri), isTrue);
      expect(SyncQueueRecoveryMode.isActive, isTrue);
      expect(SyncQueueRecoveryMode.activationSource, 'uri');
    });

    test('unrelated query does not activate', () {
      final uri = Uri.parse('https://app.mastepalm.com.br/?diag=1');
      expect(SyncQueueRecoveryMode.resolveFromUri(uri), isFalse);
      expect(SyncQueueRecoveryMode.isActive, isFalse);
    });
  });

  group('processPending / retryItem recovery guards', () {
    test('DIRECT_PROCESS_PENDING_RECOVERY_GUARD', () async {
      await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'nathy-pratas-e-folheados',
        entityKey: 1,
      );
      final before = await queueFingerprint();
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final r = await SyncQueueService.processPending();
      expect(r.blockedByRecoveryMode, isTrue);
      expect(r.processed, 0);
      expect(await queueFingerprint(), before);
    });

    test('RETRY_ITEM_RECOVERY_GUARD', () async {
      final id = await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'nathy-pratas-e-folheados',
        entityKey: 2,
        lastError: 'previous',
      );
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final before = await queueFingerprint();
      final ok = await SyncQueueService.retryItem(id);
      expect(ok, isFalse);
      expect(await queueFingerprint(), before);
    });

    test('AutoSync.syncCompleto skipped in recovery mode', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final r = await AutoSyncService.syncCompleto();
      expect(r.erro, 'queue_recovery_mode');
      expect(r.sucesso, isTrue);
    });
  });

  group('metadata inventory', () {
    test('METADATA_INVENTORY excludes sensitive payload', () async {
      await seedItem(
        type: SyncOperationType.upsertProduto,
        lojaId: 'nathy-pratas-e-folheados',
        entityKey: 9,
        lastError: 'fail user@example.com phone +55 11 99999-8888',
        stockIntentJson: jsonEncode({
          'clienteNome': 'SECRET_NAME',
          'email': 'secret@example.com',
          'operationId': 'op-safe-meta',
        }),
      );
      final before = await queueFingerprint();
      final entries = await SyncQueueService.listQueueMetadata(
        storeId: 'nathy-pratas-e-folheados',
      );
      expect(entries, isNotEmpty);
      final json = jsonEncode(entries.map((e) => e.toSafeJson()).toList());
      expect(json.contains('SECRET_NAME'), isFalse);
      expect(json.contains('secret@example.com'), isFalse);
      expect(json.contains('stockIntentJson'), isFalse);
      expect(json.contains('clienteNome'), isFalse);
      expect(entries.first.lastErrorCategory.contains('@'), isFalse);
      expect(entries.first.itemType, 'upsertProduto');
      expect(await queueFingerprint(), before);
    });

    test('LEGACY_SALE_ITEMS_IDENTIFIABLE_BY_METADATA', () async {
      await seedItem(
        type: SyncOperationType.upsertVenda,
        lojaId: 'nathy-pratas-e-folheados',
        entityKey: 3,
      );
      final agg = await SyncQueueService.aggregateQueueInventory(
        storeId: 'nathy-pratas-e-folheados',
      );
      expect(agg.byType['upsertVenda'], 1);
      expect(agg.total, 1);
    });

    test('INVENTORY_QUEUE_MUTATION zero', () async {
      await seedItem(
        type: SyncOperationType.upsertFornecedor,
        lojaId: 'loja-a',
        entityKey: 4,
      );
      final before = await queueFingerprint();
      await SyncQueueService.listQueueMetadata();
      await SyncQueueService.aggregateQueueInventory();
      expect(await queueFingerprint(), before);
    });
  });

  group('backup', () {
    test('QUEUE_BACKUP non-destructive with integrity', () async {
      await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-b',
        entityKey: 5,
      );
      final before = await queueFingerprint();
      final outDir =
          await Directory.systemTemp.createTemp('mp_queue_backup_out_');
      final path = '${outDir.path}${Platform.pathSeparator}queue_backup.json';
      final integrity = await SyncQueueService.writeRawBackupToPath(path);
      expect(integrity.recordCount, 1);
      expect(integrity.boxName, 'sync_queue');
      expect(integrity.contentSha256, isNotEmpty);
      expect(integrity.sensitivityLabel, contains('SENSITIVE'));
      final fileBytes = await File(path).readAsBytes();
      expect(sha256.convert(fileBytes).toString(), integrity.contentSha256);
      expect(await queueFingerprint(), before);
      // Do not print file contents (sensitive).
      await outDir.delete(recursive: true);
    });
  });

  group('isolated single-item executor', () {
    test('ISOLATED_SINGLE_ITEM touches only selected', () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final id1 = await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-x',
        entityKey: 10,
      );
      final id2 = await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-x',
        entityKey: 11,
      );
      final id3 = await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-x',
        entityKey: 12,
      );

      final dry = await SyncQueueService.processOneById(
        queueItemId: id2,
        expectedStoreId: 'loja-x',
        expectedType: SyncOperationType.upsertCliente,
        dryRun: true,
      );
      expect(dry.outcome, SyncQueueOneItemOutcome.dryRunOk);
      expect(dry.mutatedQueue, isFalse);

      final seen = <String>[];
      SyncQueueService.debugOneItemExecuteHook = (item) async {
        seen.add(item.id);
        return true;
      };

      final exec = await SyncQueueService.processOneById(
        queueItemId: id2,
        expectedStoreId: 'loja-x',
        expectedType: SyncOperationType.upsertCliente,
        dryRun: false,
      );
      expect(exec.outcome, SyncQueueOneItemOutcome.executedSuccess);
      expect(seen, [id2]);
      expect(seen.contains(id1), isFalse);
      expect(seen.contains(id3), isFalse);

      // Direct processPending remains blocked in recovery mode.
      final pending = await SyncQueueService.processPending();
      expect(pending.blockedByRecoveryMode, isTrue);

      final remaining = await SyncQueueService.listQueueMetadata(
        storeId: 'loja-x',
      );
      expect(remaining.map((e) => e.queueItemId).toSet(), {id1, id3});
    });

    test('LEGACY_SALE_RECOVERY_BLOCK zero mutation', () async {
      final saleId = await seedItem(
        type: SyncOperationType.upsertVenda,
        lojaId: 'loja-x',
        entityKey: 20,
      );
      final before = await queueFingerprint();
      var hookCalls = 0;
      SyncQueueService.debugOneItemExecuteHook = (_) async {
        hookCalls++;
        return true;
      };
      final r = await SyncQueueService.processOneById(
        queueItemId: saleId,
        expectedStoreId: 'loja-x',
        expectedType: SyncOperationType.upsertVenda,
        dryRun: false,
      );
      expect(r.outcome, SyncQueueOneItemOutcome.blockedLegacySaleRecovery);
      expect(r.mutatedQueue, isFalse);
      expect(hookCalls, 0);
      expect(await queueFingerprint(), before);
    });

    test('UNKNOWN / unsupported type block via type mismatch', () async {
      final id = await seedItem(
        type: SyncOperationType.upsertProduto,
        lojaId: 'loja-x',
        entityKey: 30,
      );
      final before = await queueFingerprint();
      final r = await SyncQueueService.processOneById(
        queueItemId: id,
        expectedStoreId: 'loja-x',
        expectedType: SyncOperationType.upsertCliente,
        dryRun: false,
      );
      expect(r.outcome, SyncQueueOneItemOutcome.typeMismatch);
      expect(await queueFingerprint(), before);
    });

    test('store guard blocks wrong store', () async {
      final id = await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-a',
        entityKey: 40,
      );
      final r = await SyncQueueService.processOneById(
        queueItemId: id,
        expectedStoreId: 'loja-b',
        expectedType: SyncOperationType.upsertCliente,
        dryRun: false,
      );
      expect(r.outcome, SyncQueueOneItemOutcome.storeMismatch);
    });
  });

  group('normal mode preserved', () {
    test('processPending not blocked when recovery OFF', () async {
      expect(SyncQueueRecoveryMode.isActive, isFalse);
      await seedItem(
        type: SyncOperationType.upsertCliente,
        lojaId: 'loja-n',
        entityKey: 50,
      );
      // Empty entity → handler returns true and removes item (cliente missing).
      final r = await SyncQueueService.processPending(scopeLojaId: 'loja-n');
      expect(r.blockedByRecoveryMode, isFalse);
      // Item removed because Hive entity absent (existing semantics).
      final left = await SyncQueueService.listQueueMetadata(storeId: 'loja-n');
      expect(left, isEmpty);
    });
  });
}
