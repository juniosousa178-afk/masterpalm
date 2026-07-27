/// Canonical edge types supported by the Graph Engine.
enum GraphEdgeType {
  contains,
  imports,
  extendsType,
  implementsType,
  mixesIn,
  declares,
  calls,
  readsFrom,
  writesTo,
  accesses,
  dependsOn,
}

extension GraphEdgeTypeX on GraphEdgeType {
  String get wireName => name;

  static GraphEdgeType fromWireName(String value) {
    return GraphEdgeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown GraphEdgeType: $value'),
    );
  }
}
