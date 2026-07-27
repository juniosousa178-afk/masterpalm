/// Opaque reference to a signing key — never exposes private key bytes.
///
/// Does not support JSON serialization. [toString] is safe for logs.
class OpaqueCryptographicSigningKeyHandle {
  const OpaqueCryptographicSigningKeyHandle({
    required this.keyId,
    required this.algorithmId,
    required Object holder,
  }) : _holder = holder;

  final String keyId;
  final String algorithmId;
  final Object _holder;

  /// Package-internal accessor for authorized adapters only.
  Object get holder => _holder;

  @override
  String toString() =>
      'OpaqueCryptographicSigningKeyHandle(keyId: $keyId, algorithmId: $algorithmId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpaqueCryptographicSigningKeyHandle &&
          keyId == other.keyId &&
          algorithmId == other.algorithmId &&
          identical(_holder, other._holder);

  @override
  int get hashCode =>
      Object.hash(keyId, algorithmId, identityHashCode(_holder));
}
