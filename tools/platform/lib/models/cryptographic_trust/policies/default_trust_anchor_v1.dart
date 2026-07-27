import '../cryptographic_key_reference.dart';
import '../cryptographic_trust_anchor.dart';
import '../cryptographic_trust_enums.dart';

/// Shared default trust anchor for factory policy descriptors.
const defaultTrustAnchorV1 = CryptographicTrustAnchorReference(
  trustAnchorId: 'anchor-default-v1',
  keyReference: CryptographicKeyReference(
    keyId: 'key-anchor-default',
    keyType: CryptographicKeyType.ed25519,
    algorithmId: 'ed25519-v1',
    usage: [
      CryptographicKeyUsage.sign,
      CryptographicKeyUsage.verify,
    ],
    status: CryptographicKeyStatus.active,
    publicKeyFingerprint:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    version: '1',
    validFrom: '2026-01-01T00:00:00.000Z',
    validUntil: '2028-01-01T00:00:00.000Z',
  ),
  trustLevel: CryptographicTrustLevel.critical,
  status: CryptographicTrustStatus.trusted,
  issuer: 'MasterPalm Default Anchor',
  scope: {'domain': 'cryptographic-trust'},
  validFrom: '2026-01-01T00:00:00.000Z',
  validUntil: '2028-01-01T00:00:00.000Z',
);
