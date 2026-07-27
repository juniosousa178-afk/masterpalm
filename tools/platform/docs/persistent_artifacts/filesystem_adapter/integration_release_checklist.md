# Controlled Filesystem Integration Release Checklist

- [ ] `masterpalm_platform.dart` não exporta tipos concretos de filesystem.
- [ ] `masterpalm_platform_filesystem.dart` exporta tipos concretos e helpers de registro.
- [ ] `PersistentArtifactBackendRegistry` sem default backend.
- [ ] Gate de ambiente bloqueia `productionEligible=false` em produção.
- [ ] `PlatformPersistentArtifactProvider` exige `backendId` em operações físicas.
- [ ] `evaluate` e `evaluateAndPublish` sem chamadas físicas implícitas.
- [ ] `deleteContent` não usado como deleção filesystem (usar quarentena física).
- [ ] `ObservablePersistentArtifactProvider` delega operações físicas sem path/payload em metadata pública.
- [ ] Recovery inspector só ativo com `enableRecoveryInspector=true`.
- [ ] `dart analyze lib` limpo.
- [ ] `dart test test/persistent_artifacts` verde.
- [ ] `dart test` verde.
