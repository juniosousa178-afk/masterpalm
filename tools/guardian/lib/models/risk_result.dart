enum RiskLevel { green, yellow, red, blocking }

class RiskItem {
  RiskItem({
    required this.file,
    required this.level,
    required this.reason,
    this.method,
  });

  final String file;
  final String? method;
  final RiskLevel level;
  final String reason;

  Map<String, dynamic> toJson() => {
        'file': file,
        if (method != null) 'method': method,
        'level': level.name,
        'reason': reason,
      };
}

class RiskResult {
  RiskResult({required this.items, required this.overall});

  final List<RiskItem> items;
  final RiskLevel overall;

  Map<String, dynamic> toJson() => {
        'overall': overall.name,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
