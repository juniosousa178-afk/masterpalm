/// Canonical node types supported by the Graph Engine.
enum GraphNodeType {
  project,
  package,
  library,
  file,
  clazz,
  mixinType,
  enumType,
  extensionType,
  method,
  constructor,
  function,
  field,
  firestoreCollection,
  hiveBox,
  screen,
  widget,
  service,
  repository,
  externalType,
}

extension GraphNodeTypeX on GraphNodeType {
  String get wireName => switch (this) {
        GraphNodeType.enumType => 'enum',
        GraphNodeType.clazz => 'class',
        GraphNodeType.mixinType => 'mixin',
        GraphNodeType.extensionType => 'extension',
        _ => name,
      };

  static GraphNodeType fromWireName(String value) {
    switch (value) {
      case 'enum':
        return GraphNodeType.enumType;
      case 'class':
        return GraphNodeType.clazz;
      case 'mixin':
        return GraphNodeType.mixinType;
      case 'extension':
        return GraphNodeType.extensionType;
      default:
        return GraphNodeType.values.firstWhere(
          (e) => e.name == value,
          orElse: () => throw FormatException('Unknown GraphNodeType: $value'),
        );
    }
  }
}
