/// Taxonomy category for a metric definition.
enum MetricCategory {
  graphStructure,
  nodeDistribution,
  edgeDistribution,
  dependency,
  connectivity,
  cycle,
  storageAccess,
  callableStructure,
  importedGuardian,
  importedAst,
}

extension MetricCategoryX on MetricCategory {
  String get wireName => name;

  static MetricCategory fromWireName(String value) {
    return MetricCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown MetricCategory: $value'),
    );
  }
}
