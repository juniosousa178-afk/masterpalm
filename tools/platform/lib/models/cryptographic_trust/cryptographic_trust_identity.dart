/// Deterministic identity for a Cryptographic Trust snapshot.
///
/// Domain fingerprint != cryptographic signature.
class CryptographicTrustIdentity {
  const CryptographicTrustIdentity({
    required this.cryptographicTrustId,
    this.subjectsFingerprint,
    this.signaturesFingerprint,
    this.attestationsFingerprint,
    this.policiesFingerprint,
    this.trustChainsFingerprint,
    this.verificationFingerprint,
    this.snapshotFingerprint,
  });

  final String cryptographicTrustId;
  final String? subjectsFingerprint;
  final String? signaturesFingerprint;
  final String? attestationsFingerprint;
  final String? policiesFingerprint;
  final String? trustChainsFingerprint;
  final String? verificationFingerprint;
  final String? snapshotFingerprint;

  Map<String, dynamic> toJson() => {
        'cryptographicTrustId': cryptographicTrustId,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (signaturesFingerprint != null)
          'signaturesFingerprint': signaturesFingerprint,
        if (attestationsFingerprint != null)
          'attestationsFingerprint': attestationsFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (trustChainsFingerprint != null)
          'trustChainsFingerprint': trustChainsFingerprint,
        if (verificationFingerprint != null)
          'verificationFingerprint': verificationFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  factory CryptographicTrustIdentity.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustIdentity(
      cryptographicTrustId: json['cryptographicTrustId'] as String,
      subjectsFingerprint: json['subjectsFingerprint'] as String?,
      signaturesFingerprint: json['signaturesFingerprint'] as String?,
      attestationsFingerprint: json['attestationsFingerprint'] as String?,
      policiesFingerprint: json['policiesFingerprint'] as String?,
      trustChainsFingerprint: json['trustChainsFingerprint'] as String?,
      verificationFingerprint: json['verificationFingerprint'] as String?,
      snapshotFingerprint: json['snapshotFingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'cryptographicTrustId': cryptographicTrustId,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (signaturesFingerprint != null)
          'signaturesFingerprint': signaturesFingerprint,
        if (attestationsFingerprint != null)
          'attestationsFingerprint': attestationsFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (trustChainsFingerprint != null)
          'trustChainsFingerprint': trustChainsFingerprint,
        if (verificationFingerprint != null)
          'verificationFingerprint': verificationFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  CryptographicTrustIdentity copyWith({
    String? cryptographicTrustId,
    String? subjectsFingerprint,
    String? signaturesFingerprint,
    String? attestationsFingerprint,
    String? policiesFingerprint,
    String? trustChainsFingerprint,
    String? verificationFingerprint,
    String? snapshotFingerprint,
  }) {
    return CryptographicTrustIdentity(
      cryptographicTrustId: cryptographicTrustId ?? this.cryptographicTrustId,
      subjectsFingerprint: subjectsFingerprint ?? this.subjectsFingerprint,
      signaturesFingerprint:
          signaturesFingerprint ?? this.signaturesFingerprint,
      attestationsFingerprint:
          attestationsFingerprint ?? this.attestationsFingerprint,
      policiesFingerprint: policiesFingerprint ?? this.policiesFingerprint,
      trustChainsFingerprint:
          trustChainsFingerprint ?? this.trustChainsFingerprint,
      verificationFingerprint:
          verificationFingerprint ?? this.verificationFingerprint,
      snapshotFingerprint: snapshotFingerprint ?? this.snapshotFingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustIdentity &&
          cryptographicTrustId == other.cryptographicTrustId &&
          subjectsFingerprint == other.subjectsFingerprint &&
          signaturesFingerprint == other.signaturesFingerprint &&
          attestationsFingerprint == other.attestationsFingerprint &&
          policiesFingerprint == other.policiesFingerprint &&
          trustChainsFingerprint == other.trustChainsFingerprint &&
          verificationFingerprint == other.verificationFingerprint &&
          snapshotFingerprint == other.snapshotFingerprint;

  @override
  int get hashCode => Object.hash(
        cryptographicTrustId,
        subjectsFingerprint,
        signaturesFingerprint,
        attestationsFingerprint,
        policiesFingerprint,
        trustChainsFingerprint,
        verificationFingerprint,
        snapshotFingerprint,
      );
}
