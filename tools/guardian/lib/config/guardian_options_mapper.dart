import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../guardian_config.dart';

/// Maps Guardian YAML config to Platform [GuardianOptions] without merging types.
class GuardianOptionsMapper {
  const GuardianOptionsMapper._();

  static GuardianOptions fromExecution({
    required GuardianConfig config,
    bool simulationOnly = true,
  }) {
    return GuardianOptions(
      simulationOnly: simulationOnly,
      configDirName: 'config',
    );
  }
}
