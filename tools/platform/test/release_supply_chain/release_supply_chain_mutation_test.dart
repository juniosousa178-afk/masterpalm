import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_policy_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/release_supply_chain/artifact_registry_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/compliance_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_identity_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_snapshot_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/sbom_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/supply_chain_validator.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

/// Mutation coverage registry for Sprint 05.0 Part 3.
/// Each case documents a single-field mutation and expected validator rejection.
void main() {
  group('Release Supply Chain mutation tests', () {
    const snapshotValidator = ReleaseSupplyChainSnapshotValidator();
    const supplyChainValidator = SupplyChainValidator();
    const sbomValidator = SbomValidator();
    const artifactValidator = ArtifactRegistryValidator();
    const complianceValidator = ComplianceValidator();
    const identity = ReleaseSupplyChainIdentityBuilder();

    final snapshotMutations = <String, dynamic Function()>{
      'snapshot-empty-fingerprint': () =>
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot()
              .copyWith(fingerprint: ''),
      'snapshot-metadata-fingerprint-mismatch': () {
        final s = ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(fingerprint: 'mismatch'),
        );
      },
      'snapshot-empty-snapshot-id': () {
        final s = ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(supplyChainSnapshotId: ''),
        );
      },
    };

    for (final entry in snapshotMutations.entries) {
      test('snapshot validator rejects ${entry.key}', () {
        final mutated = entry.value() as ReleaseSupplyChainSnapshot;
        final result = snapshotValidator.validate(mutated);
        expect(result.isValid, isFalse, reason: entry.key);
      });
    }

    test('supply chain validator rejects empty fingerprint mutation', () {
      final record = ReleaseSupplyChainTestFixtures.validSupplyChainRecord()
          .copyWith(fingerprint: '');
      expect(supplyChainValidator.validate(record).isValid, isFalse);
    });

    test('sbom validator rejects component count mismatch mutation', () {
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final mutated = sbom.copyWith(
        metadata: sbom.metadata.copyWith(componentCount: 99),
      );
      expect(sbomValidator.validate(mutated).isValid, isFalse);
    });

    test('artifact validator rejects empty digest mutation', () {
      final artifact = ReleaseSupplyChainTestFixtures.validArtifactRecord();
      final mutated = artifact.copyWith(
        integrity: artifact.integrity.copyWith(
          digest: artifact.integrity.digest.copyWith(value: ''),
        ),
      );
      expect(artifactValidator.validate(mutated).isValid, isFalse);
    });

    test('compliance validator rejects nonCompliant without violations', () {
      final comp =
          ReleaseSupplyChainTestFixtures.validComplianceResult().copyWith(
        status: ComplianceStatus.nonCompliant,
        violations: const [],
      );
      expect(complianceValidator.validate(comp).isValid, isFalse);
    });

    test('identity fingerprint changes when normative field mutates', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final fp1 = identity.fingerprintForSnapshot(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(commitId: 'mutated-commit'),
      );
      expect(identity.fingerprintForSnapshot(mutated), isNot(fp1));
    });

    test('compliance policy mutation with empty rules fails validator', () {
      final policy = CompliancePolicyV1.create();
      final json = policy.toJson();
      (json['policy'] as Map<String, dynamic>)['rules'] = [];
      final mutated = RegisteredCompliancePolicy.fromJson(json);
      expect(
        complianceValidator
            .validate(
              ReleaseSupplyChainTestFixtures.validComplianceResult().copyWith(
                policy: mutated.policy,
              ),
            )
            .isValid,
        isFalse,
      );
    });
  });
}
