import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Declarative digest algorithm descriptor — does not execute hashing.
class CryptographicDigestDescriptor {
  const CryptographicDigestDescriptor({
    required this.algorithm,
    required this.algorithmId,
    this.outputSizeBits,
    this.parameters = const {},
    this.metadata = const {},
  });

  final CryptographicDigestAlgorithm algorithm;
  final String algorithmId;
  final int? outputSizeBits;
  final Map<String, String> parameters;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm.wireName,
        'algorithmId': algorithmId,
        if (outputSizeBits != null) 'outputSizeBits': outputSizeBits,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicDigestDescriptor.fromJson(Map<String, dynamic> json) {
    return CryptographicDigestDescriptor(
      algorithm: CryptographicDigestAlgorithmX.fromWireName(
        json['algorithm'] as String,
      ),
      algorithmId: json['algorithmId'] as String,
      outputSizeBits: json['outputSizeBits'] as int?,
      parameters: Map.unmodifiable(
        (json['parameters'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'algorithm': algorithm.wireName,
        'algorithmId': algorithmId,
        if (outputSizeBits != null) 'outputSizeBits': outputSizeBits,
        if (parameters.isNotEmpty) 'parameters': _sortedStringMap(parameters),
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicDigestDescriptor copyWith({
    CryptographicDigestAlgorithm? algorithm,
    String? algorithmId,
    int? outputSizeBits,
    Map<String, String>? parameters,
    Map<String, String>? metadata,
  }) {
    return CryptographicDigestDescriptor(
      algorithm: algorithm ?? this.algorithm,
      algorithmId: algorithmId ?? this.algorithmId,
      outputSizeBits: outputSizeBits ?? this.outputSizeBits,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicDigestDescriptor &&
          algorithm == other.algorithm &&
          algorithmId == other.algorithmId &&
          outputSizeBits == other.outputSizeBits &&
          trustMapEquals(parameters, other.parameters) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        algorithm,
        algorithmId,
        outputSizeBits,
        Object.hashAll(parameters.entries),
        Object.hashAll(metadata.entries),
      );
}

/// Declarative signature algorithm descriptor — does not sign or verify.
class CryptographicSignatureDescriptor {
  const CryptographicSignatureDescriptor({
    required this.algorithm,
    required this.algorithmId,
    required this.keyType,
    required this.format,
    this.parameters = const {},
    this.metadata = const {},
  });

  final CryptographicSignatureAlgorithm algorithm;
  final String algorithmId;
  final CryptographicKeyType keyType;
  final CryptographicSignatureFormat format;
  final Map<String, String> parameters;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm.wireName,
        'algorithmId': algorithmId,
        'keyType': keyType.wireName,
        'format': format.wireName,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicSignatureDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicSignatureDescriptor(
      algorithm: CryptographicSignatureAlgorithmX.fromWireName(
        json['algorithm'] as String,
      ),
      algorithmId: json['algorithmId'] as String,
      keyType: CryptographicKeyTypeX.fromWireName(json['keyType'] as String),
      format: CryptographicSignatureFormatX.fromWireName(
        json['format'] as String,
      ),
      parameters: Map.unmodifiable(
        (json['parameters'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'algorithm': algorithm.wireName,
        'algorithmId': algorithmId,
        'keyType': keyType.wireName,
        'format': format.wireName,
        if (parameters.isNotEmpty) 'parameters': _sortedStringMap(parameters),
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicSignatureDescriptor copyWith({
    CryptographicSignatureAlgorithm? algorithm,
    String? algorithmId,
    CryptographicKeyType? keyType,
    CryptographicSignatureFormat? format,
    Map<String, String>? parameters,
    Map<String, String>? metadata,
  }) {
    return CryptographicSignatureDescriptor(
      algorithm: algorithm ?? this.algorithm,
      algorithmId: algorithmId ?? this.algorithmId,
      keyType: keyType ?? this.keyType,
      format: format ?? this.format,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicSignatureDescriptor &&
          algorithm == other.algorithm &&
          algorithmId == other.algorithmId &&
          keyType == other.keyType &&
          format == other.format &&
          trustMapEquals(parameters, other.parameters) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        algorithm,
        algorithmId,
        keyType,
        format,
        Object.hashAll(parameters.entries),
        Object.hashAll(metadata.entries),
      );
}
