/// Shared risk classification model for platform consumers.
enum PlatformRiskLevel { low, medium, high, critical }

class PlatformRiskItem {
  const PlatformRiskItem({
    required this.id,
    required this.level,
    required this.message,
    this.source,
    this.metadata = const {},
  });

  final String id;
  final PlatformRiskLevel level;
  final String message;
  final String? source;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level.name,
        'message': message,
        if (source != null) 'source': source,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

class PlatformRiskResult {
  const PlatformRiskResult({
    required this.overall,
    required this.items,
    this.score,
  });

  final PlatformRiskLevel overall;
  final List<PlatformRiskItem> items;
  final double? score;

  Map<String, dynamic> toJson() => {
        'overall': overall.name,
        'items': items.map((e) => e.toJson()).toList(),
        if (score != null) 'score': score,
      };
}
