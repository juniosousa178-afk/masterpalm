import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:test/test.dart';

void main() {
  void assertEnumRoundtrip<T extends Enum>({
    required List<T> values,
    required String Function(T) wireName,
    required T Function(String) fromWireName,
    required String unknownLabel,
  }) {
    group(unknownLabel, () {
      test('wireName roundtrip for all values', () {
        for (final value in values) {
          expect(fromWireName(wireName(value)), value);
          expect(wireName(value), value.name);
        }
      });

      test('all values covered', () {
        expect(values, isNotEmpty);
        expect(values.map(wireName).toSet(), hasLength(values.length));
      });

      test('unknown wireName throws FormatException', () {
        expect(
          () => fromWireName('__unknown_enum_value__'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  }

  assertEnumRoundtrip(
    values: CryptographicTrustSubjectType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicTrustSubjectTypeX.fromWireName,
    unknownLabel: 'CryptographicTrustSubjectType',
  );
  assertEnumRoundtrip(
    values: CryptographicDigestAlgorithm.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicDigestAlgorithmX.fromWireName,
    unknownLabel: 'CryptographicDigestAlgorithm',
  );
  assertEnumRoundtrip(
    values: CryptographicSignatureAlgorithm.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicSignatureAlgorithmX.fromWireName,
    unknownLabel: 'CryptographicSignatureAlgorithm',
  );
  assertEnumRoundtrip(
    values: CryptographicSignatureFormat.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicSignatureFormatX.fromWireName,
    unknownLabel: 'CryptographicSignatureFormat',
  );
  assertEnumRoundtrip(
    values: CryptographicKeyType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicKeyTypeX.fromWireName,
    unknownLabel: 'CryptographicKeyType',
  );
  assertEnumRoundtrip(
    values: CryptographicKeyUsage.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicKeyUsageX.fromWireName,
    unknownLabel: 'CryptographicKeyUsage',
  );
  assertEnumRoundtrip(
    values: CryptographicKeyStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicKeyStatusX.fromWireName,
    unknownLabel: 'CryptographicKeyStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicTrustLevel.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicTrustLevelX.fromWireName,
    unknownLabel: 'CryptographicTrustLevel',
  );
  assertEnumRoundtrip(
    values: CryptographicTrustStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicTrustStatusX.fromWireName,
    unknownLabel: 'CryptographicTrustStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicVerificationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicVerificationStatusX.fromWireName,
    unknownLabel: 'CryptographicVerificationStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicAttestationType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicAttestationTypeX.fromWireName,
    unknownLabel: 'CryptographicAttestationType',
  );
  assertEnumRoundtrip(
    values: CryptographicAttestationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicAttestationStatusX.fromWireName,
    unknownLabel: 'CryptographicAttestationStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicPolicyStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicPolicyStatusX.fromWireName,
    unknownLabel: 'CryptographicPolicyStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicRequirementType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicRequirementTypeX.fromWireName,
    unknownLabel: 'CryptographicRequirementType',
  );
  assertEnumRoundtrip(
    values: CryptographicIssueSeverity.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicIssueSeverityX.fromWireName,
    unknownLabel: 'CryptographicIssueSeverity',
  );
  assertEnumRoundtrip(
    values: CryptographicRevocationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicRevocationStatusX.fromWireName,
    unknownLabel: 'CryptographicRevocationStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicTransparencyLogStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicTransparencyLogStatusX.fromWireName,
    unknownLabel: 'CryptographicTransparencyLogStatus',
  );
  assertEnumRoundtrip(
    values: CryptographicIdentityType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicIdentityTypeX.fromWireName,
    unknownLabel: 'CryptographicIdentityType',
  );
  assertEnumRoundtrip(
    values: CryptographicSourceType.values,
    wireName: (e) => e.wireName,
    fromWireName: CryptographicSourceTypeX.fromWireName,
    unknownLabel: 'CryptographicSourceType',
  );

  test('CryptographicIssueSeverity has exactly four severities', () {
    expect(CryptographicIssueSeverity.values, hasLength(4));
    expect(
      CryptographicIssueSeverity.values.map((e) => e.wireName).toList(),
      ['info', 'warning', 'error', 'critical'],
    );
  });

  test('CryptographicValidationIssue serializes severity wireName', () {
    const issue = CryptographicValidationIssue(
      code: 'CT_ENUM',
      path: 'severity',
      severity: CryptographicIssueSeverity.critical,
      message: 'critical severity',
    );
    expect(issue.toJson()['severity'], 'critical');
  });
}
