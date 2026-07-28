import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/config/mp_environment_config.dart';

void main() {
  group('WEB_PRODUCTION_ENVIRONMENT_GUARD (compile-time defaults)', () {
    test('production defaults não usam emulators', () {
      // Valores default do build production (sem dart-define QA).
      expect(MpEnvironmentConfig.environment, MpEnvironment.production);
      expect(MpEnvironmentConfig.useFirebaseEmulators, isFalse);
      expect(MpEnvironmentConfig.authEmulatorHost, isEmpty);
      expect(MpEnvironmentConfig.firestoreEmulatorHost, isEmpty);
      MpEnvironmentConfig.assertProductionBuildSafe();
    });

    test('QA projectId bloqueia produção', () {
      expect(
        () => MpEnvironmentConfig.assertQaProjectSafe('masterpalm-58c46'),
        throwsStateError,
      );
      expect(
        () => MpEnvironmentConfig.assertQaProjectSafe(
          MpEnvironmentConfig.qaProjectId,
        ),
        returnsNormally,
      );
    });
  });
}
