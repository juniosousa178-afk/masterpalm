// Configuração compile-time de ambiente (R8.4.33). Sem RC/Hive.

import 'package:master_palm/core/produto_stock_write_enforcement.dart';

/// Ambientes suportados.
enum MpEnvironment {
  production,
  qa,
  development,
}

/// Configuração explícita via --dart-define (compile-time).
class MpEnvironmentConfig {
  MpEnvironmentConfig._();

  static const String _envRaw =
      String.fromEnvironment('MP_ENVIRONMENT', defaultValue: 'production');
  static const String _useEmulatorsRaw =
      String.fromEnvironment('MP_USE_FIREBASE_EMULATORS', defaultValue: 'false');

  static const String authEmulatorHost =
      String.fromEnvironment('MP_AUTH_EMULATOR_HOST', defaultValue: '');
  static const String firestoreEmulatorHost =
      String.fromEnvironment('MP_FIRESTORE_EMULATOR_HOST', defaultValue: '');
  static const String functionsEmulatorHost =
      String.fromEnvironment('MP_FUNCTIONS_EMULATOR_HOST', defaultValue: '');
  static const String storageEmulatorHost =
      String.fromEnvironment('MP_STORAGE_EMULATOR_HOST', defaultValue: '');

  /// ProjectId exclusivo do ambiente QA Web E2E (nunca produção).
  static const String qaProjectId = 'masterpalm-r8433-web-e2e-local';

  /// ProjectId de produção.
  static const String productionProjectId = 'masterpalm-58c46';

  static MpEnvironment get environment {
    switch (_envRaw.trim().toLowerCase()) {
      case 'qa':
        return MpEnvironment.qa;
      case 'development':
      case 'dev':
        return MpEnvironment.development;
      case 'production':
      case 'prod':
        return MpEnvironment.production;
      default:
        return MpEnvironment.production;
    }
  }

  static bool get useFirebaseEmulators =>
      _useEmulatorsRaw.trim().toLowerCase() == 'true';

  static bool get isProduction => environment == MpEnvironment.production;
  static bool get isQa => environment == MpEnvironment.qa;
  static bool get isDevelopment => environment == MpEnvironment.development;

  /// Falha se build production tiver flags de emulator.
  static void assertProductionBuildSafe() {
    if (!isProduction) return;
    if (useFirebaseEmulators) {
      throw StateError(
        'PRODUCTION_EMULATOR_CONFIGURATION_BLOCKED: '
        'MP_USE_FIREBASE_EMULATORS=true em MP_ENVIRONMENT=production',
      );
    }
    final hosts = [
      authEmulatorHost,
      firestoreEmulatorHost,
      functionsEmulatorHost,
      storageEmulatorHost,
    ];
    for (final h in hosts) {
      if (h.trim().isNotEmpty) {
        throw StateError(
          'PRODUCTION_EMULATOR_CONFIGURATION_BLOCKED: host emulator definido ($h)',
        );
      }
    }
  }

  /// Bloqueia projectId de produção em qualquer fluxo emulator/QA.
  static void assertQaProjectSafe(String projectId) {
    if (projectId == productionProjectId ||
        projectId.contains(productionProjectId)) {
      throw StateError(
        'WEB_E2E_SYNTHETIC_SEED_PRODUCTION_BLOCKED: projectId=$projectId',
      );
    }
    if (isQa && projectId != qaProjectId) {
      throw StateError(
        'QA projectId inesperado: $projectId (esperado $qaProjectId)',
      );
    }
  }

  /// Validação mínima de build_number para manifest Web.
  static void assertBuildNumberCompatible(int buildNumber) {
    if (buildNumber <= 0) {
      throw ArgumentError('build_number deve ser inteiro positivo');
    }
    if (buildNumber < kMinStockRevisionClientVersion) {
      throw ArgumentError(
        'build_number $buildNumber < kMinStockRevisionClientVersion '
        '($kMinStockRevisionClientVersion)',
      );
    }
  }
}
