import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

CryptographicTrustSnapshot? _resolveSnapshot(
  DashboardSectionBuildContext context,
) {
  return context.sources.cryptographicTrust ??
      context.request.cryptographicTrustSnapshot;
}

/// Summary section for cryptographic trust snapshots (read-only).
class CryptographicTrustSummarySectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustSummarySectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustSummary;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Cryptographic Trust Summary',
        order: 160,
        widgets: context.request.includeUnavailable
            ? [
                unavailableWidget(
                  'cryptographicTrust.summary',
                  'Cryptographic Trust',
                ),
              ]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Cryptographic trust snapshot unavailable'],
      );
    }

    final meta = snapshot.metadata;
    final verifiedCount = snapshot.verificationResults
        .where((v) => v.status == CryptographicVerificationStatus.verified)
        .length;

    return buildSection(
      type: sectionType,
      title: 'Cryptographic Trust Summary',
      order: 160,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'cryptographicTrust.summary.status',
          title: 'Snapshot Status',
          status: snapshot.status.wireName,
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.summary.release',
          title: 'Release',
          status: meta.releaseId ?? '-',
          order: 1,
        ),
        scalarWidget(
          widgetId: 'cryptographicTrust.summary.subjects',
          title: 'Subjects',
          value: snapshot.subjects.length.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'cryptographicTrust.summary.signatures',
          title: 'Signatures',
          value: snapshot.signatures.length.toDouble(),
          order: 3,
        ),
        scalarWidget(
          widgetId: 'cryptographicTrust.summary.attestations',
          title: 'Attestations',
          value: snapshot.attestations.length.toDouble(),
          order: 4,
        ),
        scalarWidget(
          widgetId: 'cryptographicTrust.summary.verified',
          title: 'Verified Results',
          value: verifiedCount.toDouble(),
          order: 5,
        ),
      ],
      limitations: [
        'verified-does-not-authorize-release',
        ...meta.limitations,
        ...snapshot.limitations,
      ],
    );
  }
}

/// Signatures section — IDs and algorithm metadata only.
class CryptographicTrustSignaturesSectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustSignaturesSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustSignatures;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Signatures',
        order: 161,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cryptographicTrust.signatures', 'Signatures')]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Signatures',
      order: 161,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.signatures.count',
          title: 'Signature Count',
          value: snapshot.signatures.length.toDouble(),
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.signatures.algorithms',
          title: 'Algorithms',
          status: snapshot.signatures
              .map((s) => s.signatureDescriptor.algorithmId)
              .toSet()
              .join(', '),
          order: 1,
        ),
      ],
    );
  }
}

/// Attestations section.
class CryptographicTrustAttestationsSectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustAttestationsSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustAttestations;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Attestations',
        order: 162,
        widgets: context.request.includeUnavailable
            ? [
                unavailableWidget(
                  'cryptographicTrust.attestations',
                  'Attestations',
                ),
              ]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Attestations',
      order: 162,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.attestations.count',
          title: 'Attestation Count',
          value: snapshot.attestations.length.toDouble(),
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.attestations.types',
          title: 'Types',
          status: snapshot.attestations
              .map((a) => a.attestationType.wireName)
              .toSet()
              .join(', '),
          order: 1,
        ),
      ],
    );
  }
}

/// Trust chains section.
class CryptographicTrustChainsSectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustChainsSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustChains;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Trust Chains',
        order: 163,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cryptographicTrust.chains', 'Trust Chains')]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Trust Chains',
      order: 163,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.chains.count',
          title: 'Chain Count',
          value: snapshot.trustChains.length.toDouble(),
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.chains.statuses',
          title: 'Statuses',
          status: snapshot.trustChains
              .map((c) => c.status.wireName)
              .toSet()
              .join(', '),
          order: 1,
        ),
      ],
    );
  }
}

/// Policy evaluation section.
class CryptographicTrustPolicyEvaluationSectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustPolicyEvaluationSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustPolicyEvaluation;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Policy Evaluation',
        order: 164,
        widgets: context.request.includeUnavailable
            ? [
                unavailableWidget(
                  'cryptographicTrust.policyEvaluation',
                  'Policy Evaluation',
                ),
              ]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    final policyResults =
        snapshot.verificationResults.expand((v) => v.policyResults).toList();

    return buildSection(
      type: sectionType,
      title: 'Policy Evaluation',
      order: 164,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.policyEvaluation.policy-count',
          title: 'Policies',
          value: snapshot.trustPolicies.length.toDouble(),
        ),
        scalarWidget(
          widgetId: 'cryptographicTrust.policyEvaluation.result-count',
          title: 'Policy Results',
          value: policyResults.length.toDouble(),
          order: 1,
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.policyEvaluation.statuses',
          title: 'Evaluation Statuses',
          status:
              policyResults.map((p) => p.status.wireName).toSet().join(', '),
          order: 2,
        ),
      ],
    );
  }
}

/// Revocation section.
class CryptographicTrustRevocationSectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustRevocationSectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustRevocation;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Revocation',
        order: 165,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('cryptographicTrust.revocation', 'Revocation')]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Revocation',
      order: 165,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.revocation.count',
          title: 'Revocation Records',
          value: snapshot.revocations.length.toDouble(),
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.revocation.statuses',
          title: 'Statuses',
          status: snapshot.revocations
              .map((r) => r.status.wireName)
              .toSet()
              .join(', '),
          order: 1,
        ),
      ],
    );
  }
}

/// Transparency log references section.
class CryptographicTrustTransparencySectionBuilder
    implements DashboardSectionBuilder {
  const CryptographicTrustTransparencySectionBuilder();

  @override
  DashboardSectionType get sectionType =>
      DashboardSectionType.cryptographicTrustTransparency;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = _resolveSnapshot(context);
    if (snapshot == null) {
      return buildSection(
        type: sectionType,
        title: 'Transparency',
        order: 166,
        widgets: context.request.includeUnavailable
            ? [
                unavailableWidget(
                  'cryptographicTrust.transparency',
                  'Transparency',
                ),
              ]
            : [],
        availability: DashboardAvailability.unavailable,
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Transparency',
      order: 166,
      availability: DashboardAvailability.available,
      widgets: [
        scalarWidget(
          widgetId: 'cryptographicTrust.transparency.count',
          title: 'Log References',
          value: snapshot.transparencyLogReferences.length.toDouble(),
        ),
        statusWidget(
          widgetId: 'cryptographicTrust.transparency.logs',
          title: 'Log IDs',
          status: snapshot.transparencyLogReferences
              .map((t) => t.logId)
              .toSet()
              .join(', '),
          order: 1,
        ),
      ],
    );
  }
}
