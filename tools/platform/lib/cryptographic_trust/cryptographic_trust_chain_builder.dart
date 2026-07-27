import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_anchor.dart';
import '../models/cryptographic_trust/cryptographic_trust_chain.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';

/// Result of declarative trust chain assembly.
class CryptographicTrustChainBuildResult {
  const CryptographicTrustChainBuildResult({
    required this.chains,
    this.issues = const [],
    this.warnings = const [],
    this.limitations = const [
      'declarative-chain-only',
      'no-x509-path-building',
      'no-release-authorization',
    ],
  });

  final List<CryptographicTrustChain> chains;
  final List<CryptographicVerificationIssue> issues;
  final List<String> warnings;
  final List<String> limitations;
}

/// Builds declarative trust chains from collected material.
///
/// Chain presence does not imply automatic trust or release authorization.
class CryptographicTrustChainBuilder {
  const CryptographicTrustChainBuilder();

  CryptographicTrustChainBuildResult build({
    required CollectedCryptographicTrustMaterial material,
    required String referenceTime,
  }) {
    final chains = <CryptographicTrustChain>[];
    final issues = <CryptographicVerificationIssue>[];
    final warnings = <String>[];
    final keyById = {
      for (final key in material.keyReferences) key.keyId: key,
    };
    final anchorById = {
      for (final anchor in material.trustAnchors) anchor.trustAnchorId: anchor,
    };

    for (final signature in material.signatures) {
      final subjectId = signature.subject.subjectId;
      final leafKey = signature.keyReference;
      final anchorRef = signature.trustAnchorReference;

      if (anchorRef == null) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_CHAIN_ANCHOR_MISSING',
            severity: CryptographicIssueSeverity.warning,
            path: 'signatures.${signature.signatureId}.trustAnchorReference',
            message: 'Signature has no trust anchor reference',
            signatureId: signature.signatureId,
            subjectId: subjectId,
          ),
        );
        continue;
      }

      if (!keyById.containsKey(leafKey.keyId)) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_CHAIN_LEAF_KEY_MISSING',
            severity: CryptographicIssueSeverity.critical,
            path: 'signatures.${signature.signatureId}.keyReference.keyId',
            message: 'Leaf key not found in collected key references',
            signatureId: signature.signatureId,
            subjectId: subjectId,
          ),
        );
      }

      if (!anchorById.containsKey(anchorRef.trustAnchorId) &&
          !keyById.containsKey(anchorRef.keyReference.keyId)) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_CHAIN_ANCHOR_UNRESOLVED',
            severity: CryptographicIssueSeverity.critical,
            path: 'signatures.${signature.signatureId}.trustAnchorReference',
            message: 'Trust anchor not found in collected anchors',
            signatureId: signature.signatureId,
            subjectId: subjectId,
          ),
        );
      }

      final temporalIssue = _validateTemporal(
        leafKey: leafKey,
        anchor: anchorRef,
        referenceTime: referenceTime,
        signatureId: signature.signatureId,
      );
      if (temporalIssue != null) {
        issues.add(temporalIssue);
      }

      final chainIssues = <CryptographicVerificationIssue>[];
      final intermediates = <CryptographicKeyReference>[];
      final visited = <String>{leafKey.keyId};

      for (final intermediate in material.keyReferences) {
        if (intermediate.keyId == leafKey.keyId) continue;
        if (intermediate.keyId == anchorRef.keyReference.keyId) continue;
        if (visited.contains(intermediate.keyId)) {
          chainIssues.add(
            CryptographicVerificationIssue(
              code: 'CT_CHAIN_CYCLE',
              severity: CryptographicIssueSeverity.critical,
              path: 'trustChains.${signature.signatureId}',
              message: 'Cycle detected in intermediate key references',
              signatureId: signature.signatureId,
              subjectId: subjectId,
            ),
          );
          break;
        }
        visited.add(intermediate.keyId);
        intermediates.add(intermediate);
      }

      final status = chainIssues.any(
        (i) => i.severity == CryptographicIssueSeverity.critical,
      )
          ? CryptographicTrustStatus.invalid
          : CryptographicTrustStatus.provisional;

      chains.add(
        CryptographicTrustChain(
          trustChainId: 'chain:${signature.signatureId}',
          subjectId: subjectId,
          signatureId: signature.signatureId,
          leafKey: leafKey,
          intermediateReferences: intermediates,
          trustAnchor: anchorRef,
          status: status,
          issues: chainIssues,
          metadata: const {'builder': 'declarative-v1'},
        ),
      );
    }

    for (final existing in material.trustChains) {
      chains.add(existing);
    }

    chains.sort((a, b) => a.trustChainId.compareTo(b.trustChainId));

    if (chains.isEmpty && material.signatures.isNotEmpty) {
      warnings.add('No trust chains assembled from collected signatures');
    }

    return CryptographicTrustChainBuildResult(
      chains: List.unmodifiable(chains),
      issues: List.unmodifiable(issues),
      warnings: List.unmodifiable(warnings),
    );
  }

  CryptographicVerificationIssue? _validateTemporal({
    required CryptographicKeyReference leafKey,
    required CryptographicTrustAnchorReference anchor,
    required String referenceTime,
    required String signatureId,
  }) {
    if (leafKey.validUntil != null &&
        referenceTime.compareTo(leafKey.validUntil!) > 0) {
      return CryptographicVerificationIssue(
        code: 'CT_CHAIN_KEY_EXPIRED',
        severity: CryptographicIssueSeverity.warning,
        path: 'signatures.$signatureId.keyReference.validUntil',
        message: 'Leaf key is expired at reference time',
        signatureId: signatureId,
      );
    }
    if (leafKey.validFrom != null &&
        referenceTime.compareTo(leafKey.validFrom!) < 0) {
      return CryptographicVerificationIssue(
        code: 'CT_CHAIN_KEY_NOT_YET_VALID',
        severity: CryptographicIssueSeverity.warning,
        path: 'signatures.$signatureId.keyReference.validFrom',
        message: 'Leaf key is not yet valid at reference time',
        signatureId: signatureId,
      );
    }
    return null;
  }
}
