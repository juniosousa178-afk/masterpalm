import '../models/observability/telemetry_enums.dart';

/// Registry of telemetry definitions. Frozen after bootstrap.
class TelemetryRegistry {
  TelemetryRegistry();

  final Set<TelemetryComponent> _components = {};
  final Set<TelemetryOperation> _operations = {};
  final Set<TelemetryEventType> _eventTypes = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void registerComponent(TelemetryComponent component) {
    _ensureMutable();
    if (_components.contains(component)) {
      throw StateError('Duplicate component: ${component.wireName}');
    }
    _components.add(component);
  }

  void registerOperation(TelemetryOperation operation) {
    _ensureMutable();
    if (_operations.contains(operation)) {
      throw StateError('Duplicate operation: ${operation.wireName}');
    }
    _operations.add(operation);
  }

  void registerEventType(TelemetryEventType eventType) {
    _ensureMutable();
    if (_eventTypes.contains(eventType)) {
      throw StateError('Duplicate event type: ${eventType.wireName}');
    }
    _eventTypes.add(eventType);
  }

  void freeze() => _frozen = true;

  List<TelemetryComponent> get components {
    final list = _components.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    return List.unmodifiable(list);
  }

  List<TelemetryOperation> get operations {
    final list = _operations.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    return List.unmodifiable(list);
  }

  List<TelemetryEventType> get eventTypes {
    final list = _eventTypes.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    return List.unmodifiable(list);
  }

  void _ensureMutable() {
    if (_frozen) throw StateError('TelemetryRegistry is frozen');
  }

  static void registerFoundation(TelemetryRegistry registry) {
    for (final c in TelemetryComponent.values) {
      registry.registerComponent(c);
    }
    for (final o in TelemetryOperation.values) {
      registry.registerOperation(o);
    }
    for (final t in TelemetryEventType.values) {
      registry.registerEventType(t);
    }
  }
}
