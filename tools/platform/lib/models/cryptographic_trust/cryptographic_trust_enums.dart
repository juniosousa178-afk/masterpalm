/// Cryptographic trust subject taxonomy.
enum CryptographicTrustSubjectType {
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  artifact,
  manifest,
  report,
  bundle,
  document,
  payload,
  attestation,
  signature,
  key,
  trustAnchor,
  custom,
  unknown,
}

extension CryptographicTrustSubjectTypeX on CryptographicTrustSubjectType {
  String get wireName => name;

  static CryptographicTrustSubjectType fromWireName(String value) {
    return CryptographicTrustSubjectType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustSubjectType: $value',
      ),
    );
  }
}

/// Digest algorithm descriptor (domain taxonomy — not an implementation).
enum CryptographicDigestAlgorithm {
  sha256,
  sha384,
  sha512,
  blake2b,
  sha1,
  md5,
  custom,
  unknown,
}

extension CryptographicDigestAlgorithmX on CryptographicDigestAlgorithm {
  String get wireName => name;

  static CryptographicDigestAlgorithm fromWireName(String value) {
    return CryptographicDigestAlgorithm.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicDigestAlgorithm: $value',
      ),
    );
  }
}

/// Signature algorithm descriptor (domain taxonomy — not an implementation).
enum CryptographicSignatureAlgorithm {
  rsaPkcs1,
  rsaPss,
  ecdsa,
  ed25519,
  dsa,
  hmac,
  custom,
  unknown,
}

extension CryptographicSignatureAlgorithmX on CryptographicSignatureAlgorithm {
  String get wireName => name;

  static CryptographicSignatureAlgorithm fromWireName(String value) {
    return CryptographicSignatureAlgorithm.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicSignatureAlgorithm: $value',
      ),
    );
  }
}

/// Signature encoding/format taxonomy.
enum CryptographicSignatureFormat {
  raw,
  der,
  jws,
  cms,
  pgpArmor,
  cobra,
  custom,
  unknown,
}

extension CryptographicSignatureFormatX on CryptographicSignatureFormat {
  String get wireName => name;

  static CryptographicSignatureFormat fromWireName(String value) {
    return CryptographicSignatureFormat.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicSignatureFormat: $value',
      ),
    );
  }
}

/// Public key type taxonomy.
enum CryptographicKeyType {
  rsa,
  ec,
  ed25519,
  dsa,
  symmetric,
  custom,
  unknown,
}

extension CryptographicKeyTypeX on CryptographicKeyType {
  String get wireName => name;

  static CryptographicKeyType fromWireName(String value) {
    return CryptographicKeyType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicKeyType: $value'),
    );
  }
}

/// Key usage classification.
enum CryptographicKeyUsage {
  sign,
  verify,
  encrypt,
  decrypt,
  keyAgreement,
  certificateSign,
  crlSign,
  encipherOnly,
  decipherOnly,
  unknown,
}

extension CryptographicKeyUsageX on CryptographicKeyUsage {
  String get wireName => name;

  static CryptographicKeyUsage fromWireName(String value) {
    return CryptographicKeyUsage.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicKeyUsage: $value'),
    );
  }
}

/// Key lifecycle status.
enum CryptographicKeyStatus {
  active,
  inactive,
  expired,
  revoked,
  compromised,
  pending,
  unknown,
}

extension CryptographicKeyStatusX on CryptographicKeyStatus {
  String get wireName => name;

  static CryptographicKeyStatus fromWireName(String value) {
    return CryptographicKeyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicKeyStatus: $value'),
    );
  }
}

/// Declared trust level (does not authorize release).
enum CryptographicTrustLevel {
  none,
  low,
  moderate,
  high,
  critical,
  unknown,
}

extension CryptographicTrustLevelX on CryptographicTrustLevel {
  String get wireName => name;

  static CryptographicTrustLevel fromWireName(String value) {
    return CryptographicTrustLevel.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicTrustLevel: $value'),
    );
  }
}

/// Trust relationship lifecycle status.
enum CryptographicTrustStatus {
  untrusted,
  provisional,
  trusted,
  expired,
  revoked,
  invalid,
  unknown,
}

extension CryptographicTrustStatusX on CryptographicTrustStatus {
  String get wireName => name;

  static CryptographicTrustStatus fromWireName(String value) {
    return CryptographicTrustStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicTrustStatus: $value'),
    );
  }
}

