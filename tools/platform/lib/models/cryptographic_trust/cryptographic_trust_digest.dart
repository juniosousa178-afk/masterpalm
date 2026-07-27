import 'cryptographic_trust_algorithm_descriptors.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Pre-computed digest reference — does not compute hashes or prove authorship.
///
/// [createdAt] is operational/transient and excluded from [toComparableJson].
class CryptographicDigest {
  const CryptographicDigest({
    required this.descriptor,
    required this.value,
    required this.encoding,
    required this.subjectId,
    this.createdAt,
    this.metadata = const {},
  });

  final CryptographicDigestDescriptor descriptor;
  final String value;
  final String encoding;
  final String subjectId;
  final String? createdAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'descriptor': descriptor.toJson(),
        'value': value,
        'encoding': encoding,
        'subjectId': subjectId,
        if (createdAt != null) 'createdAt': createdAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicDigest.fromJson(Map<String, dynamic> json) {
    return CryptographicDigest(
      descriptor: CryptographicDigestDescriptor.fromJson(
        json['descriptor'] as Map<String, dynamic>,
      ),
      value: json['value'] as String,
      encoding: json['encoding'] as String,
      subjectId: json['subjectId'] as String,
      createdAt: json['createdAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'descriptor': descriptor.toComparableJson(),
        'value': value,
        'encoding': encoding,
        'subjectId': subjectId,
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicDigest copyWith({
    CryptographicDigestDescriptor? descriptor,
    String? value,
    String? encoding,
    String? subjectId,
    String? createdAt,
    Map<String, String>? metadata,
  }) {
    return CryptographicDigest(
      descriptor: descriptor ?? this.descriptor,
      value: value ?? this.value,
      encoding: encoding ?? this.encoding,
      subjectId: subjectId ?? this.subjectId,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicDigest &&
          descriptor == other.descriptor &&
          value == other.value &&
          encoding == other.encoding &&
          subjectId == other.subjectId &&
          createdAt == other.createdAt &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        descriptor,
        value,
        encoding,
        subjectId,
        createdAt,
        Object.hashAll(metadata.entries),
      );
}
