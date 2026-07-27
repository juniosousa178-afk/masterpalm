import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
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
    values: PersistentArtifactType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactType',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactFormat.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactFormatX.fromWireName,
    unknownLabel: 'PersistentArtifactFormat',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactEncoding.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactEncodingX.fromWireName,
    unknownLabel: 'PersistentArtifactEncoding',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactCompression.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactCompressionX.fromWireName,
    unknownLabel: 'PersistentArtifactCompression',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactLifecycleStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactLifecycleStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactLifecycleStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactPublicationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactPublicationStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactPublicationStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactIntegrityStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactIntegrityStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactIntegrityStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactAvailabilityStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactAvailabilityStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactAvailabilityStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactStorageClass.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactStorageClassX.fromWireName,
    unknownLabel: 'PersistentArtifactStorageClass',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactLocationType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactLocationTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactLocationType',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactVersionStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactVersionStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactVersionStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactRetentionAction.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactRetentionActionX.fromWireName,
    unknownLabel: 'PersistentArtifactRetentionAction',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactDeletionStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactDeletionStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactDeletionStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactReplicationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactReplicationStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactReplicationStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactDurabilityLevel.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactDurabilityLevelX.fromWireName,
    unknownLabel: 'PersistentArtifactDurabilityLevel',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactConsistencyModel.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactConsistencyModelX.fromWireName,
    unknownLabel: 'PersistentArtifactConsistencyModel',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactPolicyStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactPolicyStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactPolicyStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactRequirementType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactRequirementTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactRequirementType',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactIssueSeverity.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactIssueSeverityX.fromWireName,
    unknownLabel: 'PersistentArtifactIssueSeverity',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactSourceType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactSourceTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactSourceType',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactOperationType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactOperationTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactOperationType',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactEncryptionStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactEncryptionStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactEncryptionStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactAccessScope.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactAccessScopeX.fromWireName,
    unknownLabel: 'PersistentArtifactAccessScope',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactOperationStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactOperationStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactOperationStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactRetentionRecordStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactRetentionRecordStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactRetentionRecordStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactInfrastructureStatus.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactInfrastructureStatusX.fromWireName,
    unknownLabel: 'PersistentArtifactInfrastructureStatus',
  );
  assertEnumRoundtrip(
    values: PersistentArtifactPolicyType.values,
    wireName: (e) => e.wireName,
    fromWireName: PersistentArtifactPolicyTypeX.fromWireName,
    unknownLabel: 'PersistentArtifactPolicyType',
  );

  test('PersistentArtifactIssueSeverity has exactly three severities', () {
    expect(PersistentArtifactIssueSeverity.values, hasLength(3));
    expect(
      PersistentArtifactIssueSeverity.values.map((e) => e.wireName).toList(),
      ['info', 'warning', 'critical'],
    );
  });

  test('PersistentArtifactType includes unknown sentinel', () {
    expect(
      PersistentArtifactType.values,
      contains(PersistentArtifactType.unknown),
    );
  });
}