/// Verification outcome status (structural/declarative — not live crypto verify).
enum CryptographicVerificationStatus {
  pending,
  verified,
  partiallyVerified,
  unverified,
  invalid,
  expired,
  revoked,
  error,
  unknown,
}

extension CryptographicVerificationStatusX on CryptographicVerificationStatus {
  String get wireName => name;

  static CryptographicVerificationStatus fromWireName(String value) {
    return CryptographicVerificationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicVerificationStatus: $value',
      ),
    );
  }
}

/// Attestation kind taxonomy.
enum CryptographicAttestationType {
  artifactIntegrity,
  buildProvenance,
  supplyChain,
  compliance,
  policyCompliance,
  sbom,
  vulnerabilityScan,
  releaseReadiness,
  custom,
  unknown,
}

extension CryptographicAttestationTypeX on CryptographicAttestationType {
  String get wireName => name;

  static CryptographicAttestationType fromWireName(String value) {
    return CryptographicAttestationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicAttestationType: $value',
      ),
    );
  }
}

/// Attestation lifecycle status.
enum CryptographicAttestationStatus {
  draft,
  issued,
  active,
  expired,
  revoked,
  superseded,
  invalid,
  unverified,
  unknown,
}

extension CryptographicAttestationStatusX on CryptographicAttestationStatus {
  String get wireName => name;

  static CryptographicAttestationStatus fromWireName(String value) {
    return CryptographicAttestationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicAttestationStatus: $value',
      ),
    );
  }
}

/// Trust policy lifecycle status.
enum CryptographicPolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
  unknown,
}

extension CryptographicPolicyStatusX on CryptographicPolicyStatus {
  String get wireName => name;

  static CryptographicPolicyStatus fromWireName(String value) {
    return CryptographicPolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicPolicyStatus: $value'),
    );
  }
}

/// Trust requirement kind.
enum CryptographicRequirementType {
  signature,
  attestation,
  trustAnchor,
  transparencyLog,
  keyUsage,
  algorithm,
  revocation,
  digest,
  trustLevel,
  custom,
  unknown,
}

extension CryptographicRequirementTypeX on CryptographicRequirementType {
  String get wireName => name;

  static CryptographicRequirementType fromWireName(String value) {
    return CryptographicRequirementType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicRequirementType: $value',
      ),
    );
  }
}

/// Validation and verification issue severity.
enum CryptographicIssueSeverity {
  info,
  warning,
  error,
  critical,
}

extension CryptographicIssueSeverityX on CryptographicIssueSeverity {
  String get wireName => name;

  static CryptographicIssueSeverity fromWireName(String value) {
    return CryptographicIssueSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicIssueSeverity: $value'),
    );
  }
}

/// Revocation record status.
enum CryptographicRevocationStatus {
  active,
  pending,
  superseded,
  cancelled,
  unknown,
}

extension CryptographicRevocationStatusX on CryptographicRevocationStatus {
  String get wireName => name;

  static CryptographicRevocationStatus fromWireName(String value) {
    return CryptographicRevocationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicRevocationStatus: $value',
      ),
    );
  }
}

/// Transparency log entry status.
enum CryptographicTransparencyLogStatus {
  pending,
  integrated,
  rejected,
  expired,
  unavailable,
  unknown,
}

extension CryptographicTransparencyLogStatusX
    on CryptographicTransparencyLogStatus {
  String get wireName => name;

  static CryptographicTransparencyLogStatus fromWireName(String value) {
    return CryptographicTransparencyLogStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTransparencyLogStatus: $value',
      ),
    );
  }
}

/// Signer/issuer identity kind (not application user identity).
enum CryptographicIdentityType {
  individual,
  organization,
  service,
  automation,
  authority,
  custom,
  unknown,
}

extension CryptographicIdentityTypeX on CryptographicIdentityType {
  String get wireName => name;

  static CryptographicIdentityType fromWireName(String value) {
    return CryptographicIdentityType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicIdentityType: $value'),
    );
  }
}

/// Upstream source module reference kind.
enum CryptographicSourceType {
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  artifact,
  report,
  manifest,
  externalAttestation,
  custom,
  unknown,
}

extension CryptographicSourceTypeX on CryptographicSourceType {
  String get wireName => name;

  static CryptographicSourceType fromWireName(String value) {
    return CryptographicSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CryptographicSourceType: $value'),
    );
  }
}
