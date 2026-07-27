import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_chain_builder.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_chain_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust chain audit', () {
    const builder = CryptographicTrustChainBuilder();
    const validator = CryptographicTrustChainValidator();

    test('validator accepts valid trust chain', () {
      final chain = CryptographicTrustTestFixtures.validTrustChain();
      expect(validator.validate(chain).isValid, isTrue);
    });

    test('validator rejects empty trustChainId', () {
      final chain = CryptographicTrustTestFixtures.validTrustChain().copyWith(
        trustChainId: '',
      );
      expect(validator.validate(chain).isValid, isFalse);
    });

    test('evaluation produces trust chains in snapshot', () async {
      final result = await evaluatePassingSnapshot();
      expect(result.snapshot?.trustChains, isNotEmpty);
    });

    test('built chain status is structural not release authorization',
        () async {
      final result = await evaluatePassingSnapshot();
      final chain = result.snapshot!.trustChains.first;
      expect(chain.status, isA<CryptographicTrustStatus>());
      expect(result.metadata['noReleaseAuthorization'], 'true');
    });

    test('chain builder limitations include no-release-authorization', () {
      const builder = CryptographicTrustChainBuilder();
      final limitations =
          const CryptographicTrustChainBuildResult(chains: []).limitations;
      expect(limitations, contains('no-release-authorization'));
      expect(builder, isNotNull);
    });

    test('chain comparable excludes builtAt timestamp', () {
      final chain = CryptographicTrustTestFixtures.validTrustChain();
      expect(chain.toComparableJson().containsKey('builtAt'), isFalse);
    });
  });
}
