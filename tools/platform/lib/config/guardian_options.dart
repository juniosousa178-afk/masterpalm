/// Options for Guardian integration via Platform Core.
class GuardianOptions {
  const GuardianOptions({
    this.simulationOnly = true,
    this.configDirName = 'config',
  });

  final bool simulationOnly;
  final String configDirName;

  GuardianOptions copyWith({
    bool? simulationOnly,
    String? configDirName,
  }) {
    return GuardianOptions(
      simulationOnly: simulationOnly ?? this.simulationOnly,
      configDirName: configDirName ?? this.configDirName,
    );
  }
}
