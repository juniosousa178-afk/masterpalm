import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';
import '../models/release_supply_chain/supply_chain_models.dart';

/// Validates structural consistency of [SupplyChainRecord].
class SupplyChainValidator {
  const SupplyChainValidator();

  ReleaseSupplyChainValidationResult validate(SupplyChainRecord record) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message,
        {String? relatedId}) {
      errors.add(message);
      issues.add(
        ReleaseSupplyChainValidationIssue(
          code: code,
          path: path,
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (record.recordId.isEmpty) {
      addError('RSC_SC_ID', 'recordId', 'recordId is required');
    }
    if (record.fingerprint.isEmpty) {
      addError('RSC_SC_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (record.policy.policyId.isEmpty) {
      addError('RSC_SC_POLICY_ID', 'policy.policyId', 'policyId is required');
    }

    final nodeIds = <String>{};
    for (final node in record.nodes) {
      if (!nodeIds.add(node.nodeId)) {
        addError(
          'RSC_SC_DUPLICATE_NODE',
          'nodes',
          'duplicate nodeId: ${node.nodeId}',
          relatedId: node.nodeId,
        );
      }
    }

    final edgeIds = <String>{};
    for (final edge in record.edges) {
      if (!edgeIds.add(edge.edgeId)) {
        addError(
          'RSC_SC_DUPLICATE_EDGE',
          'edges',
          'duplicate edgeId: ${edge.edgeId}',
          relatedId: edge.edgeId,
        );
      }
    }

    if (record.evidence.length < record.policy.minimumEvidenceCount) {
      addError(
        'RSC_SC_EVIDENCE_COUNT',
        'evidence',
        'evidence count below policy minimum',
      );
    }

    if (record.status == SupplyChainStatus.blocked) {
      warnings.add('supply chain status is blocked');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
