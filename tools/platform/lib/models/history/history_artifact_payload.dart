/// Versioned JSON payload for a [HistoryArtifact].
class HistoryArtifactPayload {
  const HistoryArtifactPayload({
    required this.encoding,
    required this.data,
  });

  static const String jsonEncoding = 'json';

  final String encoding;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'encoding': encoding,
        'data': data,
      };

  factory HistoryArtifactPayload.fromJson(Map<String, dynamic> json) {
    return HistoryArtifactPayload(
      encoding: json['encoding'] as String? ?? jsonEncoding,
      data: Map<String, dynamic>.from(json['data'] as Map),
    );
  }
}
