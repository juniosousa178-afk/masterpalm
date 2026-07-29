// Guard de hosts/portas emulator — fail-closed QA Web E2E (R8.4.40).

import 'package:http/http.dart' as http;

import 'mp_environment_config.dart';

const Set<String> _blockedProductionMarkers = {
  MpEnvironmentConfig.productionProjectId,
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'firebaseapp.com',
};

const Set<String> _allowedLocalHosts = {
  'localhost',
  '127.0.0.1',
  '::1',
  '0:0:0:0:0:0:0:1',
};

/// Normaliza host (trim, lowercase).
String normalizeQaEmulatorHost(String host) => host.trim().toLowerCase();

/// Parse `host:port` com validação fail-closed.
({String host, int port}) parseQaEmulatorHostPort(
  String raw, {
  required String label,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw StateError('QA_EMULATOR_HOST_EMPTY: $label');
  }
  for (final blocked in _blockedProductionMarkers) {
    if (trimmed.toLowerCase().contains(blocked.toLowerCase())) {
      throw StateError('QA_PRODUCTION_ENDPOINT_BLOCKED: $label=$raw');
    }
  }
  final parts = trimmed.split(':');
  if (parts.length != 2) {
    throw FormatException('QA_EMULATOR_HOST_INVALID: $label=$raw');
  }
  final host = normalizeQaEmulatorHost(parts[0]);
  if (host == 'host.docker.internal') {
    throw StateError('QA_EMULATOR_HOST_BLOCKED: host.docker.internal');
  }
  if (!_allowedLocalHosts.contains(host)) {
    throw StateError('QA_EMULATOR_HOST_NOT_LOCAL: $label host=$host');
  }
  final port = int.tryParse(parts[1].trim());
  if (port == null || port <= 0 || port > 65535) {
    throw FormatException('QA_EMULATOR_PORT_INVALID: $label=$raw');
  }
  return (host: host, port: port);
}

/// Valida ambiente QA + emulators obrigatórios antes de qualquer Firebase init.
void assertQaBootstrapEnvironment() {
  if (!MpEnvironmentConfig.isQa) {
    throw StateError('QA_BOOTSTRAP_ENV_INVALID: MP_ENVIRONMENT != qa');
  }
  if (!MpEnvironmentConfig.useFirebaseEmulators) {
    throw StateError(
      'QA_BOOTSTRAP_EMULATORS_REQUIRED: MP_USE_FIREBASE_EMULATORS != true',
    );
  }
  MpEnvironmentConfig.assertQaProjectSafe(MpEnvironmentConfig.qaProjectId);

  for (final entry in <String, String>{
    'auth': MpEnvironmentConfig.authEmulatorHost,
    'firestore': MpEnvironmentConfig.firestoreEmulatorHost,
  }.entries) {
    parseQaEmulatorHostPort(entry.value, label: entry.key);
  }

  final optional = <String, String>{
    'functions': MpEnvironmentConfig.functionsEmulatorHost,
    'storage': MpEnvironmentConfig.storageEmulatorHost,
  };
  for (final entry in optional.entries) {
    if (entry.value.trim().isEmpty) continue;
    parseQaEmulatorHostPort(entry.value, label: entry.key);
  }
}

/// Confirma que o emulator responde HTTP antes de conectar SDK.
Future<void> assertQaEmulatorReachable(
  String hostPort, {
  required String label,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final parsed = parseQaEmulatorHostPort(hostPort, label: label);
  final uri = Uri(scheme: 'http', host: parsed.host, port: parsed.port);
  try {
    final res = await http.get(uri).timeout(timeout);
    if (res.statusCode >= 500) {
      throw StateError(
        'QA_EMULATOR_UNREACHABLE: $label HTTP ${res.statusCode}',
      );
    }
  } catch (e) {
    if (e is StateError) rethrow;
    throw StateError('QA_EMULATOR_UNREACHABLE: $label ($hostPort) — $e');
  }
}
