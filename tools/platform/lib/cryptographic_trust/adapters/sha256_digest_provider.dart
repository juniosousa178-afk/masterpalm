import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../interfaces/cryptographic_digest_provider.dart';

/// SHA-256 digest provider using package:crypto.
class Sha256DigestProvider implements CryptographicDigestProvider {
  const Sha256DigestProvider();

  static const defaultAlgorithmId = 'sha256-v1';

  @override
  String get algorithmId => defaultAlgorithmId;

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.digest,
      };

  @override
  CryptographicDigest computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigestDescriptor descriptor,
    required String subjectId,
  }) {
    if (descriptor.algorithm != CryptographicDigestAlgorithm.sha256 ||
        descriptor.algorithmId != algorithmId) {
      throw UnsupportedError(
          'Unsupported digest algorithm: ${descriptor.algorithmId}');
    }
    final digest = sha256.convert(subjectBytes);
    return CryptographicDigest(
      descriptor: descriptor,
      value: digest.toString(),
      encoding: 'hex',
      subjectId: subjectId,
    );
  }
}

List<int> hexToBytes(String hex) {
  return List<int>.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  );
}

String bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String base64ToHex(String base64Value) {
  return bytesToHex(base64.decode(base64Value));
}
