import '../../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';

/// Vendor-neutral digest computation contract.
abstract class CryptographicDigestProvider {
  String get algorithmId;

  Set<CryptographicProviderCapability> get capabilities;

  CryptographicDigest computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigestDescriptor descriptor,
    required String subjectId,
  });
}
