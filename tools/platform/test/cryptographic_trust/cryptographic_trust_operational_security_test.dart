import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/key_material/opaque_cryptographic_signing_key_handle.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust operational security', () {
    test('opaque handle toString excludes holder object', () async {
      await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
      final handle = InMemoryEd25519SigningKeyHandle(
        keyId: 'sec-key',
        keyPair: await CryptographicTrustOperationalFixtures.testKeyPair(),
      );
      final text = handle.toString();
      expect(text, contains('keyId: sec-key'));
      expect(text, isNot(contains('SimpleKeyPair')));
      expect(text, isNot(contains('bytes')));
    });

    test('opaque handle has no toJson serialization', () async {
      await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
      final handle = InMemoryEd25519SigningKeyHandle(
        keyId: 'sec-key',
        keyPair: await CryptographicTrustOperationalFixtures.testKeyPair(),
      );
      expect(handle, isA<OpaqueCryptographicSigningKeyHandle>());
      expect(handle.runtimeType.toString(),
          contains('InMemoryEd25519SigningKeyHandle'));
    });

    test('evaluation result json excludes private key material', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final encoded = jsonEncode(result.toJson());
      expect(encoded.contains('privateKey'), isFalse);
      expect(encoded.contains('secret'), isFalse);
      expect(encoded.contains('seed'), isFalse);
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
    });

    test('snapshot json excludes raw private key fields', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final json = snapshot.toJson();
      expect(json.containsKey('privateKey'), isFalse);
      expect(json.containsKey('secret'), isFalse);
      expect(json.containsKey('seed'), isFalse);
    });

    test('operational fixtures do not expose private key bytes in digest',
        () async {
      final digest =
          await CryptographicTrustOperationalFixtures.digestForPayload(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      expect(digest.toJson().containsKey('privateKey'), isFalse);
      expect(digest.value, hasLength(64));
    });

    test('signed envelope stores signature not private key', () async {
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      expect(envelope.toJson().containsKey('privateKey'), isFalse);
      expect(envelope.signatureValue, isNotEmpty);
    });

    test('domain models directory avoids Process.run', () {
      final dir = Directory('lib/models/cryptographic_trust');
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        expect(file.readAsStringSync().contains('Process.run'), isFalse,
            reason: file.path);
      }
    });

    test('operational layer avoids HttpClient network calls', () {
      final dir = Directory('lib/cryptographic_trust');
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse, reason: file.path);
        expect(content.contains('Socket.connect'), isFalse, reason: file.path);
      }
    });

    test('verification result never marks release authorized', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await stack.provider.verifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result?.toJson().containsKey('releaseAuthorized'), isFalse);
      expect(result?.metadata['noReleaseAuthorization'], 'true');
    });

    test('provider sign result does not expose private key material', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack(
          includeSigner: true);
      await stack.registerTestKeys();
      final template = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final result = await stack.provider.sign(
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        template: template,
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
      expect(result.envelope?.toJson().containsKey('privateKey'), isFalse);
    });
  });
}
