import 'release_evidence_enums.dart';

/// Structural reference to a signature (no cryptographic verification).
class ReleaseSignatureReference {
  const ReleaseSignatureReference({
    required this.signatureId,
    required this.signatureType,
    required this.algorithm,
    required this.signedArtifactId,
    required this.signedFingerprint,
    required this.signatureLocation,
    required this.verificationStatus,
    this.keyId,
    this.certificateId,
    this.issuedAt,
    this.verifierReference,
    this.limitations = const [],
    this.metadata = const {},
  });

  final String signatureId;
  final String signatureType;
  final String algorithm;
  final String? keyId;
  final String? certificateId;
  final String signedArtifactId;
  final String signedFingerprint;
  final String signatureLocation;
  final String? issuedAt;
  final ReleaseSignatureVerificationStatus verificationStatus;
  final String? verifierReference;
  final List<String> limitations;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'signatureId': signatureId,
        'signatureType': signatureType,
        'algorithm': algorithm,
        if (keyId != null) 'keyId': keyId,
        if (certificateId != null) 'certificateId': certificateId,
        'signedArtifactId': signedArtifactId,
        'signedFingerprint': signedFingerprint,
        'signatureLocation': signatureLocation,
        if (issuedAt != null) 'issuedAt': issuedAt,
        'verificationStatus': verificationStatus.wireName,
        if (verifierReference != null) 'verifierReference': verifierReference,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseSignatureReference.fromJson(Map<String, dynamic> json) {
    return ReleaseSignatureReference(
      signatureId: json['signatureId'] as String,
      signatureType: json['signatureType'] as String,
      algorithm: json['algorithm'] as String,
      keyId: json['keyId'] as String?,
      certificateId: json['certificateId'] as String?,
      signedArtifactId: json['signedArtifactId'] as String,
      signedFingerprint: json['signedFingerprint'] as String,
      signatureLocation: json['signatureLocation'] as String,
      issuedAt: json['issuedAt'] as String?,
      verificationStatus: ReleaseSignatureVerificationStatusX.fromWireName(
        json['verificationStatus'] as String,
      ),
      verifierReference: json['verifierReference'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
