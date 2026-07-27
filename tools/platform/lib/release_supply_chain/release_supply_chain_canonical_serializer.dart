import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/compliance_models.dart';
import '../models/release_supply_chain/release_distribution_models.dart';
import '../models/release_supply_chain/release_provenance_record.dart';
import '../models/release_supply_chain/release_supply_chain_messages.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/release_supply_chain/sbom_models.dart';
import '../models/release_supply_chain/supply_chain_models.dart';

/// Canonical serialization and fingerprinting for release supply chain.
class ReleaseSupplyChainCanonicalSerializer {
  const ReleaseSupplyChainCanonicalSerializer();

  static const String version = 'release-supply-chain-canonical-v1';

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String supplyChainPolicyFingerprint(RegisteredSupplyChainPolicy policy) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(policy.toComparableJson())),
    );
  }

  String distributionPolicyFingerprint(RegisteredDistributionPolicy policy) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(policy.toComparableJson())),
    );
  }

  String compliancePolicyFingerprint(RegisteredCompliancePolicy policy) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(policy.toComparableJson())),
    );
  }

  String requestFingerprint(ReleaseSupplyChainRequest request) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(request.toJson())),
    );
  }

  String snapshotFingerprint(ReleaseSupplyChainSnapshot snapshot) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(snapshot.toComparableJson())),
    );
  }

  String provenanceFingerprint(ReleaseProvenanceRecord record) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(record.toComparableJson())),
    );
  }

  String supplyChainFingerprint(SupplyChainRecord record) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(record.toComparableJson())),
    );
  }

  String sbomFingerprint(SoftwareBillOfMaterials sbom) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(sbom.toComparableJson())),
    );
  }

  String registryFingerprint(List<ArtifactRecord> artifacts) {
    final comparable = artifacts.map((e) => e.toComparableJson()).toList()
      ..sort(
        (a, b) => (a['metadata'] as Map)['recordId']
            .toString()
            .compareTo((b['metadata'] as Map)['recordId'].toString()),
      );
    return fingerprintFromString(
        jsonEncode(_normalizeJson({'artifacts': comparable})));
  }

  String distributionFingerprint(ReleaseDistribution distribution) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(distribution.toComparableJson())),
    );
  }

  String complianceFingerprint(ComplianceResult result) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(result.toComparableJson())),
    );
  }

  String sourceReferencesFingerprint(
    List<ReleaseSupplyChainSourceReference> references,
  ) {
    final refs = references.map((r) => _normalizeJson(r.toJson())).toList()
      ..sort(
        (a, b) =>
            (a['sourceType'] as String).compareTo(b['sourceType'] as String),
      );
    return fingerprintFromString(jsonEncode(refs));
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalizeJson(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        throw FormatException('Non-finite value in canonicalization');
      }
      if (value == -0.0) return 0.0;
      return value;
    }
    return value;
  }
}
