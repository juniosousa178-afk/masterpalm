import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';

void main() {
  group('PdvV1MalformedJournalEvidence bounds', () {
    test('evidência malformada respeita profundidade máxima', () {
      dynamic nested = 'leaf';
      for (var i = 0; i < 20; i++) {
        nested = {'level': nested};
      }
      final result = pdvV1SanitizeMalformedPayload(nested);
      expect(result.wasTruncated, isTrue);
      expect('${result.payload}', contains('depth_truncated'));
    });

    test('evidência malformada respeita limite de nós', () {
      final map = <String, dynamic>{};
      for (var i = 0; i < 1100; i++) {
        map['k$i'] = i;
      }
      final result = pdvV1SanitizeMalformedPayload(map);
      expect(result.wasTruncated, isTrue);
      expect(result.rejectedNodeCount, greaterThan(0));
    });

    test('evidência sanitiza chaves sensíveis', () {
      final raw = {
        'operationId': 'op-1',
        'accessToken': 'secret-value',
        'password': 'p',
        'email': 'a@b.c',
      };
      final result = pdvV1SanitizeMalformedPayload(raw);
      final payload = result.payload as Map;
      expect(payload['accessToken'], '[redacted]');
      expect(payload['password'], '[redacted]');
      expect(payload['email'], '[redacted]');
      expect(result.redactedKeyCount, greaterThanOrEqualTo(3));
      expect(payload['operationId'], 'op-1');
    });

    test('evidência truncada preserva metadados, não payload excessivo', () {
      final long = 'x' * 500;
      final raw = {'data': long, 'nested': List.filled(200, 1)};
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: raw,
        storageKey: 'trunc-test',
      );
      final evidence = outcome.malformedEvidence!;
      expect(evidence.wasTruncated, isTrue);
      expect(evidence.estimatedPayloadSize, lessThan(40 * 1024));
      expect(evidence.rawPayloadType, 'Map');
      expect(evidence.operationIdCandidate, 'trunc-test');
    });

    test('chave e-mail é redigida', () {
      final raw = {'e-mail': 'user@test.com'};
      final result = pdvV1SanitizeMalformedPayload(raw);
      final payload = result.payload as Map;
      expect(payload['e-mail'], '[redacted]');
    });

    test('payload acima de 32 KiB é truncado', () {
      final raw = {'blob': 'z' * 40000};
      final result = pdvV1SanitizeMalformedPayload(raw);
      expect(result.wasTruncated, isTrue);
      expect(result.estimatedPayloadSize, lessThanOrEqualTo(32 * 1024));
    });

    test('estrutura cíclica não trava nem lança', () {
      final map = <String, dynamic>{};
      map['self'] = map;
      expect(() => pdvV1SanitizeMalformedPayload(map), returnsNormally);
      final result = pdvV1SanitizeMalformedPayload(map);
      expect('${result.payload}', contains('cycle'));
    });

    test('RecoveryPlan não contém rawPayload', () {
      final raw = {'accessToken': 'SECRET', 'state': 'invalid'};
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: raw,
        storageKey: 'op-mal',
      );
      final plan = PdvV1RecoveryOrchestrator().plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final encoded = plan.toJson().toString();
      expect(encoded.contains('SECRET'), isFalse);
      expect(encoded.contains('rawPayload'), isFalse);
    });

    test('fingerprint não contém rawPayload', () {
      final raw = {'password': 'p', 'state': 'invalid'};
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: raw,
        storageKey: 'op-fp-mal',
      );
      final plan = PdvV1RecoveryOrchestrator().plan(
        PdvV1RecoveryOrchestratorInput(journalOutcome: outcome),
      );
      final fp = pdvV1BuildRecoveryPlanFingerprint(
        plan: plan,
        prep: outcome.record.prepared,
      );
      final encoded = fp.toJson().toString();
      expect(encoded.contains('rawPayload'), isFalse);
      expect(encoded.contains('"p"'), isFalse);
    });

    test('reasonCode não contém rawPayload', () {
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: {'state': 'invalid', 'jwt': 'tok'},
        storageKey: 'rc',
      );
      expect(outcome.malformedEvidence!.reasonCode.contains('tok'), isFalse);
      expect(outcome.malformedEvidence!.reasonCode.contains('jwt'), isFalse);
    });

    test('candidatos de identidade permanecem quando recuperáveis', () {
      final raw = {
        'state': 'prepared',
        'prepared': {
          'operationId': 'op-c',
          'saleId': 'sale-c',
          'lojaId': 'loja-c',
          'protocolVersion': 1,
        },
      };
      final outcome = PdvV1JournalRecord.readOutcomeFromRaw(
        rawPayload: raw,
        storageKey: 'fallback-op',
      );
      final e = outcome.malformedEvidence!;
      expect(e.operationIdCandidate, 'op-c');
      expect(e.saleIdCandidate, 'sale-c');
      expect(e.lojaIdCandidate, 'loja-c');
      expect(e.protocolVersionCandidate, 1);
    });
  });
}
